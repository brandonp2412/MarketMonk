#!/usr/bin/env python3
"""Read-only MarketMonk proxy for IBKR Client Portal or native TWS APIs."""

from __future__ import annotations

import argparse
import hmac
import ipaddress
import json
import math
import os
import ssl
import time
from dataclasses import dataclass
from datetime import date, datetime
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import Any, Callable
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, quote, urlparse
from urllib.request import HTTPSHandler, Request, build_opener


@dataclass(frozen=True)
class Config:
    backend: str
    account_id: str | None
    bind: str
    port: int
    token: str
    gateway_url: str
    verify_gateway_tls: bool
    tws_host: str
    tws_port: int
    tws_client_id: int

    @classmethod
    def from_env(cls) -> "Config":
        backend = os.getenv("IBKR_BACKEND", "client_portal").strip().lower()
        if backend not in {"client_portal", "native"}:
            raise ValueError("IBKR_BACKEND must be client_portal or native")

        gateway_url = os.getenv(
            "IBKR_GATEWAY_URL", "https://127.0.0.1:5000/v1/api"
        ).rstrip("/")
        account_id = os.getenv("IBKR_ACCOUNT_ID", "").strip() or None
        bind = os.getenv("MARKET_MONK_IBKR_BIND", "127.0.0.1").strip()
        port = int(os.getenv("MARKET_MONK_IBKR_PORT", "8091"))
        token = os.getenv("MARKET_MONK_IBKR_TOKEN", "").strip()
        tws_host = os.getenv("IBKR_TWS_HOST", "127.0.0.1").strip()
        tws_port = int(os.getenv("IBKR_TWS_PORT", "4001"))
        tws_client_id = int(os.getenv("IBKR_TWS_CLIENT_ID", "97"))

        if len(token) < 32:
            raise ValueError("MARKET_MONK_IBKR_TOKEN must be at least 32 characters")
        if not 1 <= port <= 65535:
            raise ValueError("MARKET_MONK_IBKR_PORT must be between 1 and 65535")
        if not 1 <= tws_port <= 65535:
            raise ValueError("IBKR_TWS_PORT must be between 1 and 65535")
        if not tws_host:
            raise ValueError("IBKR_TWS_HOST must not be empty")
        if tws_client_id < 0:
            raise ValueError("IBKR_TWS_CLIENT_ID must be non-negative")

        parsed = urlparse(gateway_url)
        if backend == "client_portal" and (
            parsed.scheme != "https" or not parsed.hostname
        ):
            raise ValueError("IBKR_GATEWAY_URL must be an https:// URL")

        verify_raw = os.getenv("IBKR_GATEWAY_VERIFY_TLS")
        if verify_raw is None:
            verify_gateway_tls = bool(parsed.hostname) and not _is_loopback(
                parsed.hostname
            )
        else:
            verify_gateway_tls = _parse_bool(verify_raw)

        return cls(
            backend=backend,
            account_id=account_id,
            bind=bind,
            port=port,
            token=token,
            gateway_url=gateway_url,
            verify_gateway_tls=verify_gateway_tls,
            tws_host=tws_host,
            tws_port=tws_port,
            tws_client_id=tws_client_id,
        )


class IbkrError(RuntimeError):
    pass


class ClientPortalIbkrClient:
    def __init__(self, config: Config):
        self._config = config
        context = ssl.create_default_context()
        if not config.verify_gateway_tls:
            context.check_hostname = False
            context.verify_mode = ssl.CERT_NONE
        self._opener = build_opener(HTTPSHandler(context=context))

    def ensure_account_visible(self) -> str:
        accounts = self._get("portfolio/accounts")
        if not isinstance(accounts, list):
            raise IbkrError("IBKR returned an invalid account list")
        visible = [account for item in accounts if (account := _account_id(item))]
        return _select_account(visible, self._config.account_id)

    def portfolio(self) -> dict[str, Any]:
        raw_account = self.ensure_account_visible()
        account = quote(raw_account, safe="")
        positions = self._get(f"portfolio2/{account}/positions")
        summary = self._get(f"portfolio/{account}/summary")
        ledger = self._get(f"portfolio/{account}/ledger")
        if not isinstance(positions, list):
            raise IbkrError("IBKR returned an invalid position list")
        if not isinstance(summary, dict) or not isinstance(ledger, dict):
            raise IbkrError("IBKR returned invalid account summary data")

        return {
            "account": _mask_account(raw_account),
            "read_only": True,
            "source": "client_portal",
            "summary": _sanitize_account(summary, raw_account),
            "ledger": _sanitize_account(ledger, raw_account),
            "positions": [_normalize_web_position(item) for item in positions],
        }

    def historical(self, symbol: str, years: int) -> dict[str, Any]:
        raise IbkrError(
            "IBKR historical candles require the native TWS / IB Gateway backend"
        )

    def _get(self, endpoint: str) -> Any:
        url = f"{self._config.gateway_url}/{endpoint.lstrip('/')}"
        request = Request(url, headers={"Accept": "application/json"}, method="GET")
        try:
            with self._opener.open(request, timeout=20) as response:
                return json.load(response)
        except HTTPError as error:
            if error.code in (401, 403):
                raise IbkrError(
                    "IBKR Client Portal Gateway is awaiting browser authentication"
                ) from error
            raise IbkrError(f"IBKR Gateway returned HTTP {error.code}") from error
        except URLError as error:
            raise IbkrError(f"Cannot reach IBKR Gateway: {error.reason}") from error
        except (json.JSONDecodeError, UnicodeDecodeError) as error:
            raise IbkrError("IBKR Gateway returned invalid JSON") from error


