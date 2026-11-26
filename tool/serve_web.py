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
finance_fetch_slots = threading.BoundedSemaphore(8)
yahoo_blocked_until = 0.0

IBKR_ENDPOINTS = {
    "/v1/health": frozenset(),
    "/v1/portfolio": frozenset(),
    "/v1/historical": frozenset({"symbol", "years"}),
    "/v1/intraday": frozenset({"symbol", "days"}),
    "/v1/intraday/portfolio": frozenset({"days"}),
    "/v1/performance": frozenset({"period"}),
    "/v1/trades": frozenset({"days"}),
}
MAX_IBKR_RESPONSE = 16 * 1024 * 1024


def normalized_ibkr_upstream(value):
    value = value.strip()
    try:
        uri = urllib.parse.urlsplit(value)
        port = uri.port
    except ValueError as error:
        raise ValueError("Invalid IBKR upstream URL") from error
    if (
        not uri.hostname or uri.username or uri.password or uri.query or uri.fragment
        or uri.scheme not in ("https", "http")
        or (uri.scheme == "http" and uri.hostname not in
            ("localhost", "127.0.0.1", "::1"))
        or any(segment in (".", "..") for segment in uri.path.split("/"))
        or uri.path.startswith("//")
        or (port is not None and port < 1)
    ):
        raise ValueError("IBKR upstream must be HTTPS or explicitly allowlisted loopback HTTP")
    return urllib.parse.urlunsplit((
        uri.scheme, uri.netloc.lower(), uri.path.rstrip("/"), "", ""
    ))


def ibkr_request_url(upstream, path, query):
    allowed_params = IBKR_ENDPOINTS.get(path)
    if allowed_params is None:
        raise ValueError("Unsupported read-only IBKR endpoint")
    try:
        parameters = urllib.parse.parse_qs(query, strict_parsing=True)
    except ValueError as error:
        raise ValueError("Invalid IBKR query") from error
    if set(parameters) - allowed_params or any(
        len(values) != 1 or len(values[0]) > 80 for values in parameters.values()
    ):
        raise ValueError("Unsupported IBKR query")
    if "symbol" in parameters and not re.fullmatch(
        r"[A-Za-z0-9._^-]{1,48}", parameters["symbol"][0]
    ):
        raise ValueError("Invalid IBKR symbol")
    for name, limit in (("years", 10), ("days", 3650)):
        if name in parameters:
            raw = parameters[name][0]
            if not raw.isdigit() or not 1 <= int(raw) <= limit:
                raise ValueError("Invalid IBKR " + name)
    if "period" in parameters and parameters["period"][0] not in (
        "1D", "7D", "MTD", "1M", "YTD", "1Y"
    ):
        raise ValueError("Invalid IBKR performance period")
    return upstream + path + ("?" + urllib.parse.urlencode(parameters, doseq=True)
                              if parameters else "")


class _NoIbkrRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        return None


_ibkr_opener = urllib.request.build_opener(_NoIbkrRedirects)


