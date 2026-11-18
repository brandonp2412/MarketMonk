import importlib.util
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "marketmonk_web_gateway", Path(__file__).with_name("serve_web.py")
)
gateway = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gateway)


class WebGatewayTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
