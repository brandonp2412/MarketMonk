import importlib.util
import io
import http.client
import json
import threading
from functools import partial
from http.server import ThreadingHTTPServer
import urllib.error
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "marketmonk_web_gateway", Path(__file__).with_name("serve_web.py")
)
gateway = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gateway)


class WebGatewayTests(unittest.TestCase):
    def test_public_finance_gateway_is_origin_and_path_restricted(self):
        origin = "https://brandonp2412.github.io"
        server = ThreadingHTTPServer(
            ("127.0.0.1", 0),
            partial(gateway.WebHandler, directory=str(Path(__file__).parent),
                    finance_origin=origin),
        )
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            def call(path, request_origin):
                connection = http.client.HTTPConnection(
                    "127.0.0.1", server.server_address[1], timeout=3,
                )
                connection.request("GET", path, headers={"Origin": request_origin})
                response = connection.getresponse()
                result = response.status, response.getheader("Access-Control-Allow-Origin")
                response.read()
                connection.close()
                return result

            path = "/api/finance/v1/finance/search?q=ant"
            with patch.object(gateway, "get_market_data", return_value={"quotes": []}):
                self.assertEqual(call(path, origin), (200, origin))
                self.assertEqual(call(path, "https://evil.example"), (403, None))
                self.assertEqual(call("/api/ibkr/v1/portfolio", origin), (404, None))
                self.assertEqual(call("/serve_web.py", origin), (404, None))
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_search_fallback_returns_yahoo_compatible_results(self):
        with patch.object(gateway, "nasdaq_data", return_value=[
            {"symbol": "AAPL", "name": "Apple Inc.", "asset": "STOCKS"},
            {"symbol": "MUTF", "name": "Fund", "asset": "MUTUALFUNDS"},
        ]):
            result = gateway.search_fallback("AAPL")
        self.assertEqual(len(result["quotes"]), 1)
        self.assertEqual(result["quotes"][0]["quoteType"], "EQUITY")

    def test_daily_fallback_is_sorted_and_has_adjusted_closes(self):
        rows = [
            {"date": "11/18/2026", "close": "$351.20", "open": "$350.00",
             "high": "$352.00", "low": "$349.00", "volume": "1,200"},
            {"date": "11/17/2026", "close": "$345.00", "open": "$342.00",
             "high": "$346.00", "low": "$341.00", "volume": "1,100"},
        ]
        with patch.object(gateway, "nasdaq_data",
                          return_value={"tradesTable": {"rows": rows}}):
            response = gateway.chart_fallback(
                "AAPL", {"range": ["1mo"], "interval": ["1d"]}
            )
        series = response["chart"]["result"][0]
        self.assertEqual(
            series["indicators"]["quote"][0]["close"], [345.0, 351.2]
        )
        self.assertEqual(
            series["indicators"]["adjclose"][0]["adjclose"], [345.0, 351.2]
        )
        self.assertLess(series["timestamp"][0], series["timestamp"][1])

    def test_rejects_unsupported_paths_and_tickers(self):
        with self.assertRaises(ValueError):
            gateway.get_market_data("/admin", "")
        with self.assertRaises(ValueError):
            gateway.get_market_data("/v8/finance/chart/%2Fetc%2Fpasswd", "")
        with self.assertRaises(ValueError):
            gateway.get_market_data("/v1/finance/search", "q=")


