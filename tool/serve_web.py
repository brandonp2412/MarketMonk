import argparse
import json
import re
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

YAHOO = "https://query1.finance.yahoo.com"
NASDAQ = "https://api.nasdaq.com"
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/125 Safari/537.36"
cache = {}
cache_lock = threading.Lock()
yahoo_blocked_until = 0.0


def fetch_json(url):
    request = urllib.request.Request(url, headers={
        "User-Agent": USER_AGENT,
        "Accept": "application/json, text/plain, */*",
        "Origin": "https://www.nasdaq.com",
    })
    with urllib.request.urlopen(request, timeout=12) as response:
        return json.load(response)


def nasdaq_data(path, params):
    url = NASDAQ + path + "?" + urllib.parse.urlencode(params)
    result = fetch_json(url)
    if not isinstance(result, dict) or result.get("data") is None:
        raise ValueError("Nasdaq did not return market data")
    return result["data"]


def search_fallback(query):
    data = nasdaq_data("/api/autocomplete/slookup/10", {"search": query})
    quotes = []
    for entry in data:
        asset = str(entry.get("asset") or "").upper()
        if asset not in ("STOCKS", "ETF", "ETFS"):
            continue
        symbol = str(entry.get("symbol") or "")
        if not symbol:
            continue
        quotes.append({
            "symbol": symbol,
            "shortname": str(entry.get("name") or symbol).strip(),
            "longname": str(entry.get("name") or symbol).strip(),
            "exchange": str(entry.get("exchange") or "NASDAQ"),
            "quoteType": "ETF" if asset in ("ETF", "ETFS") else "EQUITY",
        })
    return {"quotes": quotes}


def number(value):
    if isinstance(value, (float, int)):
        return float(value)
    try:
        return float(str(value).replace("$", "").replace(",", "").strip())
    except (TypeError, ValueError):
        return None


def chart_fallback(symbol, parameters):
    now = datetime.now(timezone.utc)
    period1 = parameters.get("period1", [None])[0]
    period2 = parameters.get("period2", [None])[0]
    if period1 is not None:
        since = datetime.fromtimestamp(int(period1), timezone.utc)
    else:
        raw_range = parameters.get("range", ["1mo"])[0]
        duration = re.fullmatch(r"(\d+)(d|mo|y)", raw_range)
        if not duration:
            raise ValueError("Invalid chart date range")
        count = min(int(duration.group(1)), 100)
        days = count * {"d": 1, "mo": 31, "y": 366}[duration.group(2)]
        since = now - timedelta(days=days)
    until = datetime.fromtimestamp(int(period2), timezone.utc) if period2 else now
    if since >= until or (until - since).days > 36525:
        raise ValueError("Invalid chart period")
    interval = parameters.get("interval", ["1d"])[0]
    use_intraday = interval in ("1m", "2m", "5m", "15m", "30m") and (until - since).days < 2
    bars = []
    if use_intraday:
        data = nasdaq_data(
            "/api/quote/" + urllib.parse.quote(symbol, safe="") + "/chart",
            {"assetclass": "stocks"},
        )
        for point in data.get("chart") or []:
            stamp = point.get("x")
            price = number(point.get("y"))
            if isinstance(stamp, (int, float)) and price is not None and price > 0:
                bars.append((int(stamp) // 1000, price, price, price, price, 0))
    else:
        data = nasdaq_data(
            "/api/quote/" + urllib.parse.quote(symbol, safe="") + "/historical",
            {
                "assetclass": "stocks",
                "limit": "5000",
                "fromdate": since.strftime("%Y-%m-%d"),
                "todate": until.strftime("%Y-%m-%d"),
            },
        )
        rows = (data.get("tradesTable") or {}).get("rows") or []
        for row in rows:
            try:
                stamp = int(datetime.strptime(row["date"], "%m/%d/%Y").replace(tzinfo=timezone.utc).timestamp())
            except (KeyError, ValueError, TypeError):
                continue
            o, h, l, c = (number(row.get(key)) for key in ("open", "high", "low", "close"))
            v = number(row.get("volume"))
            if all(value is not None and value > 0 for value in (o, h, l, c)):
                bars.append((stamp, o, h, l, c, max(0, int(v or 0))))
    bars.sort(key=lambda row: row[0])
    if not bars:
        raise ValueError("No Nasdaq data for this symbol and range")
    return {
        "chart": {
            "error": None,
            "result": [{
                "meta": {
                    "currency": "USD",
                    "symbol": symbol,
                    "source": "Nasdaq",
                    "instrumentType": "EQUITY",
                    "regularMarketPrice": bars[-1][4],
                    "regularMarketTime": bars[-1][0],
                },
                "timestamp": [bar[0] for bar in bars],
                "indicators": {
                    "quote": [{
                        "open": [bar[1] for bar in bars],
                        "high": [bar[2] for bar in bars],
                        "low": [bar[3] for bar in bars],
                        "close": [bar[4] for bar in bars],
                        "volume": [bar[5] for bar in bars],
                    }],
                    "adjclose": [{"adjclose": [bar[4] for bar in bars]}],
                },
            }],
        }
    }


def get_market_data(path, query):
    global yahoo_blocked_until
    parameters = urllib.parse.parse_qs(query)
    if path == "/v1/finance/search":
        q = parameters.get("q", [""])[0].strip()
        if not 0 < len(q) <= 50:
            raise ValueError("Invalid search term")
        fallback = lambda: search_fallback(q)
    elif path.startswith("/v8/finance/chart/"):
        symbol = urllib.parse.unquote(path.removeprefix("/v8/finance/chart/"))
        if not re.fullmatch(r"[A-Za-z0-9._^=-]{1,48}", symbol):
            raise ValueError("Invalid ticker symbol")
        fallback = lambda: chart_fallback(symbol, parameters)
    else:
        raise ValueError("Unsupported finance endpoint")

    if time.monotonic() >= yahoo_blocked_until:
        try:
            yahoo_url = YAHOO + path + ("?" + query if query else "")
            return fetch_json(yahoo_url)
        except urllib.error.HTTPError as error:
            if error.code == 429:
                yahoo_blocked_until = time.monotonic() + 300
        except (OSError, ValueError):
            pass
    return fallback()


class WebHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlsplit(self.path)
        if not parsed.path.startswith("/api/finance"):
            return super().do_GET()
        path = parsed.path.removeprefix("/api/finance")
        key = (path, parsed.query)
        with cache_lock:
            entry = cache.get(key)
        if entry and entry[0] > time.monotonic():
            data = entry[1]
        else:
            try:
                data = json.dumps(get_market_data(path, parsed.query), separators=(",", ":")).encode()
            except ValueError as error:
                return self.api_error(422, str(error))
            except (urllib.error.URLError, OSError, KeyError, TypeError) as error:
                return self.api_error(503, "Market data unavailable")
            with cache_lock:
                if len(cache) > 256:
                    cache.clear()
                cache[key] = (time.monotonic() + 60, data)
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def api_error(self, status, message):
        data = json.dumps({"error": message}).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)


def main():
    parser = argparse.ArgumentParser(description="Serve MarketMonk web with the same-origin finance gateway")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--directory", type=Path, default=Path(__file__).resolve().parent.parent / "build/web")
    args = parser.parse_args()
    if not args.directory.joinpath("index.html").is_file():
        parser.error("Build web first using: flutter build web")
    with ThreadingHTTPServer((args.host, args.port), partial(WebHandler, directory=str(args.directory))) as server:
        print(f"MarketMonk web: http://{args.host}:{args.port}", flush=True)
        server.serve_forever()


if __name__ == "__main__":
    main()
