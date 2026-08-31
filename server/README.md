# MarketMonk IBKR proxy

This directory contains a standalone, read-only bridge between MarketMonk and Interactive Brokers. It is intentionally independent of any personal IBKR bot, login automation, or trading project.

The HTTP interface consumed by MarketMonk is the same for both supported backends:

- `GET /v1/health`
- `GET /v1/portfolio`
- `GET /v1/historical?symbol=AAPL&years=10`

Every request requires `Authorization: Bearer <MARKET_MONK_IBKR_TOKEN>`. The bridge exposes no order endpoint and rejects POST requests.

## Native TWS / IB Gateway backend

This is the recommended backend for a normal TWS or IB Gateway installation. Set `IBKR_BACKEND=native`, then point `IBKR_TWS_HOST` and `IBKR_TWS_PORT` at the socket API. IB Gateway live accounts normally use port `4001`; TWS and paper installations can use different ports.

MarketMonk uses `ib_async` only as the transport implementation for IBKR's documented TWS socket protocol. The bridge connects with the library's read-only connection option and only reads managed accounts, account values, and portfolio updates. For defense in depth, enable **Read-Only API** in TWS / IB Gateway itself as well.

IBKR documents `updatePortfolio` as providing position size, market price, market value, average cost, daily unrealized P/L, and daily realized P/L. Those values are normalized into MarketMonk's existing `/v1/portfolio` response.

The native backend can also request daily `TRADES` historical bars for current stock positions. MarketMonk requests between one and ten years, uses regular trading hours, and routes through `SMART` when a portfolio contract does not include an API routing exchange. Historical availability follows the market-data permissions on the IBKR username. MarketMonk falls back to Yahoo for unheld symbols or when IBKR historical data is unavailable.

Official IBKR documentation:

- https://www.interactivebrokers.com/docs/tws-api/doc/introduction
- https://www.interactivebrokers.com/docs/tws-api/doc/account-portfolio-data/account-updates/receiving-account-updates
- https://www.interactivebrokers.com/docs/tws-api/doc/account-portfolio-data/account-updates/account-value-keys
- https://interactivebrokers.github.io/tws-api/historical_bars.html
- https://interactivebrokers.github.io/tws-api/historical_data.html
- https://interactivebrokers.github.io/tws-api/historical_limitations.html

The Python dependency is pinned in `requirements.txt`.

## Client Portal backend

The original Client Portal Web API backend remains available with `IBKR_BACKEND=client_portal`. It uses only documented portfolio endpoints:

- `GET /portfolio/accounts`
- `GET /portfolio2/{accountId}/positions`
- `GET /portfolio/{accountId}/summary`
- `GET /portfolio/{accountId}/ledger`

It never initializes an `/iserver` brokerage session. Retail Client Portal Gateway authentication still requires the normal browser login and periodic reauthentication according to IBKR's supported flow.

Official IBKR documentation:

- https://www.interactivebrokers.com/docs/web-api/v1/endpoints/portfolio/portfolio-accounts
- https://www.interactivebrokers.com/docs/web-api/v1/endpoints/portfolio/positions-new
- https://www.interactivebrokers.com/docs/web-api/v1/endpoints/portfolio/portfolio-summary
- https://www.interactivebrokers.com/docs/web-api/v1/endpoints/portfolio/portfolio-ledger
- https://www.interactivebrokers.com/docs/web-api/authentication/sessions

## Run

Create a virtual environment and install the pinned dependency:

```bash
python3 -m venv venv
venv/bin/pip install -r requirements.txt
```

When deploying the example systemd unit under `/opt/market-monk-ibkr`, make the virtualenv readable by its dedicated service account after installing or copying dependencies:

```bash
sudo chown -R root:market-monk-ibkr /opt/market-monk-ibkr/venv
sudo chmod -R o-rwx /opt/market-monk-ibkr/venv
sudo chmod -R g+rX /opt/market-monk-ibkr/venv
```

This step matters if deployment tools preserve a different source group or a restrictive umask; otherwise the service can appear healthy until its first restart and then fail while importing dependencies.

Copy `ibkr-proxy.env.example` to a protected environment file, set a random `MARKET_MONK_IBKR_TOKEN` of at least 32 characters, and configure the backend. `IBKR_ACCOUNT_ID` is optional when the Gateway exposes exactly one account; set it when the username can see multiple accounts.

Start the bridge:

```bash
set -a
. ./ibkr-proxy.env
set +a
venv/bin/python ./ibkr_proxy.py
```

The default listener is `127.0.0.1:8091`. Put HTTPS or a private VPN in front of it for access from a phone. Do not expose the plain HTTP listener directly to the internet.

## API

`GET /v1/health` connects to the selected IBKR backend and verifies that the configured account is visible. With no configured account ID, a single visible account is selected automatically; multiple visible accounts require `IBKR_ACCOUNT_ID`.

`GET /v1/portfolio` returns a normalized read-only snapshot containing the masked account ID, summary values, ledger values, and current positions with quantity, average cost, current market price/value, daily realized P/L, daily unrealized P/L, currency, exchange, and contract ID when supplied by IBKR.

`GET /v1/historical?symbol=AAPL&years=10` is available with the native backend for a current stock position visible to that IBKR session. `years` must be from 1 through 10. It returns daily OHLCV bars and the contract currency. The endpoint remains read-only and the service still exposes no order route.

## systemd

`market-monk-ibkr.service` is an example hardened unit. It expects:

- application: `/opt/market-monk-ibkr/ibkr_proxy.py`
- virtualenv: `/opt/market-monk-ibkr/venv`
- environment: `/etc/market-monk-ibkr.env`
- unprivileged account: `market-monk-ibkr`

## Tests

```bash
cd server
python3 -m unittest -v test_ibkr_proxy.py
```
