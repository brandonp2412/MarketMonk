import 'package:market_monk/app_state_database.dart';
import 'package:market_monk/database.dart';

typedef LegacyProfileDatabaseOpener = Future<Database?> Function(
  String profileName,
);

class LegacyUnifiedSnapshot {
  const LegacyUnifiedSnapshot({
    required this.settings,
    required this.profiles,
    required this.activeProfileName,
  });

  final Map<String, Object?> settings;
  final List<LegacyProfileSnapshot> profiles;
  final String activeProfileName;
}

class LegacyProfileSnapshot {
  const LegacyProfileSnapshot({
    required this.name,
    this.trades = const [],
    this.ibkrSettings,
    this.ibkrCacheEntries = const [],
    this.candles = const [],
  });

  final String name;
  final List<LegacyTradeSnapshot> trades;
  final LegacyIbkrSettingsSnapshot? ibkrSettings;
  final List<LegacyIbkrCacheSnapshot> ibkrCacheEntries;
  final List<LegacyCandleSnapshot> candles;
}

class LegacyTradeSnapshot {
  const LegacyTradeSnapshot({
    required this.symbol,
    required this.name,
    required this.quantity,
    required this.price,
    required this.tradeType,
    required this.tradeDate,
    required this.realizedPL,
    required this.commission,
  });

  final String symbol;
  final String name;
  final double quantity;
  final double price;
  final String tradeType;
  final DateTime tradeDate;
  final double realizedPL;
  final double commission;
}

class LegacyIbkrSettingsSnapshot {
  const LegacyIbkrSettingsSnapshot({
    required this.enabled,
    required this.baseUrl,
    required this.token,
  });

  final bool enabled;
  final String baseUrl;
  final String token;
}

class LegacyIbkrCacheSnapshot {
  const LegacyIbkrCacheSnapshot({
    required this.kind,
    required this.cacheKey,
    required this.payloadJson,
    required this.cachedAt,
  });

  final String kind;
  final String cacheKey;
  final String payloadJson;
  final DateTime cachedAt;
}

class LegacyCandleSnapshot {
  const LegacyCandleSnapshot({
    required this.symbol,
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    required this.adjClose,
  });

  final String symbol;
  final DateTime date;
  final double open;
  final double high;
  final double low;
  final double close;
  final int volume;
  final double adjClose;
}

Future<LegacyUnifiedSnapshot> readLegacyUnifiedSnapshot({
  required AppStateDatabase appState,
  required LegacyProfileDatabaseOpener openProfileDatabase,
  bool closeProfileDatabases = true,
}) async {
  final settings = Map<String, Object?>.from(await appState.readSettings())
    ..remove(AppStateDatabase.activeProfileSettingKey);

  var profileNames = await appState.readProfiles();
  if (profileNames.isEmpty) {
    profileNames = const ['Default'];
  }

  final savedActiveProfile = await appState.readActiveProfile();
  final activeProfileName =
      savedActiveProfile != null && profileNames.contains(savedActiveProfile)
          ? savedActiveProfile
          : profileNames.contains('Default')
              ? 'Default'
              : profileNames.first;

  final profiles = <LegacyProfileSnapshot>[];
  for (final profileName in profileNames) {
    final database = await openProfileDatabase(profileName);
    if (database == null) {
      profiles.add(LegacyProfileSnapshot(name: profileName));
      continue;
    }

    try {
      final trades = await database.select(database.trades).get();
      final ibkrSettings = await database.readIbkrProfileSettings();
      final ibkrCache = await database.select(database.ibkrCacheEntries).get();
      final candles = await database.select(database.candles).get();

      profiles.add(
        LegacyProfileSnapshot(
          name: profileName,
          trades: [
            for (final trade in trades)
              LegacyTradeSnapshot(
                symbol: trade.symbol,
                name: trade.name,
                quantity: trade.quantity,
                price: trade.price,
                tradeType: trade.tradeType,
                tradeDate: trade.tradeDate,
                realizedPL: trade.realizedPL,
                commission: trade.commission,
              ),
          ],
          ibkrSettings: ibkrSettings == null
              ? null
              : LegacyIbkrSettingsSnapshot(
                  enabled: ibkrSettings.enabled,
                  baseUrl: ibkrSettings.baseUrl,
                  token: ibkrSettings.token,
                ),
          ibkrCacheEntries: [
            for (final entry in ibkrCache)
              LegacyIbkrCacheSnapshot(
                kind: entry.kind,
                cacheKey: entry.cacheKey,
                payloadJson: entry.payloadJson,
                cachedAt: entry.cachedAt,
              ),
          ],
          candles: [
            for (final candle in candles)
              LegacyCandleSnapshot(
                symbol: candle.symbol,
                date: candle.date,
                open: candle.open,
                high: candle.high,
                low: candle.low,
                close: candle.close,
                volume: candle.volume,
                adjClose: candle.adjClose,
              ),
          ],
        ),
      );
    } finally {
      if (closeProfileDatabases) {
        await database.close();
      }
    }
  }

  return LegacyUnifiedSnapshot(
    settings: settings,
    profiles: profiles,
    activeProfileName: activeProfileName,
  );
}