class NativeIbkrClient:
    def __init__(
        self,
        config: Config,
        ib_factory: Callable[[], Any] | None = None,
    ):
        self._config = config
        if ib_factory is None:
            try:
                from ib_async import IB
                from ib_async.ib import StartupFetch
            except ImportError as error:
                raise IbkrError(
                    "Native IBKR backend requires ib_async; install server/requirements.txt"
                ) from error
            ib_factory = IB
            self._startup_fetch = StartupFetch.POSITIONS | StartupFetch.ACCOUNT_UPDATES
        else:
            self._startup_fetch = 9
        self._ib_factory = ib_factory

    def ensure_account_visible(self) -> str:
        ib = self._connect()
        try:
            return self._select_account(ib)
        finally:
            ib.disconnect()

    def portfolio(self) -> dict[str, Any]:
        ib = self._connect()
        try:
            account = self._select_account(ib)
            items = list(ib.portfolio(account))
            values = list(ib.accountValues(account))
            return {
                "account": _mask_account(account),
                "read_only": True,
                "source": "native",
                "summary": _native_summary(values),
                "ledger": _native_ledger(values),
                "positions": [_normalize_native_position(item) for item in items],
            }
        except IbkrError:
            raise
        except Exception as error:
            raise IbkrError(f"IBKR TWS API portfolio read failed: {error}") from error
        finally:
            ib.disconnect()

    def historical(self, symbol: str, years: int) -> dict[str, Any]:
        ib = self._connect()
        try:
            account = self._select_account(ib)
            item = next(
                (
                    position
                    for position in ib.portfolio(account)
                    if str(getattr(position.contract, "symbol", "")).upper()
                    == symbol.upper()
                    and str(getattr(position.contract, "secType", "")).upper()
                    == "STK"
                ),
                None,
            )
            if item is None:
                raise IbkrError(
                    "IBKR historical candles are available for current stock positions only"
                )

            contract = item.contract
            if not str(getattr(contract, "exchange", "")).strip():
                contract.exchange = "SMART"

            bars = ib.reqHistoricalData(
                contract,
                endDateTime="",
                durationStr=f"{years} Y",
                barSizeSetting="1 day",
                whatToShow="TRADES",
                useRTH=True,
                formatDate=1,
                timeout=30,
            )
            if not bars:
                raise IbkrError(f"IBKR returned no historical candles for {symbol}")

            currency = str(getattr(contract, "currency", "") or "USD").strip()
            return {
                "read_only": True,
                "source": "native",
                "symbol": str(getattr(contract, "symbol", symbol)).strip(),
                "currency": currency,
                "candles": [_normalize_historical_bar(bar) for bar in bars],
            }
        except IbkrError:
            raise
        except Exception as error:
            raise IbkrError(f"IBKR TWS API historical read failed: {error}") from error
        finally:
            ib.disconnect()

    def _connect(self) -> Any:
        ib = self._ib_factory()
        try:
            ib.connect(
                self._config.tws_host,
                self._config.tws_port,
                clientId=self._config.tws_client_id,
                timeout=20,
                readonly=True,
                account=self._config.account_id or "",
                fetchFields=self._startup_fetch,
            )
            return ib
        except Exception as error:
            try:
                ib.disconnect()
            except Exception:
                pass
            raise IbkrError(f"Cannot reach IBKR TWS API: {error}") from error

    def _select_account(self, ib: Any) -> str:
        try:
            visible = list(ib.managedAccounts())
        except Exception as error:
            raise IbkrError(f"Cannot read IBKR managed accounts: {error}") from error
        return _select_account(visible, self._config.account_id)