class IbkrWebGatewayTests(unittest.TestCase):
    def test_upstreams_require_explicit_secure_allowlist(self):
        self.assertEqual(
            gateway.normalized_ibkr_upstream("https://IBKR.example.test/"),
            "https://ibkr.example.test",
        )
        for target in (
            "http://ibkr.example.test",
            "https://127.0.0.1@evil.test",
            "https://ibkr.example.test/../admin",
            "file:///etc/passwd",
            "https://ibkr.example.test?token=secret",
        ):
            with self.subTest(target=target), self.assertRaises(ValueError):
                gateway.normalized_ibkr_upstream(target)

    def test_only_read_only_ibkr_routes_and_valid_query_values_are_accepted(self):
        base = "https://ibkr.example.test"
        self.assertEqual(
            gateway.ibkr_request_url(base, "/v1/historical",
                                     "symbol=AAPL&years=2"),
            base + "/v1/historical?symbol=AAPL&years=2",
        )
        for path, query in (
            ("/v1/orders", ""),
            ("/v1/historical", "symbol=AAPL&years=0"),
            ("/v1/historical", "symbol=AAPL&years=11"),
            ("/v1/historical", "symbol=../admin&years=1"),
            ("/v1/portfolio", "url=http://127.0.0.1"),
            ("/v1/performance", "period=ALL"),
            ("/v1/historical", "symbol=AAPL&symbol=MSFT"),
        ):
            with self.subTest(path=path, query=query), self.assertRaises(ValueError):
                gateway.ibkr_request_url(base, path, query)

    def test_authorization_forwarded_only_as_header(self):
        class Response:
            status = 200

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return False

            def read(self, maximum):
                return b'{"status":"ok"}'

        with patch.object(gateway._ibkr_opener, "open", return_value=Response()) as send:
            status, data = gateway.fetch_ibkr(
                "https://ibkr.example.test",
                "/v1/historical",
                "symbol=AAPL&years=1",
                "Bearer opaque-test-token",
            )
        self.assertEqual((status, json.loads(data)), (200, {"status": "ok"}))
        request = send.call_args.args[0]
        self.assertEqual(request.full_url, "https://ibkr.example.test/v1/historical?symbol=AAPL&years=1")
        self.assertEqual(request.get_header("Authorization"), "Bearer opaque-test-token")
        self.assertNotIn("opaque-test-token", request.full_url)

    def test_rate_limit_http_status_survives_proxy(self):
        target = "https://ibkr.example.test/v1/historical?symbol=AAPL&years=1"
        failure = urllib.error.HTTPError(
            target, 429, "Too many requests", {},
            io.BytesIO(b'{"detail":"IBKR rate limited"}'),
        )
        with patch.object(gateway._ibkr_opener, "open", side_effect=failure):
            status, payload = gateway.fetch_ibkr(
                "https://ibkr.example.test", "/v1/historical",
                "symbol=AAPL&years=1", "Bearer fake-token",
            )
        self.assertEqual(status, 429)
        self.assertEqual(json.loads(payload)["detail"], "IBKR rate limited")

    def test_http_gateway_denies_unlisted_targets_and_proxies_allowed_requests(self):
        allowed = frozenset({"https://ibkr.example.test"})
        server = ThreadingHTTPServer(
            ("127.0.0.1", 0),
            partial(gateway.WebHandler, directory=str(Path(__file__).parent),
                    ibkr_upstreams=allowed),
        )
        server_thread = threading.Thread(target=server.serve_forever, daemon=True)
        server_thread.start()
        try:
            def call(target, path="/api/ibkr/v1/historical?symbol=AAPL&years=1",
                     bearer="Bearer fake-token"):
                connection = http.client.HTTPConnection(
                    "127.0.0.1", server.server_address[1], timeout=3,
                )
                connection.request("GET", path, headers={
                    "Authorization": bearer,
                    "X-MarketMonk-Ibkr-Upstream": target,
                })
                response = connection.getresponse()
                value = response.status, json.loads(response.read())
                connection.close()
                return value

            with patch.object(gateway, "fetch_ibkr", return_value=(
                200, b'{"symbol":"AAPL","currency":"USD","candles":[]}',
            )) as fetch:
                self.assertEqual(call("https://evil.example.test")[0], 403)
                self.assertEqual(call("https://ibkr.example.test",
                                      bearer="")[0], 401)
                self.assertEqual(call("https://ibkr.example.test",
                                      path="/api/ibkr/v1/orders")[0], 422)
                status, data = call("https://ibkr.example.test/")
                self.assertEqual(status, 200)
                self.assertEqual(data["symbol"], "AAPL")
                fetch.assert_called_once_with(
                    "https://ibkr.example.test", "/v1/historical",
                    "symbol=AAPL&years=1", "Bearer fake-token",
                )
        finally:
            server.shutdown()
            server.server_close()
            server_thread.join(timeout=5)


if __name__ == "__main__":
    unittest.main()
