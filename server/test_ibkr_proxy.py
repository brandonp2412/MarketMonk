import asyncio
import json
import time
import sqlite3
import tempfile
import threading
import unittest
from datetime import date, datetime, timezone
from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
from pathlib import Path
from types import SimpleNamespace
from urllib.parse import parse_qs, urlparse

from ibkr_proxy import (
    ClientPortalIbkrClient,
    CommandPerformanceClient,
    CommandTransactionsClient,
    Config,
    IbkrError,
    NativeIbkrClient,
    _mask_account,
    _normalize_web_position,
    make_handler,
)


def config(**overrides):
    values = {
        "backend": "client_portal",
        "account_id": "U1234567",
        "bind": "127.0.0.1",
        "port": 8091,
        "token": "x" * 32,
        "gateway_url": "https://127.0.0.1:5000/v1/api",
        "verify_gateway_tls": False,
        "tws_host": "127.0.0.1",
        "tws_port": 4001,
        "tws_client_id": 97,
        "performance_command": None,
        "transactions_command": None,
        "performance_cache_database": None,
    }
    values.update(overrides)
    return Config(**values)


def raw_performance(account_id="U1234567"):
    return {
        "nav": {
            "dates": ["20260818", "20260916"],
            "data": [
                {
                    "id": account_id,
                    "navs": [321000, 333000],
                    "cashFlows": [0, 10000],
                    "startNAV": {"date": "20260817", "val": 320000},
                    "baseCurrency": "NZD",
                }
            ],
        },
        "cps": {
            "dates": ["20260818", "20260916"],
            "data": [
                {
                    "id": account_id,
                    "returns": [0.001, 0.0549],
                    "baseCurrency": "NZD",
                }
            ],
        },
        "pm": "TWR",
    }


def raw_trades(account_id="U1234567"):
    return {
        "read_only": True,
        "source": "flex",
        "account_id": account_id,
        "account": "****4567",
        "days": 3650,
        "available": True,
        "available_from": "2022-01-01",
        "includes_real_time": False,
        "trades": [
            {
                "symbol": "AAPL",
                "name": "APPLE INC",
                "currency": "USD",
                "conid": 265598,
                "quantity": -5,
                "price": 192.26,
                "trade_type": "close",
                "trade_date": "2026-09-30",
                "realized_pnl": 123.45,
                "commission": 1.25,
            }
        ],
    }


class FakeClient:
    def ensure_account_visible(self) -> None:
        return None

    def portfolio(self):
        return {
            "account": "****1234",
            "read_only": True,
            "summary": {"netliquidation": {"amount": 1000}},
            "ledger": {"BASE": {"cashbalance": 100}},
            "positions": [],
        }

    def intraday(self, symbol, days):
        result = self.historical(symbol, 1)
        result["interval"] = "1m" if days == 1 else "15m"
        result["candles"][0]["date"] = "2026-08-28T14:30:00+00:00"
        return result

    def intraday_portfolio(self, days):
        return {"series": [self.intraday("AAPL", days)], "errors": {},
                "interval": "1m" if days == 1 else "15m"}

    def historical(self, symbol, years):
        return {
            "read_only": True,
            "source": "native",
            "symbol": symbol,
            "currency": "USD",
            "candles": [
                {
                    "date": "2026-08-28",
                    "open": 198,
                    "high": 202,
                    "low": 197,
                    "close": 200,
                    "volume": 1000,
                }
            ],
        }

    def transactions(self, days):
        return {
            "read_only": True,
            "source": "client_portal",
            "account": "****1234",
            "days": days,
            "includes_real_time": True,
            "trades": [
                {
                    "symbol": "AAPL",
                    "name": "Apple Inc",
                    "currency": "USD",
                    "conid": 265598,
                    "quantity": 5,
                    "price": 192.26,
                    "trade_type": "open",
                    "trade_date": "2023-12-11",
                }
            ],
        }

    def performance(self, period):
        return {
            "read_only": True,
            "source": "client_portal",
            "period": period,
            "measure": "TWR",
            "currency": "NZD",
            "start_date": "20260817",
            "start_nav": 320000,
            "dates": ["20260818", "20260916"],
            "nav": [321000, 333000],
            "return_dates": ["20260818", "20260916"],
            "returns": [0.001, 0.0549],
        }


class FailingClient:
    def ensure_account_visible(self) -> None:
        raise IbkrError("IBKR Client Portal Gateway is awaiting browser authentication")

    def portfolio(self):
        raise AssertionError("not reached")

    def historical(self, symbol, years):
        raise AssertionError("not reached")

    def performance(self, period):
        raise AssertionError("not reached")


