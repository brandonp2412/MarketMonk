#!/usr/bin/env python3
"""Read-only MarketMonk proxy for the official IBKR Client Portal Web API."""

from __future__ import annotations

import argparse
import hmac
import ipaddress
import json
import math
import os
import ssl
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlparse
from urllib.request import HTTPSHandler, Request, build_opener


@dataclass(frozen=True)
class Config:
    gateway_url: str
    account_id: str | None
    bind: str
    port: int
    token: str
    verify_gateway_tls: bool

    @classmethod
    def from_env(cls) -> "Config":
        gateway_url = os.getenv(
            "IBKR_GATEWAY_URL", "https://127.0.0.1:5000/v1/api"
        ).rstrip("/")
        account_id = os.getenv("IBKR_ACCOUNT_ID", "").strip() or None
        bind = os.getenv("MARKET_MONK_IBKR_BIND", "127.0.0.1").strip()
        port = int(os.getenv("MARKET_MONK_IBKR_PORT", "8091"))
        token = os.getenv("MARKET_MONK_IBKR_TOKEN", "").strip()

        parsed = urlparse(gateway_url)
        if parsed.scheme != "https" or not parsed.hostname:
            raise ValueError("IBKR_GATEWAY_URL must be an https:// URL")
        if len(token) < 32:
            raise ValueError("MARKET_MONK_IBKR_TOKEN must be at least 32 characters")
        if not 1 <= port <= 65535:
            raise ValueError("MARKET_MONK_IBKR_PORT must be between 1 and 65535")

        verify_raw = os.getenv("IBKR_GATEWAY_VERIFY_TLS")
        if verify_raw is None:
            verify_gateway_tls = not _is_loopback(parsed.hostname)
        else:
            verify_gateway_tls = _parse_bool(verify_raw)

        return cls(
            gateway_url=gateway_url,
            account_id=account_id,
            bind=bind,
            port=port,
            token=token,
            verify_gateway_tls=verify_gateway_tls,
        )


class IbkrError(RuntimeError):
    pass


class IbkrClient:
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
        configured = self._config.account_id
        if configured is not None:
            if configured not in visible:
                raise IbkrError("Configured IBKR account is not visible in this session")
            return configured
        if len(visible) == 1:
            return visible[0]
        if not visible:
            raise IbkrError("No IBKR accounts are visible in this session")
        raise IbkrError(
            "Multiple IBKR accounts are visible; set IBKR_ACCOUNT_ID on the proxy"
        )

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
            "summary": _sanitize_account(summary, raw_account),
            "ledger": _sanitize_account(ledger, raw_account),
            "positions": [_normalize_position(item) for item in positions],
        }

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


def make_handler(client: IbkrClient, token: str) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        server_version = "MarketMonkIBKR/1"

        def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
            supplied = self.headers.get("Authorization", "")
            expected = f"Bearer {token}"
            if not hmac.compare_digest(supplied, expected):
                self._json(401, {"error": "unauthorized"})
                return

            try:
                if self.path == "/v1/health":
                    client.ensure_account_visible()
                    self._json(200, {"status": "ok", "source": "ibkr"})
                elif self.path == "/v1/portfolio":
                    self._json(200, client.portfolio())
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


def _normalize_position(value: Any) -> dict[str, Any]:
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
    server = ThreadingHTTPServer(
        (config.bind, config.port),
        make_handler(IbkrClient(config), config.token),
    )
    print(f"MarketMonk IBKR proxy listening on {config.bind}:{config.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
