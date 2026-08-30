import json
import threading
import unittest
from http.client import HTTPConnection
from http.server import ThreadingHTTPServer

from ibkr_proxy import (
    Config,
    IbkrClient,
    IbkrError,
    _mask_account,
    _normalize_position,
    make_handler,
)


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


class FailingClient:
    def ensure_account_visible(self) -> None:
        raise IbkrError("IBKR Client Portal Gateway is awaiting browser authentication")

    def portfolio(self):
        raise AssertionError("not reached")


class RecordingIbkrClient(IbkrClient):
    def __init__(self, account_id="U1234567"):
        self._config = Config(
            gateway_url="https://127.0.0.1:5000/v1/api",
            account_id=account_id,
            bind="127.0.0.1",
            port=8091,
            token="x" * 32,
            verify_gateway_tls=False,
        )
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


class ProxyTests(unittest.TestCase):
    def test_normalizes_official_portfolio2_shape(self):
        position = _normalize_position(
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

    def test_portfolio_uses_only_documented_read_only_endpoints(self):
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
        self.assertTrue(portfolio["read_only"])

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