class RecordingIbkrClient(ClientPortalIbkrClient):
    def __init__(self, account_id="U1234567"):
        self._config = config(account_id=account_id)
        self.endpoints = []
        self.posts = []
        self._performance_cache = {}
        self._transactions_cache = {}

    def _get(self, endpoint):
        self.endpoints.append(endpoint)
        if endpoint.startswith("iserver/marketdata/history?"):
            return {
                "volumeFactor": 100,
                "data": [
                    {
                        "o": 198,
                        "h": 202,
                        "l": 197,
                        "c": 200,
                        "v": 12.34,
                        "t": 1787961600000,
                    }
                ],
            }
        responses = {
            "portfolio/accounts": [{"accountId": "U1234567"}],
            "portfolio2/U1234567/positions": [
                {
                    "position": 2,
                    "conid": 265598,
                    "avgCost": 190,
                    "currency": "USD",
                    "description": "AAPL",
                    "marketPrice": 200,
                    "marketValue": 400,
                    "realizedPnl": 0,
                    "unrealizedPnl": 20,
                    "secType": "STK",
                }
            ],
            "portfolio/U1234567/summary": {
                "accountcode": {"value": "U1234567"}
            },
            "portfolio/U1234567/ledger": {},
        }
        return responses[endpoint]

    def _post(self, endpoint, body):
        self.posts.append((endpoint, body))
        if endpoint == "pa/transactions":
            return {
                "includesRealTime": True,
                "transactions": [
                    {
                        "date": "Mon Dec 11 00:00:00 EST 2023",
                        "cur": "USD",
                        "pr": 192.26,
                        "qty": 5,
                        "acctid": "U1234567",
                        "amt": -961.3,
                        "conid": 265598,
                        "type": "Buy",
                        "desc": "Apple Inc",
                    }
                ],
            }
        return {
            "nav": {
                "dates": ["20260818", "20260916"],
                "data": [
                    {
                        "id": "U1234567",
                        "navs": [321000, 333000],
                        "cashFlows": [0, 10000],
                        "startNAV": {"date": "20260817", "val": 320000},
                        "baseCurrency": "NZD",
                    }
                ],
            },
            "cps": {
                "dates": ["20260818", "20260916"],
                "data": [
                    {
                        "id": "U1234567",
                        "returns": [0.001, 0.0549],
                        "baseCurrency": "NZD",
                    }
                ],
            },
            "pm": "TWR",
        }


class FakeNativeIb:
    def __init__(self):
        self.connected = False
        self.connect_kwargs = None
        self.disconnected = False
        self.historical_request = None

    def connect(self, host, port, **kwargs):
        self.connected = True
        self.connect_kwargs = (host, port, kwargs)

    def disconnect(self):
        self.disconnected = True

    def managedAccounts(self):
        return ["U1234567"]

    def portfolio(self, account):
        assert account == "U1234567"
        contract = SimpleNamespace(
            symbol="AAPL",
            secType="STK",
            currency="USD",
            primaryExchange="NASDAQ",
            exchange="SMART",
            conId=265598,
        )
        return [
            SimpleNamespace(
                contract=contract,
                position=2,
                marketPrice=200,
                marketValue=400,
                averageCost=190,
                unrealizedPNL=20,
                realizedPNL=4,
            )
        ]

    def accountValues(self, account):
        assert account == "U1234567"
        return [
            SimpleNamespace(tag="NetLiquidation", value="1700", currency="NZD"),
            SimpleNamespace(
                tag="NetLiquidationByCurrency", value="1700", currency="BASE"
            ),
            SimpleNamespace(
                tag="NetLiquidationByCurrency", value="1000", currency="USD"
            ),
            SimpleNamespace(tag="CashBalance", value="100", currency="USD"),
        ]

    def run(self, awaitable):
        return asyncio.run(awaitable)

    async def reqHistoricalDataAsync(self, contract, **kwargs):
        return self.reqHistoricalData(contract, **kwargs)

    def reqHistoricalData(self, contract, **kwargs):
        self.historical_request = (contract, kwargs)
        if kwargs["barSizeSetting"] != "1 day":
            return [
                SimpleNamespace(
                    date=datetime(2026, 8, 28, 14, minute, tzinfo=timezone.utc),
                    open=198, high=202, low=197, close=200, volume=1234,
                )
                for minute in (30, 31)
            ]
        return [
            SimpleNamespace(
                date=date(2026, 8, 28),
                open=198,
                high=202,
                low=197,
                close=200,
                volume=1234,
            )
        ]


