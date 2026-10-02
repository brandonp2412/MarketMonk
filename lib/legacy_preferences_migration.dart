import 'dart:convert';

import 'package:market_monk/app_state_database.dart';
import 'package:market_monk/database.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef ProfileDatabaseFactory = Database Function(String profile);

const _legacyProfilePreferenceKeys = {
  'accounts',
  'activeAccount',
  'ibkrAccountConfigs',
  'portfolioCacheV1',
  'ibkrPerformanceCacheV1',
};

/// Non-destructively seeds the SQLite persistence foundation from the current
/// SharedPreferences layout.
///
/// This intentionally does not remove or rewrite any legacy preference. Callers
/// can keep reading SharedPreferences until each state owner is cut over in a
/// later slice. Existing SQLite values always win so rerunning this migration
/// cannot replace newer state.
Future<void> seedSqliteFromLegacyPreferences({
  required SharedPreferences preferences,
  required AppStateDatabase appState,
  ProfileDatabaseFactory? profileDatabaseFactory,
}) async {
  final storedAccounts = preferences.getStringList('accounts') ?? const [];
  final accounts = <String>[
    'Default',
    for (final account in storedAccounts)
      if (account != 'Default') account,
  ];

  await appState.seedProfilesIfEmpty(accounts);
  await appState.seedSettingIfMissing(
    AppStateDatabase.activeProfileSettingKey,
    preferences.getString('activeAccount') ?? 'Default',
  );

  for (final key in preferences.getKeys()) {
    if (_legacyProfilePreferenceKeys.contains(key)) continue;
    await appState.seedSettingIfMissing(key, preferences.get(key));
  }

  final configs = _decodeMap(preferences.getString('ibkrAccountConfigs'));
  final portfolioCache = _decodeMap(preferences.getString('portfolioCacheV1'));
  final performanceCache =
      _decodeMap(preferences.getString('ibkrPerformanceCacheV1'));

  final profileNames = <String>{
    ...accounts,
    ...configs.keys,
    ...portfolioCache.keys,
    ...performanceCache.keys,
  };

  for (final profile in profileNames) {
    final database = (profileDatabaseFactory ?? _openProfileDatabase)(profile);
    try {
      await _seedIbkrConfig(database, configs[profile]);
      await _seedPortfolioCache(database, portfolioCache[profile]);
      await _seedPerformanceCache(database, performanceCache[profile]);
    } finally {
      await database.close();
    }
  }
}

Database _openProfileDatabase(String profile) =>
    Database(profile == 'Default' ? 'market-monk' : 'market-monk-$profile');

Map<String, dynamic> _decodeMap(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  final decoded = jsonDecode(raw);
  return decoded is Map<String, dynamic> ? decoded : const {};
}

Future<void> _seedIbkrConfig(Database database, Object? raw) async {
  if (raw is! Map<String, dynamic>) return;
  if (await database.readIbkrProfileSettings() != null) return;

  await database.writeIbkrProfileSettings(
    enabled: raw['enabled'] == true,
    baseUrl: raw['baseUrl'] as String? ?? '',
    token: raw['token'] as String? ?? '',
  );
}

Future<void> _seedPortfolioCache(Database database, Object? raw) async {
  if (raw is! Map<String, dynamic>) return;
  if (await database.readIbkrCache('portfolio', 'snapshot') != null) return;

  final cachedAt = DateTime.tryParse(raw['cachedAt'] as String? ?? '');
  if (cachedAt == null) return;

  await database.writeIbkrCache(
    kind: 'portfolio',
    cacheKey: 'snapshot',
    payloadJson: jsonEncode(raw),
    cachedAt: cachedAt,
  );
}

Future<void> _seedPerformanceCache(Database database, Object? raw) async {
  if (raw is! Map<String, dynamic>) return;
  for (final entry in raw.entries) {
    final value = entry.value;
    if (value is! Map<String, dynamic>) continue;
    if (await database.readIbkrCache('performance', entry.key) != null) {
      continue;
    }
    final cachedAt = DateTime.tryParse(value['cachedAt'] as String? ?? '');
    if (cachedAt == null) continue;

    await database.writeIbkrCache(
      kind: 'performance',
      cacheKey: entry.key,
      payloadJson: jsonEncode(value),
      cachedAt: cachedAt,
    );
  }
}
