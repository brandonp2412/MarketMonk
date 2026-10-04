import 'dart:convert';

import 'package:market_monk/database.dart';
import 'package:market_monk/legacy_profile_database.dart';
import 'package:market_monk/logging.dart';

/// Opens an independently owned connection for a named profile.
typedef ProfileDatabaseFactory = LegacyProfileDatabase Function(String profile);

/// Marks a successful one-time import; deletions must never be reseeded.
const sqliteMigrationCompleteKey = 'sqliteMigrationCompleteV1';

/// Marks import of the pre-cutover SQLite app-state database.
const legacyAppStateMigrationCompleteKey = 'legacyAppStateMigrationCompleteV1';

/// Marks deletion of the obsolete pre-cutover app-state SQLite file.
const legacyAppStateCleanupCompleteKey = 'legacyAppStateCleanupCompleteV1';

/// Legacy values that belong in profile tables rather than global settings.
const legacyProfilePreferenceKeys = {
  'accounts',
  'activeAccount',
  'ibkrAccountConfigs',
  'portfolioCacheV1',
  'ibkrPerformanceCacheV1',
};

/// Imports retired preference values directly into the one live database.
Future<List<String>> seedDatabaseFromLegacyValues({
  required Map<String, Object?> values,
  required Database database,
}) async {
  final storedAccounts =
      (values['accounts'] as List?)?.whereType<String>().toList() ??
          const <String>[];
  final incomingAccounts = <String>{
    'Default',
    for (final account in storedAccounts)
      if (account != 'Default') account,
  }.toList();

  for (final account in incomingAccounts) {
    if (account.isEmpty || account.contains('/') || account.contains(r'\\')) {
      throw const FormatException('Invalid legacy profile name');
    }
  }

  final existingProfiles = await database.readProfiles();
  final existingByName = {
    for (final profile in existingProfiles) profile.name: profile,
  };
  final mergedAccounts = <String>[
    'Default',
    for (final profile in existingProfiles)
      if (profile.name != 'Default') profile.name,
    for (final account in incomingAccounts)
      if (account != 'Default' && !existingByName.containsKey(account)) account,
  ];

  for (var index = 0; index < mergedAccounts.length; index++) {
    final name = mergedAccounts[index];
    final current = existingByName[name];
    await database.upsertProfile(
      id: current?.id ??
          (name == 'Default' ? 'profile-default' : 'profile-legacy-$index'),
      name: name,
      sortOrder: index,
    );
  }

  final legacyActive =
      values['activeAccount'] as String? ?? values['activeProfile'] as String?;
  if (await database.readActiveProfile() == null) {
    await database.setActiveProfile(
      legacyActive != null && mergedAccounts.contains(legacyActive)
          ? legacyActive
          : 'Default',
    );
  }

  for (final entry in values.entries) {
    final key = entry.key;
    if (legacyProfilePreferenceKeys.contains(key) ||
        key == 'activeProfile' ||
        key == sqliteMigrationCompleteKey ||
        key == legacyAppStateMigrationCompleteKey ||
        key == legacyAppStateCleanupCompleteKey) {
      continue;
    }
    if (await database.readSetting(key) == null) {
      await database.writeSetting(key, entry.value);
    }
  }

  await _seedDatabaseIbkrValues(database, mergedAccounts, values);
  return mergedAccounts;
}

Future<void> _seedDatabaseIbkrValues(
  Database database,
  List<String> accounts,
  Map<String, Object?> values,
) async {
  final configs = _decodeMap(values['ibkrAccountConfigs'] as String?);
  final portfolioCache =
      _decodeMap(values['portfolioCacheV1'] as String?, discardMalformed: true);
  final performanceCache = _decodeMap(
    values['ibkrPerformanceCacheV1'] as String?,
    discardMalformed: true,
  );

  for (final account in accounts) {
    final profile = await database.readProfileByName(account);
    if (profile == null) continue;

    final config = configs[account];
    if (config is Map<String, dynamic> &&
        await database.readIbkrSettings(profile.id) == null) {
      await database.writeIbkrSettings(
        profileId: profile.id,
        enabled: config['enabled'] == true,
        baseUrl: config['baseUrl'] as String? ?? '',
        token: config['token'] as String? ?? '',
      );
    }

    final portfolio = portfolioCache[account];
    if (portfolio is Map<String, dynamic> &&
        await database.readIbkrCache(
              profile.id,
              'portfolio',
              'snapshot',
            ) ==
            null) {
      final cachedAt = DateTime.tryParse(
        portfolio['cachedAt'] is String ? portfolio['cachedAt'] as String : '',
      );
      if (cachedAt != null) {
        await database.writeIbkrCache(
          profileId: profile.id,
          kind: 'portfolio',
          cacheKey: 'snapshot',
          payloadJson: jsonEncode(portfolio),
          cachedAt: cachedAt,
        );
      }
    }

    final performance = performanceCache[account];
    if (performance is! Map<String, dynamic>) continue;
    for (final entry in performance.entries) {
      final cached = entry.value;
      if (cached is! Map<String, dynamic>) continue;
      if (await database.readIbkrCache(
            profile.id,
            'performance',
            entry.key,
          ) !=
          null) {
        continue;
      }
      final cachedAt = DateTime.tryParse(
        cached['cachedAt'] is String ? cached['cachedAt'] as String : '',
      );
      if (cachedAt == null) continue;
      await database.writeIbkrCache(
        profileId: profile.id,
        kind: 'performance',
        cacheKey: entry.key,
        payloadJson: jsonEncode(cached),
        cachedAt: cachedAt,
      );
    }
  }
}

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