def fetch_ibkr(upstream, path, query, bearer):
    url = ibkr_request_url(upstream, path, query)
    request = urllib.request.Request(url, headers={
        "Authorization": bearer,
        "Accept": "application/json",
        "User-Agent": USER_AGENT,
    })
    try:
        with _ibkr_opener.open(request, timeout=75) as response:
            payload = response.read(MAX_IBKR_RESPONSE + 1)
            status = response.status
    except urllib.error.HTTPError as error:
        status = error.code
        payload = error.read(MAX_IBKR_RESPONSE + 1)
        try:
            json.loads(payload)
        except (ValueError, UnicodeDecodeError):
            payload = json.dumps({"detail": "IBKR returned HTTP " + str(status)}).encode()
    if len(payload) > MAX_IBKR_RESPONSE:
        raise ValueError("IBKR response exceeded size limit")
    return status, payload


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
    if any(len(values) != 1 for values in parameters.values()):
        raise ValueError("Repeated finance query parameter")
    if path == "/v1/finance/search":
        if set(parameters) != {"q"}:
            raise ValueError("Unsupported search query")
        q = parameters.get("q", [""])[0].strip()
        if not 0 < len(q) <= 50:
            raise ValueError("Invalid search term")
        fallback = lambda: search_fallback(q)
    elif path.startswith("/v8/finance/chart/"):
        if set(parameters) - {"range", "interval", "period1", "period2", "includePrePost"}:
            raise ValueError("Unsupported chart query")
        for key in ("period1", "period2"):
            if key in parameters and not re.fullmatch(r"[0-9]{1,11}", parameters[key][0]):
                raise ValueError("Invalid chart timestamp")
        if "range" in parameters and not re.fullmatch(r"[0-9]{1,3}(d|mo|y)", parameters["range"][0]):
            raise ValueError("Invalid chart range")
        if "interval" in parameters and parameters["interval"][0] not in {"1m", "2m", "5m", "15m", "30m", "1d", "1wk", "1mo"}:
            raise ValueError("Invalid chart interval")
        if "includePrePost" in parameters and parameters["includePrePost"][0] not in {"true", "false"}:
            raise ValueError("Invalid pre/post setting")
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
    def __init__(self, *args, ibkr_upstreams=frozenset(), finance_origin=None, **kwargs):
        self.ibkr_upstreams = ibkr_upstreams
        self.finance_origin = finance_origin
        super().__init__(*args, **kwargs)

    def end_headers(self):
        if (self.finance_origin and
                self.headers.get("Origin") == self.finance_origin and
                urllib.parse.urlsplit(self.path).path.startswith("/api/finance/")):
            self.send_header("Access-Control-Allow-Origin", self.finance_origin)
            self.send_header("Vary", "Origin")
        super().end_headers()

    def do_HEAD(self):
        if self.finance_origin:
            return self.api_error(405, "GET required")
        return super().do_HEAD()

    def do_GET(self):
        parsed = urllib.parse.urlsplit(self.path)
        if self.finance_origin:
            if not parsed.path.startswith("/api/finance/"):
                return self.api_error(404, "Not found")
            if self.headers.get("Origin") != self.finance_origin:
                return self.api_error(403, "Origin not permitted")
            if len(parsed.query) > 512:
                return self.api_error(422, "Invalid market data query")
        if parsed.path.startswith("/api/ibkr/"):
            return self.serve_ibkr(parsed)
        if not parsed.path.startswith("/api/finance"):
            return super().do_GET()
        path = parsed.path.removeprefix("/api/finance")
        key = (path, parsed.query)
        with cache_lock:
            entry = cache.get(key)
        if entry and entry[0] > time.monotonic():
            data = entry[1]
        else:
            if not finance_fetch_slots.acquire(blocking=False):
                return self.api_error(429, "Market data busy; retry shortly")
            try:
                data = json.dumps(get_market_data(path, parsed.query), separators=(",", ":")).encode()
            except ValueError as error:
                return self.api_error(422, str(error))
            except (urllib.error.URLError, OSError, KeyError, TypeError) as error:
                return self.api_error(503, "Market data unavailable")
            finally:
                finance_fetch_slots.release()
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

    def serve_ibkr(self, parsed):
        if not self.ibkr_upstreams:
            return self.api_error(503, "IBKR web gateway is not configured")
        upstream = self.headers.get("X-MarketMonk-Ibkr-Upstream", "")
        try:
            upstream = normalized_ibkr_upstream(upstream)
        except ValueError:
            return self.api_error(403, "Invalid IBKR upstream")
        if upstream not in self.ibkr_upstreams:
            return self.api_error(403, "IBKR upstream is not allowlisted")
        bearer = self.headers.get("Authorization", "")
        if not bearer.startswith("Bearer ") or not 8 < len(bearer) < 8192:
            return self.api_error(401, "IBKR bearer token is required")
        try:
            path = parsed.path.removeprefix("/api/ibkr")
            ibkr_request_url(upstream, path, parsed.query)
            status, payload = fetch_ibkr(
                upstream, path, parsed.query, bearer,
            )
        except ValueError as error:
            return self.api_error(422, str(error))
        except (urllib.error.URLError, OSError):
            return self.api_error(502, "IBKR upstream unavailable")
        self.respond_json(status, payload)

    def respond_json(self, status, data):
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def api_error(self, status, message):
        self.respond_json(status, json.dumps({"error": message}).encode())


def main():
    parser = argparse.ArgumentParser(description="Serve MarketMonk web with the same-origin finance gateway")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--directory", type=Path, default=Path(__file__).resolve().parent.parent / "build/web")
    parser.add_argument(
        "--ibkr-upstream", action="append", default=[],
        help="Explicitly permitted self-hosted IBKR read-only API base URL",
    )
    parser.add_argument("--finance-origin", help="Serve only public finance GETs for this browser origin")
    args = parser.parse_args()
    if args.finance_origin and args.ibkr_upstream:
        parser.error("Public finance-only mode cannot serve IBKR")
    try:
        ibkr_upstreams = frozenset(
            normalized_ibkr_upstream(value) for value in args.ibkr_upstream
        )
    except ValueError as error:
        parser.error(str(error))
    if not args.finance_origin and not args.directory.joinpath("index.html").is_file():
        parser.error("Build web first using: flutter build web")
    with ThreadingHTTPServer(
        (args.host, args.port),
        partial(WebHandler, directory=str(args.directory), ibkr_upstreams=ibkr_upstreams, finance_origin=args.finance_origin),
    ) as server:
        print(f"MarketMonk web: http://{args.host}:{args.port}", flush=True)
        server.serve_forever()


if __name__ == "__main__":
    main()
