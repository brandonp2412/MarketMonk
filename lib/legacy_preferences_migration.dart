import 'dart:convert';

import 'package:market_monk/app_state_database.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Opens an independently owned connection for a named profile.
typedef ProfileDatabaseFactory = Database Function(String profile);

/// Marks a successful one-time import; deletions must never be reseeded.
const sqliteMigrationCompleteKey = 'sqliteMigrationCompleteV1';

/// Legacy values that belong in profile tables rather than global settings.
const legacyProfilePreferenceKeys = {
  'accounts',
  'activeAccount',
  'ibkrAccountConfigs',
  'portfolioCacheV1',
  'ibkrPerformanceCacheV1',
};

/// Copies legacy preferences without modifying the upgrade source.
Future<void> seedSqliteFromLegacyPreferences({
  required SharedPreferences preferences,
  required AppStateDatabase appState,
  ProfileDatabaseFactory? profileDatabaseFactory,
}) =>
    seedSqliteFromLegacyValues(
      values: {
        for (final key in preferences.getKeys()) key: preferences.get(key),
      },
      appState: appState,
      profileDatabaseFactory: profileDatabaseFactory,
    );

/// Imports legacy app and profile values, also used for version-one backups.
/// Existing SQLite rows win, making interrupted upgrades safe to retry.
Future<void> seedSqliteFromLegacyValues({
  required Map<String, Object?> values,
  required AppStateDatabase appState,
  ProfileDatabaseFactory? profileDatabaseFactory,
}) async {
  final storedAccounts =
      (values['accounts'] as List?)?.cast<String>() ?? const [];
  final accounts = <String>{
    'Default',
    for (final account in storedAccounts)
      if (account != 'Default') account,
  }.toList();

  await appState.seedProfilesIfEmpty(accounts);
  await appState.seedSettingIfMissing(
    AppStateDatabase.activeProfileSettingKey,
    values['activeAccount'] as String? ?? 'Default',
  );

  for (final key in values.keys) {
    if (legacyProfilePreferenceKeys.contains(key) ||
        key == sqliteMigrationCompleteKey) continue;
    await appState.seedSettingIfMissing(key, values[key]);
  }

  final configs = _decodeMap(values['ibkrAccountConfigs'] as String?);
  final portfolioCache =
      _decodeMap(values['portfolioCacheV1'] as String?, discardMalformed: true);
  final performanceCache = _decodeMap(
    values['ibkrPerformanceCacheV1'] as String?,
    discardMalformed: true,
  );

  final profileNames = accounts;

  for (final profile in profileNames) {
    if (profile.contains('/') || profile.contains(r'\') || profile.isEmpty) {
      throw FormatException('Invalid legacy profile name');
    }
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

Map<String, dynamic> _decodeMap(String? raw, {bool discardMalformed = false}) {
  if (raw == null || raw.isEmpty) return const {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const FormatException('Expected a legacy JSON object');
  } on FormatException catch (error, stack) {
    if (!discardMalformed) rethrow;
    talker.handle(error, stack, 'Skipped malformed legacy cache');
    return const {};
  }
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

  final cachedAt = DateTime.tryParse(
    raw['cachedAt'] is String ? raw['cachedAt'] as String : '',
  );
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
    final cachedAt = DateTime.tryParse(
      value['cachedAt'] is String ? value['cachedAt'] as String : '',
    );
    if (cachedAt == null) continue;

    await database.writeIbkrCache(
      kind: 'performance',
      cacheKey: entry.key,
      payloadJson: jsonEncode(value),
      cachedAt: cachedAt,
    );
  }
}
