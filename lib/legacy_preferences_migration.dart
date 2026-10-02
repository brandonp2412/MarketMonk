import 'dart:convert';

import 'package:market_monk/app_state_database.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Opens an independently owned connection for a named profile.
typedef ProfileDatabaseFactory = Database Function(String profile);

/// Marks a successful one-time import; deletions must never be reseeded.
const sqliteMigrationCompleteKey = 'sqliteMigrationCompleteV1';

/// Marks import of the pre-cutover SQLite app-state database.
const legacyAppStateMigrationCompleteKey = 'legacyAppStateMigrationCompleteV1';

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
Future<List<String>> seedAppStateFromLegacyValues({
  required Map<String, Object?> values,
  required AppStateDatabase appState,
}) async {
  final storedAccounts =
      (values['accounts'] as List?)?.cast<String>() ?? const <String>[];
  final legacyAccounts = <String>{
    'Default',
    for (final account in storedAccounts)
      if (account != 'Default') account,
  }.toList();
  for (final account in legacyAccounts) {
    if (account.contains('/') || account.contains(r'\') || account.isEmpty) {
      throw const FormatException('Invalid legacy profile name');
    }
  }

  final existingAccounts = await appState.readProfiles();
  final mergedAccounts = <String>[
    'Default',
    for (final account in existingAccounts)
      if (account != 'Default') account,
    for (final account in legacyAccounts)
      if (account != 'Default' && !existingAccounts.contains(account)) account,
  ];
  if (existingAccounts.length != mergedAccounts.length ||
      existingAccounts.indexed.any(
        (entry) => mergedAccounts[entry.$1] != entry.$2,
      )) {
    await appState.replaceProfiles(mergedAccounts);
  }

  final legacyActiveAccount = values['activeAccount'] as String? ??
      values[AppStateDatabase.activeProfileSettingKey] as String?;
  final currentActiveAccount = await appState.readActiveProfile();
  if (currentActiveAccount == null &&
      legacyActiveAccount != null &&
      mergedAccounts.contains(legacyActiveAccount)) {
    await appState.setActiveProfile(legacyActiveAccount);
  } else if (currentActiveAccount == null) {
    await appState.setActiveProfile('Default');
  }

  for (final key in values.keys) {
    if (legacyProfilePreferenceKeys.contains(key) ||
        key == AppStateDatabase.activeProfileSettingKey ||
        key == sqliteMigrationCompleteKey ||
        key == legacyAppStateMigrationCompleteKey) {
      continue;
    }
    await appState.seedSettingIfMissing(key, values[key]);
  }

  return legacyAccounts;
}

Future<void> seedSqliteFromLegacyValues({
  required Map<String, Object?> values,
  required AppStateDatabase appState,
  ProfileDatabaseFactory? profileDatabaseFactory,
}) async {
  final accounts = await seedAppStateFromLegacyValues(
    values: values,
    appState: appState,
  );

  final configs = _decodeMap(values['ibkrAccountConfigs'] as String?);
  final portfolioCache =
      _decodeMap(values['portfolioCacheV1'] as String?, discardMalformed: true);
  final performanceCache = _decodeMap(
    values['ibkrPerformanceCacheV1'] as String?,
    discardMalformed: true,
  );

  for (final profile in accounts) {
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