def make_client(config: Config) -> Any:
    if config.backend == "native":
        return NativeIbkrClient(config)
    return ClientPortalIbkrClient(config)


def make_handler(client: Any, token: str) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        server_version = "MarketMonkIBKR/2"

        def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
            supplied = self.headers.get("Authorization", "")
            expected = f"Bearer {token}"
            if not hmac.compare_digest(supplied, expected):
                self._json(401, {"error": "unauthorized"})
                return

            parsed = urlparse(self.path)
            try:
                if parsed.path == "/v1/health":
                    client.ensure_account_visible()
                    self._json(200, {"status": "ok", "source": "ibkr"})
                elif parsed.path == "/v1/portfolio":
                    self._json(200, client.portfolio())
                elif parsed.path == "/v1/historical":
                    query = parse_qs(parsed.query)
                    symbol = (query.get("symbol") or [""])[0].strip()
                    if not symbol or len(symbol) > 32:
                        self._json(400, {"error": "invalid symbol"})
                        return
                    try:
                        years = int((query.get("years") or ["10"])[0])
                    except ValueError:
                        self._json(400, {"error": "invalid years"})
                        return
                    if not 1 <= years <= 10:
                        self._json(400, {"error": "years must be between 1 and 10"})
                        return
                    self._json(200, client.historical(symbol, years))
                else:
                    self._json(404, {"error": "not found"})
            except IbkrError as error:
                self._json(
                    502,
                    {"error": "IBKR unavailable", "detail": str(error)},
                )

        def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
            self._json(405, {"error": "method not allowed"})

        def log_message(self, format: str, *args: Any) -> None:
            print(f"{self.address_string()} - {format % args}")

        def _json(self, status: int, body: dict[str, Any]) -> None:
            payload = json.dumps(body, separators=(",", ":")).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(payload)

    return Handler


def _select_account(visible: list[str], configured: str | None) -> str:
    visible = [account.strip() for account in visible if account.strip()]
    if configured is not None:
        if configured not in visible:
            raise IbkrError("Configured IBKR account is not visible in this session")
        return configured
    if len(visible) == 1:
        return visible[0]
    if not visible:
        raise IbkrError("No IBKR accounts are visible in this session")
    raise IbkrError("Multiple IBKR accounts are visible; set IBKR_ACCOUNT_ID on the proxy")


