<div align="center">

<img src="docs/readme-icon.png" width="112" alt="MarketMonk app icon">

# MarketMonk

Track stocks on any platform 📈

<p>
  <a href="https://github.com/brandonp2412/MarketMonk/releases/latest"><img alt="GitHub Release" src="https://img.shields.io/github/v/release/brandonp2412/MarketMonk?style=for-the-badge&logoColor=ffffff&labelColor=2B7A78&color=151218"></a>
  <a href="#"><img alt="Release downloads" src="https://img.shields.io/github/downloads/brandonp2412/MarketMonk/total.svg?style=for-the-badge&logoColor=ffffff&labelColor=2B7A78&color=151218"></a>
</p>

<p>
  <a href="https://play.google.com/store/apps/details?id=com.codesail.market_monk"><img alt="Get it on Google Play" style="height: 80px !important" src="./docs/get-it-on-google-play.png"/></a>
  <a href="https://f-droid.org/packages/com.codesail.market_monk"><img src="./docs/get-it-on-fdroid.png" alt="Get it on F-Droid" style="height: 80px !important"></a>
  <a href="https://apps.microsoft.com/detail/9PP4HKV1CMWC?mode=direct"><img alt="Download MarketMonk from the Microsoft Store" src="./docs/download-msstore.svg" style="height: 80px !important"/></a>
</p>

</div>

# Features

- 💹 Stock charts with daily and intraday Yahoo Finance data
- 🥧 Build and monitor your portfolio
- 🏦 Optional read-only Interactive Brokers live portfolio source
- ⚙️ Customize to your hearts desires

<br />
<p align="center">
    <img alt="MarketMonk holdings overview" src="docs/screenshots/5_en-US.png" height="700"/>
    <img alt="MarketMonk holding trade history" src="docs/screenshots/6_en-US.png" height="700"/>
    <img alt="MarketMonk edit ticker screen" src="docs/screenshots/4_en-US.png" height="700"/>
    <img alt="MarketMonk settings screen" src="docs/screenshots/3_en-US.png" height="700"/>
    <img alt="MarketMonk stock chart" src="docs/screenshots/1_en-US.png" height="700"/>
    <img alt="MarketMonk portfolio screen" src="docs/screenshots/2_en-US.png" height="700"/>
</p>

# Donations

If you would like to support this project:

- Bitcoin `bc1qzlte8featxzf7xvtp3rjv7qqtwkgpup8hu85gp`
- Monero (XMR) `85tmLfWKbpd8nxQnUY878DDuFjmfcoCFXPWR7XYKLHBSbDZV8wxgoKYUtHtq1kHWJg4m14sdBXhYuUSbxEDA29d19XuREL5`
- [GitHub sponsor](https://github.com/sponsors/brandonp2412)

# Contributing

All issues and pull requests are welcome! Bugs will be fixed faster if you include reproduction steps (and maybe [logs](https://developer.android.com/tools/logcat)). Any performance related pull requests will bring tears of joy to my eye.

# Developers

Install [flutter](https://docs.flutter.dev/get-started/install) to run this app.

Use the pinned SDK: `./flutter/bin/flutter run -d linux`, or
`./scripts/run_linux.sh`. The VS Code workspace also selects `flutter/`.
`scripts/watch.sh` watches Dart sources and requests reloads only for Flutter
sessions running from this repository.

## Command line

Market Monk includes an installable `mm` terminal client for inspecting and editing portfolio data. See the [CLI guide](docs/cli.md) for installation, examples, safety notes, and screenshots.

## Interactive Brokers

MarketMonk can use the standalone read-only proxy in [`server/`](server/) as the current portfolio source.