class ProxyTests(unittest.TestCase):
    def test_native_portfolio_intraday_reuses_one_connection_for_all_holdings(self):
        class CountingIb(FakeNativeIb):
            connects = 0
            histories = 0
            def connect(self, *args, **kwargs):
                self.connects += 1
                return super().connect(*args, **kwargs)
            def portfolio(self, account):
                first = super().portfolio(account)[0]
                second = SimpleNamespace(**vars(first))
                second.contract = SimpleNamespace(**vars(first.contract))
                second.contract.symbol = "MSFT"
                return [first, second]
            def reqHistoricalData(self, *args, **kwargs):
                self.histories += 1
                return super().reqHistoricalData(*args, **kwargs)
        fake = CountingIb()
        client = NativeIbkrClient(config(backend="native"), ib_factory=lambda: fake)
        result = client.intraday_portfolio(5)
        self.assertEqual([item["symbol"] for item in result["series"]], ["AAPL", "MSFT"])
        self.assertEqual(result["errors"], {})
        self.assertEqual(fake.connects, 1)
        self.assertEqual(fake.histories, 2)
        self.assertTrue(fake.disconnected)

    def test_native_intraday_retrieval_overlaps_independent_stocks(self):
        class ConcurrentIb(FakeNativeIb):
            def __init__(self):
                super().__init__()
                self.active = 0
                self.peak = 0

            def portfolio(self, account):
                first = super().portfolio(account)[0]
                result = []
                for symbol in ("AAPL", "MSFT", "NVDA", "AMZN"):
                    item = SimpleNamespace(**vars(first))
                    item.contract = SimpleNamespace(**vars(first.contract))
                    item.contract.symbol = symbol
                    result.append(item)
                return result

            async def reqHistoricalDataAsync(self, contract, **kwargs):
                self.active += 1
                self.peak = max(self.peak, self.active)
                try:
                    await asyncio.sleep(0.02)
                    return self.reqHistoricalData(contract, **kwargs)
                finally:
                    self.active -= 1

        fake = ConcurrentIb()
        client = NativeIbkrClient(config(backend="native"), ib_factory=lambda: fake)
        result = client.intraday_portfolio(1)
        self.assertEqual(fake.peak, 3)
        self.assertEqual(
            [item["symbol"] for item in result["series"]],
            ["AAPL", "MSFT", "NVDA", "AMZN"],
        )
        self.assertEqual(result["errors"], {})
        self.assertTrue(fake.disconnected)

    def test_web_intraday_retrieval_overlaps_independent_stocks(self):
        class ConcurrentWeb(RecordingIbkrClient):
            def __init__(self):
                super().__init__()
                self.active = 0
                self.peak = 0
                self.lock = threading.Lock()

            def _get(self, endpoint):
                result = super()._get(endpoint)
                if endpoint.endswith("/positions"):
                    return [
                        dict(result[0], description=symbol, conid=i)
                        for i, symbol in enumerate(("AAPL", "MSFT", "NVDA", "AMZN"), 1)
                    ]
                return result

            def historical(self, symbol, years, *, intraday_days=None, _positions=None):
                with self.lock:
                    self.active += 1
                    self.peak = max(self.peak, self.active)
                try:
                    time.sleep(0.02)
                    if symbol == "NVDA":
                        raise IbkrError("missing market data")
                    return {"symbol": symbol, "candles": []}
                finally:
                    with self.lock:
                        self.active -= 1

        client = ConcurrentWeb()
        result = client.intraday_portfolio(5)
        self.assertEqual(client.peak, 3)
        self.assertEqual([item["symbol"] for item in result["series"]], ["AAPL", "MSFT", "AMZN"])
        self.assertEqual(result["errors"], {"NVDA": "missing market data"})
        self.assertEqual(client.endpoints.count("portfolio/accounts"), 1)
        self.assertEqual(client.endpoints.count("portfolio2/U1234567/positions"), 1)

    def test_web_portfolio_intraday_reads_accounts_and_positions_once(self):
        class MultipleStocks(RecordingIbkrClient):
            def _get(self, endpoint):
                result = super()._get(endpoint)
                if endpoint.endswith("/positions"):
                    return result + [dict(result[0], description="MSFT", conid=123)]
                return result
        client = MultipleStocks()
        result = client.intraday_portfolio(1)
        self.assertEqual(len(result["series"]), 2)
        self.assertEqual(client.endpoints.count("portfolio/accounts"), 1)
        self.assertEqual(client.endpoints.count("portfolio2/U1234567/positions"), 1)
        self.assertEqual(result["interval"], "1m")


    def test_native_requests_share_one_connection_at_a_time(self):
        from concurrent.futures import ThreadPoolExecutor

        entered = threading.Event()
        release = threading.Event()
        second_entered = threading.Event()
        state_lock = threading.Lock()
        active = 0
        maximum = 0
        connections = 0

        class BlockingIb(FakeNativeIb):
            def connect(self, host, port, **kwargs):
                nonlocal active, maximum, connections
                with state_lock:
                    active += 1
                    maximum = max(maximum, active)
                    connections += 1
                    first = connections == 1
                if first:
                    entered.set()
                    if not release.wait(5):
                        raise RuntimeError("test connection was not released")
                else:
                    second_entered.set()
                super().connect(host, port, **kwargs)

            def disconnect(self):
                nonlocal active
                with state_lock:
                    active -= 1
                super().disconnect()

        client = NativeIbkrClient(config(backend="native"), ib_factory=BlockingIb)
        with ThreadPoolExecutor(max_workers=2) as executor:
            first = executor.submit(client.portfolio)
            try:
                self.assertTrue(entered.wait(5))
                second = executor.submit(client.intraday, "AAPL", 5)
                self.assertFalse(second_entered.wait(0.1))
            finally:
                release.set()
            self.assertTrue(first.result(timeout=5)["positions"])
            self.assertTrue(second.result(timeout=5)["candles"])
        self.assertEqual(maximum, 1)
        self.assertEqual(active, 0)


    def test_normalizes_official_portfolio2_shape(self):
        position = _normalize_web_position(
            {
                "position": 12.0,
                "conid": "9408",
                "avgCost": 266.2,
                "currency": "USD",
                "description": "MCD",
                "marketPrice": 258.82,
                "marketValue": 3105.84,
                "realizedPnl": 4.0,
                "unrealizedPnl": 88.5,
                "secType": "STK",
                "sector": "Consumer, Cyclical",
                "group": "Retail",
                "timestamp": 1717444668,
            }
        )
        self.assertEqual(position["symbol"], "MCD")
        self.assertEqual(position["security_type"], "STK")
        self.assertEqual(position["market_price"], 258.82)
        self.assertEqual(position["market_value"], 3105.84)
        self.assertEqual(position["average_cost"], 266.2)
        self.assertEqual(position["unrealized_pnl"], 88.5)

    def test_masks_account(self):
        self.assertEqual(_mask_account("U1234567"), "****4567")

    def test_auto_selects_the_only_visible_account(self):
        client = RecordingIbkrClient(account_id=None)

        portfolio = client.portfolio()

        self.assertEqual(portfolio["account"], "****4567")

    def test_client_portal_uses_documented_read_only_endpoints(self):
        client = RecordingIbkrClient()

        portfolio = client.portfolio()

        self.assertEqual(
            client.endpoints,
            [
                "portfolio/accounts",
                "portfolio2/U1234567/positions",
                "portfolio/U1234567/summary",
                "portfolio/U1234567/ledger",
            ],
        )
        self.assertEqual(portfolio["positions"][0]["symbol"], "AAPL")
        self.assertEqual(portfolio["summary"]["accountcode"]["value"], "****4567")
        self.assertEqual(portfolio["source"], "client_portal")
        self.assertTrue(portfolio["read_only"])

    def test_client_portal_reads_historical_candles_for_held_stock(self):
        client = RecordingIbkrClient()

        history = client.historical("AAPL", 1)

        self.assertEqual(history["source"], "client_portal")
        self.assertEqual(history["currency"], "USD")
        self.assertEqual(history["candles"][0]["date"], "2026-08-28")
        self.assertEqual(history["candles"][0]["close"], 200)
        self.assertEqual(history["candles"][0]["volume"], 1234)
        self.assertTrue(
            any(endpoint.startswith("iserver/marketdata/history?") for endpoint in client.endpoints)
        )

    def test_client_portal_intraday_preserves_utc_time_and_bar_size(self):
        for days, period, bar in [(1, "1d", "1min"), (5, "1w", "15min")]:
            with self.subTest(days=days):
                client = RecordingIbkrClient()
                history = client.intraday("AAPL", days)
                self.assertEqual(history["interval"], "1m" if days == 1 else "15m")
                expected = datetime.fromtimestamp(1787961600, tz=timezone.utc).isoformat()
                self.assertEqual(history["candles"][0]["date"], expected)
                self.assertEqual(history["candles"][0]["volume"], 1234)
                endpoint = next(value for value in client.endpoints
                                if value.startswith("iserver/marketdata/history?"))
                query = parse_qs(urlparse(endpoint).query)
                self.assertEqual(query["period"], [period])
                self.assertEqual(query["bar"], [bar])
                self.assertEqual(query["outsideRth"], ["false"])

    def test_client_portal_returns_current_position_trade_history(self):
        client = RecordingIbkrClient()

        history = client.transactions(3650)

        self.assertTrue(history["available"])
        self.assertTrue(history["includes_real_time"])
        self.assertEqual(history["trades"][0]["symbol"], "AAPL")
        self.assertEqual(history["trades"][0]["name"], "Apple Inc")
        self.assertEqual(history["trades"][0]["quantity"], 5)
        self.assertEqual(history["trades"][0]["price"], 192.26)
        self.assertEqual(history["trades"][0]["trade_date"], "2023-12-11")
        expected_call = (
            "pa/transactions",
            {
                "acctIds": ["U1234567"],
                "conids": [265598],
                "currency": "USD",
                "days": 3650,
            },
        )
        self.assertIn(expected_call, client.posts)
        client.transactions(3650)
        self.assertEqual(client.posts.count(expected_call), 1)

    def test_client_portal_prefers_command_backed_trade_history(self):
        calls = []
        transactions_client = SimpleNamespace(
            transactions=lambda days: calls.append(days) or raw_trades()
        )
        client = ClientPortalIbkrClient(
            config(
                transactions_command=(
                    "/opt/ibkrbot/market-monk/bin/ibkr-daily-bot",
                    "web-trades",
                )
            ),
            transactions_client=transactions_client,
        )

        history = client.transactions(3650)

        self.assertEqual(calls, [3650])
        self.assertEqual(history["source"], "flex")
        self.assertTrue(history["available"])
        self.assertEqual(history["trades"][0]["symbol"], "AAPL")

    def test_client_portal_prefers_configured_performance_command(self):
        calls = []
        performance_client = SimpleNamespace(
            performance=lambda period: calls.append(period)
            or {
                "read_only": True,
                "source": "flex",
                "period": period,
                "measure": "TWR",
                "currency": "NZD",
                "dates": ["20260930"],
                "nav": [333000],
                "return_dates": ["20260930"],
                "returns": [0.0549],
            }
        )
        client = ClientPortalIbkrClient(
            config(
                performance_command=(
                    "/opt/ibkrbot/lumibot/bin/ibkr-lumibot",
                    "web-performance",
                )
            ),
            performance_client=performance_client,
        )

        performance = client.performance("1Y")

        self.assertEqual(calls, ["1Y"])
        self.assertEqual(performance["source"], "flex")
        self.assertEqual(performance["returns"][-1], 0.0549)

    def test_client_portal_returns_broker_twr_and_nav_history(self):
        client = RecordingIbkrClient()

        performance = client.performance("1M")

        self.assertEqual(performance["measure"], "TWR")
        self.assertEqual(performance["currency"], "NZD")
        self.assertEqual(performance["start_nav"], 320000)
        self.assertEqual(performance["nav"][-1], 333000)
        self.assertEqual(performance["cash_flows"], [0, 10000])
        self.assertEqual(performance["returns"][-1], 0.0549)
        self.assertEqual(
            client.posts,
            [("pa/performance", {"acctIds": ["U1234567"], "period": "1M"})],
        )

    def test_command_performance_client_normalizes_helper_output(self):
        calls = []

        def runner(command, **kwargs):
            calls.append((command, kwargs))
            return SimpleNamespace(
                returncode=0,
                stdout=json.dumps(raw_performance()),
                stderr="",
            )

        client = CommandPerformanceClient(
            config(
                backend="native",
                performance_command=("/opt/ibkrbot/app/bin/ibkr-daily-bot", "web-performance"),
            ),
            runner=runner,
        )

        performance = client.performance("1Y")

        self.assertEqual(performance["currency"], "NZD")
        self.assertEqual(performance["nav"][-1], 333000)
        self.assertEqual(performance["cash_flows"], [0, 10000])
        self.assertEqual(performance["returns"][-1], 0.0549)
        self.assertEqual(
            calls[0][0],
            [
                "/opt/ibkrbot/app/bin/ibkr-daily-bot",
                "web-performance",
                "--period",
                "1Y",
            ],
        )
        self.assertEqual(calls[0][1]["timeout"], 90)
        client.performance("1Y")
        self.assertEqual(len(calls), 1)

    def test_command_performance_client_reads_sqlalchemy_cache_without_helper(self):
        with tempfile.TemporaryDirectory() as directory:
            database = Path(directory) / "ibkr-state.sqlite3"
            connection = sqlite3.connect(database)
            connection.execute(
                """
                CREATE TABLE marketmonk_performance_cache (
                    account_id TEXT NOT NULL,
                    period TEXT NOT NULL,
                    fetched_at DATETIME NOT NULL,
                    payload JSON NOT NULL,
                    PRIMARY KEY (account_id, period)
                )
                """
            )
            connection.execute(
                """
                INSERT INTO marketmonk_performance_cache
                    (account_id, period, fetched_at, payload)
                VALUES (?, ?, ?, ?)
                """,
                (
                    "U1234567",
                    "1Y",
                    "2026-10-07 00:00:00",
                    json.dumps(raw_performance()),
                ),
            )
            connection.commit()
            connection.close()

            def runner(*_args, **_kwargs):
                self.fail("persistent cache hit must not launch helper")

            client = CommandPerformanceClient(
                config(
                    performance_command=("helper",),
                    performance_cache_database=str(database),
                ),
                runner=runner,
            )

            performance = client.performance("1Y")

            self.assertEqual(performance["dates"][-1], "20260916")
            self.assertEqual(performance["returns"][-1], 0.0549)

    def test_command_performance_client_rejects_wrong_account_output(self):
        client = CommandPerformanceClient(
            config(
                backend="native",
                performance_command=("ibkr-daily-bot", "web-performance"),
            ),
            runner=lambda *args, **kwargs: SimpleNamespace(
                returncode=0,
                stdout=json.dumps(raw_performance("U7654321")),
                stderr="",
            ),
        )

        with self.assertRaisesRegex(
            IbkrError,
            "no performance data for the configured account",
        ):
            client.performance("1Y")

    def test_command_transactions_client_returns_helper_history(self):
        calls = []

        def runner(command, **kwargs):
            calls.append((command, kwargs))
            return SimpleNamespace(
                returncode=0,
                stdout=json.dumps(raw_trades()),
                stderr="",
            )

        client = CommandTransactionsClient(
            config(
                backend="native",
                transactions_command=("ibkr-daily-bot", "web-trades"),
            ),
            runner=runner,
        )

        history = client.transactions(3650)

        self.assertTrue(history["available"])
        self.assertEqual(history["source"], "flex")
        self.assertEqual(history["trades"][0]["realized_pnl"], 123.45)
        self.assertEqual(
            calls[0][0],
            ["ibkr-daily-bot", "web-trades", "--days", "3650"],
        )
        self.assertEqual(calls[0][1]["timeout"], 180)
        client.transactions(3650)
        self.assertEqual(len(calls), 1)

    def test_command_transactions_client_rejects_wrong_account(self):
        client = CommandTransactionsClient(
            config(
                backend="native",
                transactions_command=("ibkr-daily-bot", "web-trades"),
            ),
            runner=lambda *args, **kwargs: SimpleNamespace(
                returncode=0,
                stdout=json.dumps(raw_trades("U9999999")),
                stderr="",
            ),
        )

        with self.assertRaisesRegex(IbkrError, "wrong account"):
            client.transactions(3650)

    def test_native_backend_prefers_configured_performance_command(self):
        client = NativeIbkrClient(
            config(
                backend="native",
                performance_command=("ibkr-daily-bot", "web-performance"),
            ),
            ib_factory=FakeNativeIb,
        )

        self.assertIsInstance(client._performance_client, CommandPerformanceClient)

    def test_native_backend_reads_portfolio_without_order_calls(self):
        fake = FakeNativeIb()
        client = NativeIbkrClient(
            config(backend="native", tws_port=4003), ib_factory=lambda: fake
        )

        portfolio = client.portfolio()

        self.assertEqual(portfolio["source"], "native")
        self.assertEqual(portfolio["account"], "****4567")
        self.assertEqual(portfolio["positions"][0]["symbol"], "AAPL")
        self.assertEqual(portfolio["positions"][0]["market_value"], 400)
        self.assertEqual(portfolio["positions"][0]["realized_pnl"], 4)
        self.assertEqual(portfolio["summary"]["netliquidation"]["value"], 1700)
        self.assertEqual(
            portfolio["summary"]["netliquidationbycurrency:usd"]["value"], 1000
        )
        self.assertEqual(portfolio["ledger"]["USD"]["cashbalance"], 100)
        self.assertTrue(fake.disconnected)
        host, port, kwargs = fake.connect_kwargs
        self.assertEqual((host, port), ("127.0.0.1", 4003))
        self.assertTrue(kwargs["readonly"])
        self.assertEqual(kwargs["account"], "U1234567")
        self.assertEqual(kwargs["fetchFields"], 9)

    def test_native_backend_delegates_performance_to_client_portal(self):
        fake = FakeNativeIb()
        performance_client = FakeClient()
        client = NativeIbkrClient(
            config(backend="native", tws_port=4003),
            ib_factory=lambda: fake,
            performance_client=performance_client,
        )

        performance = client.performance("1Y")

        self.assertEqual(performance["source"], "client_portal")
        self.assertEqual(performance["period"], "1Y")
        self.assertEqual(performance["returns"][-1], 0.0549)
        self.assertFalse(fake.connected)

    def test_native_backend_prefers_configured_transactions_command(self):
        client = NativeIbkrClient(
            config(
                backend="native",
                transactions_command=("ibkr-daily-bot", "web-trades"),
            ),
            ib_factory=FakeNativeIb,
        )

        self.assertIsInstance(client._transactions_client, CommandTransactionsClient)

    def test_native_backend_marks_transaction_history_unavailable(self):
        fake = FakeNativeIb()
        client = NativeIbkrClient(
            config(backend="native", tws_port=4003), ib_factory=lambda: fake
        )

        history = client.transactions(3650)

        self.assertEqual(history["source"], "native")
        self.assertEqual(history["days"], 3650)
        self.assertFalse(history["available"])
        self.assertEqual(history["trades"], [])
        self.assertFalse(fake.connected)

    def test_native_backend_reads_historical_candles_for_held_stock(self):
        fake = FakeNativeIb()
        client = NativeIbkrClient(
            config(backend="native", tws_port=4003), ib_factory=lambda: fake
        )

        history = client.historical("AAPL", 10)

        self.assertEqual(history["source"], "native")
        self.assertTrue(history["read_only"])
        self.assertEqual(history["symbol"], "AAPL")
        self.assertEqual(history["currency"], "USD")
        self.assertEqual(history["candles"][0]["date"], "2026-08-28")
        self.assertEqual(history["candles"][0]["close"], 200)
        self.assertEqual(history["candles"][0]["volume"], 1234)
        contract, kwargs = fake.historical_request
        self.assertEqual(contract.exchange, "SMART")
        self.assertEqual(kwargs["durationStr"], "10 Y")
        self.assertEqual(kwargs["barSizeSetting"], "1 day")
        self.assertEqual(kwargs["whatToShow"], "TRADES")
        self.assertTrue(kwargs["useRTH"])
        self.assertTrue(fake.disconnected)

    def test_native_intraday_preserves_multiple_bars_and_requests_utc(self):
        for days, duration, bar in [(1, "1 D", "1 min"), (5, "1 W", "15 mins")]:
            with self.subTest(days=days):
                fake = FakeNativeIb()
                client = NativeIbkrClient(config(backend="native"), ib_factory=lambda: fake)
                history = client.intraday("AAPL", days)
                self.assertEqual(len(history["candles"]), 2)
                self.assertEqual(history["candles"][0]["date"], "2026-08-28T14:30:00+00:00")
                self.assertEqual(history["candles"][1]["date"], "2026-08-28T14:31:00+00:00")
                _, kwargs = fake.historical_request
                self.assertEqual(kwargs["durationStr"], duration)
                self.assertEqual(kwargs["barSizeSetting"], bar)
                self.assertEqual(kwargs["formatDate"], 2)
                self.assertTrue(kwargs["useRTH"])
                self.assertTrue(fake.disconnected)

    def test_intraday_rejects_non_held_stocks_and_unsupported_ranges(self):
        for client in [RecordingIbkrClient(), NativeIbkrClient(
            config(backend="native"), ib_factory=FakeNativeIb
        )]:
            with self.assertRaisesRegex(IbkrError, "current stock positions only"):
                client.intraday("MSFT", 1)
            with self.assertRaisesRegex(IbkrError, "days must be 1 or 5"):
                client.intraday("AAPL", 30)

    def test_native_historical_rejects_non_held_symbol(self):
        fake = FakeNativeIb()
        client = NativeIbkrClient(
            config(backend="native", tws_port=4003), ib_factory=lambda: fake
        )

        with self.assertRaisesRegex(IbkrError, "current stock positions only"):
            client.historical("MSFT", 1)

    def test_intraday_http_validates_parameters_and_requires_authentication(self):
        server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(FakeClient(), "x" * 32))
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.shutdown)
        self.addCleanup(server.server_close)
        connection = HTTPConnection("127.0.0.1", server.server_port)
        self.addCleanup(connection.close)
        connection.request("GET", "/v1/intraday?symbol=AAPL")
        response = connection.getresponse()
        self.assertEqual(response.status, 401)
        response.read()
        for path in ["?symbol=AAPL&days=30", "?symbol=AAPL&days=bad", "?days=1"]:
            connection.request("GET", "/v1/intraday" + path,
                               headers={"Authorization": f"Bearer {'x' * 32}"})
            response = connection.getresponse()
            self.assertEqual(response.status, 400)
            response.read()
        for days in (1, 5):
            connection.request("GET", f"/v1/intraday?symbol=AAPL&days={days}",
                               headers={"Authorization": f"Bearer {'x' * 32}"})
            response = connection.getresponse()
            self.assertEqual(response.status, 200)
            body = json.loads(response.read())
            self.assertEqual(body["interval"], "1m" if days == 1 else "15m")
            self.assertEqual(body["candles"][0]["date"], "2026-08-28T14:30:00+00:00")

        connection.request("GET", "/v1/intraday/portfolio?days=5")
        response = connection.getresponse()
        self.assertEqual(response.status, 401)
        response.read()
        for days in ("30", "bad", "1", "5"):
            connection.request("GET", f"/v1/intraday/portfolio?days={days}",
                               headers={"Authorization": f"Bearer {'x' * 32}"})
            response = connection.getresponse()
            self.assertEqual(response.status, 200 if days in ("1", "5") else 400)
            body = json.loads(response.read())
            if response.status == 200:
                self.assertEqual(body["series"][0]["symbol"], "AAPL")
                self.assertEqual(body["interval"], "1m" if days == "1" else "15m")

    def test_http_api_requires_bearer_and_returns_portfolio(self):
        server = ThreadingHTTPServer(
            ("127.0.0.1", 0), make_handler(FakeClient(), "x" * 32)
        )
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.shutdown)
        self.addCleanup(server.server_close)

        connection = HTTPConnection("127.0.0.1", server.server_port)
        connection.request("GET", "/v1/portfolio")
        unauthorized = connection.getresponse()
        self.assertEqual(unauthorized.status, 401)
        unauthorized.read()

        connection.request(
            "GET",
            "/v1/portfolio",
            headers={"Authorization": f"Bearer {'x' * 32}"},
        )
        response = connection.getresponse()
        self.assertEqual(response.status, 200)
        body = json.loads(response.read())
        self.assertTrue(body["read_only"])
        self.assertEqual(body["account"], "****1234")

        connection.request(
            "GET",
            "/v1/historical?symbol=AAPL&years=10",
            headers={"Authorization": f"Bearer {'x' * 32}"},
        )
        historical = connection.getresponse()
        self.assertEqual(historical.status, 200)
        historical_body = json.loads(historical.read())
        self.assertEqual(historical_body["symbol"], "AAPL")
        self.assertEqual(historical_body["candles"][0]["close"], 200)

        connection.request(
            "GET",
            "/v1/trades?days=3650",
            headers={"Authorization": f"Bearer {'x' * 32}"},
        )
        trades = connection.getresponse()
        self.assertEqual(trades.status, 200)
        trades_body = json.loads(trades.read())
        self.assertEqual(trades_body["trades"][0]["symbol"], "AAPL")

        connection.request(
            "GET",
            "/v1/performance?period=12M",
            headers={"Authorization": f"Bearer {'x' * 32}"},
        )
        performance = connection.getresponse()
        self.assertEqual(performance.status, 200)
        performance_body = json.loads(performance.read())
        self.assertEqual(performance_body["period"], "1Y")
        self.assertEqual(performance_body["measure"], "TWR")
        self.assertEqual(performance_body["returns"][-1], 0.0549)
        connection.close()

    def test_health_surfaces_browser_authentication(self):
        server = ThreadingHTTPServer(
            ("127.0.0.1", 0), make_handler(FailingClient(), "x" * 32)
        )
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.shutdown)
        self.addCleanup(server.server_close)

        connection = HTTPConnection("127.0.0.1", server.server_port)
        connection.request(
            "GET",
            "/v1/health",
            headers={"Authorization": f"Bearer {'x' * 32}"},
        )
        response = connection.getresponse()
        self.assertEqual(response.status, 502)
        body = json.loads(response.read())
        self.assertIn("browser authentication", body["detail"])
        connection.close()


if __name__ == "__main__":
    unittest.main()
