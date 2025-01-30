# MarketMonk

Track stocks on any platform 📈 - No ads

<p float="left">
    <a href="https://github.com/brandonp2412/MarketMonk/releases/latest"><img alt="GitHub Release" src="https://img.shields.io/github/v/release/brandonp2412/MarketMonk?style=for-the-badge&logoColor=d3bcfd&labelColor=d3bcfd&color=151218"></a>
    <a href="#"><img alt="Release downloads" src="https://img.shields.io/github/downloads/brandonp2412/MarketMonk/total.svg?style=for-the-badge&logoColor=d3bcfd&labelColor=d3bcfd&color=151218"></a>
</p>

# Features

- 💹 Line graph stocks (with Yahoo Finance Data)
- 🥧 Build and monitor your portfolio
- ⚙️ Customize to your hearts desires

<p float="left">
  <a href='https://play.google.com/store/apps/details?id=com.codesail.market_monk'><img alt='Get it on Google Play' height="75" src='https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png'/></a>
  <a href='https://apps.apple.com/us/app/market-monk-by-codesail/id6741134414?itscg=30200&itsct=apps_box_link&mttnsubad=6741134414'><img alt='Get it on Google Play' height="75" src='docs/download-apple.svg'/></a>
  <a href="https://apps.microsoft.com/detail/9PP4HKV1CMWC?mode=direct"><img src="https://get.microsoft.com/images/en-us%20dark.svg" height="75"/></a>
</p>

<br />
<p float="left">
    <img src="docs/screenshot5.jpg" height="700"/>
    <img src="docs/screenshot6.jpg" height="700"/>
    <img src="docs/screenshot4.jpg" height="700"/>
    <img src="docs/screenshot3.jpg" height="700"/>
    <img src="docs/screenshot1.jpg" height="700"/>
    <img src="docs/screenshot2.jpg" height="700"/>
</p>

# Developers

Install [flutter](https://docs.flutter.dev/get-started/install) to run this app.

## Migrations

After editing any table in `lib/tables.dart` you need to:

1. Bump `schemaVersion` in `lib/database.dart`
2. Run `dart run drift_dev make-migrations`
3. Add the relevant migration step in `lib/database.dart` `migrationSteps`.
   e.g.

```dart
from3To4: (Migrator m, Schema4 schema) async {
  await m.createTable(schema.candles);
},
```

4. Run `dart run build_runner build -d`

## Attribution

<a href="https://www.flaticon.com/free-icons/meditation" title="meditation icons">Meditation icons created by Freepik - Flaticon</a>
