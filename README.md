<div align="center">

<img src="docs/readme-icon.png" width="112" alt="MarketMonk app icon">

# MarketMonk

Stock charts and portfolio tracking for Android, Windows, and Linux 📈

<p>
  <a href="https://github.com/brandonp2412/MarketMonk/releases/latest"><img alt="GitHub Release" src="https://img.shields.io/github/v/release/brandonp2412/MarketMonk?style=for-the-badge&logoColor=ffffff&labelColor=FFB52E&color=151218"></a>
  <a href="#"><img alt="Release downloads" src="https://img.shields.io/github/downloads/brandonp2412/MarketMonk/total.svg?style=for-the-badge&logoColor=ffffff&labelColor=FFB52E&color=151218"></a>
</p>

<p>
  <a href="https://play.google.com/store/apps/details?id=com.codesail.market_monk"><img alt="Get it on Google Play" style="height: 80px !important" src="./docs/get-it-on-google-play.png"/></a>
  <a href="https://f-droid.org/packages/com.codesail.market_monk"><img src="./docs/get-it-on-fdroid.png" alt="Get it on F-Droid" style="height: 80px !important"></a>
  <a href="https://apps.microsoft.com/detail/9PP4HKV1CMWC?mode=direct"><img alt="Download MarketMonk from the Microsoft Store" src="./docs/download-msstore.svg" style="height: 80px !important"/></a>
</p>

</div>

MarketMonk helps you follow stock prices, track your holdings, and see how your portfolio performs.

# Features

- 💹 Explore daily and intraday stock charts with Yahoo Finance data
- 🥧 Track holdings, trades, and portfolio performance
- 🏦 Connect an optional read-only Interactive Brokers portfolio source
- ⚙️ Choose your chart settings, currencies, and dashboard layout

# Downloads

MarketMonk supports Android, Windows, and Linux. iOS and macOS are no longer supported.

- Android: [Google Play](https://play.google.com/store/apps/details?id=com.codesail.market_monk), [F-Droid](https://f-droid.org/packages/com.codesail.market_monk), or an APK from [GitHub Releases](https://github.com/brandonp2412/MarketMonk/releases/latest)
- Windows: [Microsoft Store](https://apps.microsoft.com/detail/9PP4HKV1CMWC?mode=direct) or a ZIP from [GitHub Releases](https://github.com/brandonp2412/MarketMonk/releases/latest)
- Linux: download the Linux ZIP from [GitHub Releases](https://github.com/brandonp2412/MarketMonk/releases/latest)

<br />
<p align="center">
    <img alt="MarketMonk holdings overview" src="fastlane/metadata/android/en-US/images/phoneScreenshots/5_en-US.png" height="700"/>
    <img alt="MarketMonk holding trade history" src="fastlane/metadata/android/en-US/images/phoneScreenshots/6_en-US.png" height="700"/>
    <img alt="MarketMonk edit ticker screen" src="fastlane/metadata/android/en-US/images/phoneScreenshots/4_en-US.png" height="700"/>
    <img alt="MarketMonk settings screen" src="fastlane/metadata/android/en-US/images/phoneScreenshots/3_en-US.png" height="700"/>
    <img alt="MarketMonk stock chart" src="fastlane/metadata/android/en-US/images/phoneScreenshots/1_en-US.png" height="700"/>
    <img alt="MarketMonk portfolio screen" src="fastlane/metadata/android/en-US/images/phoneScreenshots/2_en-US.png" height="700"/>
</p>

# Donations

If you would like to support this project:

- Bitcoin `bc1qzlte8featxzf7xvtp3rjv7qqtwkgpup8hu85gp`
- Monero (XMR) `85tmLfWKbpd8nxQnUY878DDuFjmfcoCFXPWR7XYKLHBSbDZV8wxgoKYUtHtq1kHWJg4m14sdBXhYuUSbxEDA29d19XuREL5`
- [GitHub sponsor](https://github.com/sponsors/brandonp2412)

# Contributing

All issues and pull requests are welcome! Bugs will be fixed faster if you include reproduction steps (and maybe [logs](https://developer.android.com/tools/logcat)). Any performance related pull requests will bring tears of joy to my eye.

# Developers

Use the repository-pinned [Flutter SDK](https://docs.flutter.dev/get-started/install) to build for Android, Windows, or Linux.

Use the pinned SDK: `./flutter/bin/flutter run -d linux`, or
`./scripts/run_linux.sh`. The VS Code workspace also selects `flutter/`.
`scripts/watch.sh` watches Dart sources and requests reloads only for Flutter
sessions running from this repository.

## Command line

Market Monk includes an installable `mm` terminal client for inspecting and editing portfolio data. See the [CLI guide](docs/cli.md) for installation, examples, safety notes, and screenshots.

## Interactive Brokers

MarketMonk can use the standalone read-only proxy in [`server/`](server/) as the current portfolio source.
