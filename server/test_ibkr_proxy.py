import json
import threading
import unittest
from datetime import date
from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
from types import SimpleNamespace

from ibkr_proxy import (
    ClientPortalIbkrClient,
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
    }
    values.update(overrides)
    return Config(**values)


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


class FailingClient:
    def ensure_account_visible(self) -> None:
        raise IbkrError("IBKR Client Portal Gateway is awaiting browser authentication")

    def portfolio(self):
        raise AssertionError("not reached")

    def historical(self, symbol, years):
        raise AssertionError("not reached")


class RecordingIbkrClient(ClientPortalIbkrClient):
    def __init__(self, account_id="U1234567"):
        self._config = config(account_id=account_id)
        self.endpoints = []

    def _get(self, endpoint):
        self.endpoints.append(endpoint)
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
            SimpleNamespace(tag="NetLiquidation", value="1000", currency="USD"),
            SimpleNamespace(tag="CashBalance", value="100", currency="USD"),
        ]

    def reqHistoricalData(self, contract, **kwargs):
        self.historical_request = (contract, kwargs)
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
        self.assertEqual(portfolio["summary"]["netliquidation"]["value"], 1000)
        self.assertEqual(portfolio["ledger"]["USD"]["cashbalance"], 100)
        self.assertTrue(fake.disconnected)
        host, port, kwargs = fake.connect_kwargs
        self.assertEqual((host, port), ("127.0.0.1", 4003))
        self.assertTrue(kwargs["readonly"])
        self.assertEqual(kwargs["account"], "U1234567")
        self.assertEqual(kwargs["fetchFields"], 9)

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

    def test_native_historical_rejects_non_held_symbol(self):
        fake = FakeNativeIb()
        client = NativeIbkrClient(
            config(backend="native", tws_port=4003), ib_factory=lambda: fake
        )

        with self.assertRaisesRegex(IbkrError, "current stock positions only"):
            client.historical("MSFT", 1)

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