def _normalize_web_position(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise IbkrError("IBKR returned an invalid position")
    symbol = _first_text(value, "description", "ticker", "contractDesc")
    security_type = _first_text(value, "secType", "assetClass")
    if not symbol or not security_type:
        raise IbkrError("IBKR position is missing its symbol or security type")

    return {
        "symbol": symbol,
        "security_type": security_type,
        "currency": _first_text(value, "currency") or "USD",
        "exchange": _first_text(value, "listingExchange"),
        "conid": _number(value.get("conid"), integer=True, default=0),
        "quantity": _number(value.get("position"), default=0.0),
        "market_price": _optional_number(value, "marketPrice", "mktPrice"),
        "market_value": _optional_number(value, "marketValue", "mktValue"),
        "average_cost": _optional_number(value, "avgCost", "avgPrice"),
        "unrealized_pnl": _optional_number(value, "unrealizedPnl"),
        "realized_pnl": _optional_number(value, "realizedPnl"),
        "sector": _first_text(value, "sector"),
        "group": _first_text(value, "group"),
        "timestamp": _number(value.get("timestamp"), integer=True, default=0),
    }


def _normalize_historical_bar(bar: Any) -> dict[str, Any]:
    raw_date = getattr(bar, "date", None)
    if isinstance(raw_date, datetime):
        candle_date = raw_date.date().isoformat()
    elif isinstance(raw_date, date):
        candle_date = raw_date.isoformat()
    else:
        text = str(raw_date or "").strip()
        if len(text) == 8 and text.isdigit():
            candle_date = f"{text[:4]}-{text[4:6]}-{text[6:]}"
        else:
            raise IbkrError("IBKR returned an invalid historical candle date")

    volume = _finite_optional(getattr(bar, "volume", None))
    return {
        "date": candle_date,
        "open": _number(getattr(bar, "open", None)),
        "high": _number(getattr(bar, "high", None)),
        "low": _number(getattr(bar, "low", None)),
        "close": _number(getattr(bar, "close", None)),
        "volume": max(0, int(volume or 0)),
    }


def _normalize_native_position(item: Any) -> dict[str, Any]:
    contract = item.contract
    symbol = str(getattr(contract, "symbol", "")).strip()
    security_type = str(getattr(contract, "secType", "")).strip()
    if not symbol or not security_type:
        raise IbkrError("IBKR native position is missing its symbol or security type")
    exchange = str(
        getattr(contract, "primaryExchange", "") or getattr(contract, "exchange", "")
    ).strip()
    return {
        "symbol": symbol,
        "security_type": security_type,
        "currency": str(getattr(contract, "currency", "") or "USD").strip(),
        "exchange": exchange,
        "conid": _number(getattr(contract, "conId", 0), integer=True, default=0),
        "quantity": _number(getattr(item, "position", 0.0), default=0.0),
        "market_price": _finite_optional(getattr(item, "marketPrice", None)),
        "market_value": _finite_optional(getattr(item, "marketValue", None)),
        "average_cost": _finite_optional(getattr(item, "averageCost", None)),
        "unrealized_pnl": _finite_optional(getattr(item, "unrealizedPNL", None)),
        "realized_pnl": _finite_optional(getattr(item, "realizedPNL", None)),
        "sector": "",
        "group": "",
        "timestamp": int(time.time()),
    }


def _native_summary(values: list[Any]) -> dict[str, Any]:
    summary: dict[str, Any] = {}
    for item in values:
        tag = str(getattr(item, "tag", "")).strip()
        if not tag:
            continue
        summary[tag.lower()] = {
            "value": _native_value(getattr(item, "value", "")),
            "currency": str(getattr(item, "currency", "")).strip(),
        }
    return summary


def _native_ledger(values: list[Any]) -> dict[str, Any]:
    ledger: dict[str, dict[str, Any]] = {}
    for item in values:
        currency = str(getattr(item, "currency", "")).strip()
        tag = str(getattr(item, "tag", "")).strip()
        if not currency or not tag:
            continue
        ledger.setdefault(currency, {})[tag.lower()] = _native_value(
            getattr(item, "value", "")
        )
    return ledger


def _native_value(value: Any) -> Any:
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return str(value)
    return parsed if math.isfinite(parsed) else str(value)


def _finite_optional(value: Any) -> float | None:
    if value is None:
        return None
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return None
    return parsed if math.isfinite(parsed) else None


def _optional_number(value: dict[str, Any], *names: str) -> float | None:
    for name in names:
        if name in value and value[name] is not None:
            return _number(value[name])
    return None


def _number(value: Any, *, integer: bool = False, default: Any = None) -> Any:
    if value is None:
        return default
    try:
        parsed = int(value) if integer else float(value)
    except (TypeError, ValueError) as error:
        raise IbkrError("IBKR returned an invalid numeric position field") from error
    if not integer and not math.isfinite(parsed):
        raise IbkrError("IBKR returned a non-finite numeric position field")
    return parsed


def _first_text(value: dict[str, Any], *names: str) -> str:
    for name in names:
        raw = value.get(name)
        if isinstance(raw, str) and raw.strip():
            return raw.strip()
    return ""


def _account_id(value: Any) -> str:
    if not isinstance(value, dict):
        return ""
    return _first_text(value, "accountId", "id")


def _mask_account(account: str) -> str:
    if len(account) <= 4:
        return "*" * len(account)
    return "*" * (len(account) - 4) + account[-4:]


def _sanitize_account(value: Any, account: str) -> Any:
    if isinstance(value, dict):
        return {key: _sanitize_account(item, account) for key, item in value.items()}
    if isinstance(value, list):
        return [_sanitize_account(item, account) for item in value]
    if isinstance(value, str) and value == account:
        return _mask_account(account)
    return value


def _parse_bool(value: str) -> bool:
    normalized = value.strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    raise ValueError(f"Invalid boolean: {value}")


def _is_loopback(hostname: str) -> bool:
    if hostname.lower() == "localhost":
        return True
    try:
        return ipaddress.ip_address(hostname).is_loopback
    except ValueError:
        return False


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    config = Config.from_env()
    client = make_client(config)
    server = HTTPServer((config.bind, config.port), make_handler(client, config.token))
    print(
        f"MarketMonk IBKR proxy ({config.backend}) listening on "
        f"{config.bind}:{config.port}"
    )
    server.serve_forever()


if __name__ == "__main__":
    main()
