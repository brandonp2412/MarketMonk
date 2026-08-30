# MarketMonk IBKR proxy

This directory contains a standalone, read-only proxy for the official Interactive Brokers Client Portal Web API. It is intentionally independent of any personal IBKR bot or trading project.

The proxy uses only documented portfolio endpoints:

- `GET /portfolio/accounts`
- `GET /portfolio2/{accountId}/positions`
- `GET /portfolio/{accountId}/summary`
- `GET /portfolio/{accountId}/ledger`

IBKR documentation:

- https://www.interactivebrokers.com/docs/web-api/v1/endpoints/portfolio/portfolio-accounts
- https://www.interactivebrokers.com/docs/web-api/v1/endpoints/portfolio/positions-new
- https://www.interactivebrokers.com/docs/web-api/v1/endpoints/portfolio/portfolio-summary
- https://www.interactivebrokers.com/docs/web-api/v1/endpoints/portfolio/portfolio-ledger
- https://www.interactivebrokers.com/docs/web-api/authentication/sessions

The proxy never exposes trading endpoints and does not initialize an `/iserver` brokerage session. This lets portfolio reads use IBKR's outer read-only Web API session without taking over a brokerage session that may be active in TWS or another IBKR client.

## Run

1. Install and start IBKR's Client Portal Gateway on the same host. Retail Client Portal Gateway authentication still requires the normal browser login and must be renewed daily; IBKR does not support automating that login.
2. Copy `ibkr-proxy.env.example` to a protected environment file and set a random `MARKET_MONK_IBKR_TOKEN` of at least 32 characters. `IBKR_ACCOUNT_ID` is optional when the logged-in Gateway exposes exactly one account; set it when the username can see multiple accounts.
3. Start the proxy:

```bash
set -a
. ./ibkr-proxy.env
set +a
python3 ./ibkr_proxy.py
```

The default listener is `127.0.0.1:8091`. Put an HTTPS reverse proxy or private VPN in front of it for access from a phone. Do not expose the plain HTTP listener directly to the internet.

## API

Every request requires:

```text
Authorization: Bearer <MARKET_MONK_IBKR_TOKEN>
```

`GET /v1/health` verifies that the configured IBKR account is visible through the currently authenticated Client Portal Gateway session. With no configured account ID, a single visible account is selected automatically; multiple visible accounts require `IBKR_ACCOUNT_ID`.

`GET /v1/portfolio` returns a normalized read-only snapshot containing the masked account ID, IBKR summary, ledger, and near-real-time positions with quantity, average cost, current market price/value, realized P&L, unrealized P&L, currency, sector, group, and contract ID when supplied by IBKR.

## systemd

`market-monk-ibkr.service` is an example hardened unit. It expects:

- script: `/opt/market-monk-ibkr/ibkr_proxy.py`
- environment: `/etc/market-monk-ibkr.env`
- unprivileged account: `market-monk-ibkr`

## Tests

```bash
cd server
python3 -m unittest -v test_ibkr_proxy.py
```
