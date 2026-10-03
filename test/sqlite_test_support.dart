import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/app_state_database.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/legacy_preferences_migration.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/market_data_store.dart';
import 'package:market_monk/profile_data_repository.dart';
import 'package:market_monk/sqlite_settings.dart';
import 'package:market_monk/unified_database.dart';

export 'package:market_monk/sqlite_settings.dart';

Directory? _profileDirectory;
UnifiedDatabase? _profileDataTestDatabase;

/// Seeds isolated real SQLite stores from a legacy fixture.
Future<void> seedTestSqlite(Map<String, Object?> values) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final directory = Directory.systemTemp.createTempSync('monk-test-profiles-');
  _profileDirectory = directory;
  final database = AppStateDatabase.connect(NativeDatabase.memory());
  final profileData = UnifiedDatabase.connect(NativeDatabase.memory());
  _profileDataTestDatabase = profileData;
  setProfileDataDatabaseForTesting(profileData);
  setMarketDataDatabaseForTesting(profileData);
  addTearDown(() async {
    setProfileDataDatabaseForTesting(null);
    setMarketDataDatabaseForTesting(null);
    _profileDataTestDatabase = null;
    await profileData.close();
    await database.close();
    directory.deleteSync(recursive: true);
  });
  final loaded = () async {
    await seedSqliteFromLegacyValues(
      values: values,
      appState: database,
      profileDatabaseFactory: (name) => Database.connect(
        NativeDatabase(File('${directory.path}/$name.sqlite')),
      ),
    );
    await database.writeSetting(sqliteMigrationCompleteKey, true);
    return SqliteSettings.load(database);
  }();
  await SqliteSettings.useInstance(loaded);

  // Exercise the production upgrade path so fixtures populate unified
  // profiles, account settings, caches and active identity consistently.
  final bootstrapAccounts = AccountManager(
    profileDatabaseFactory: (name) => Database.connect(
      NativeDatabase(File('${directory.path}/$name.sqlite')),
    ),
    unifiedDatabase: profileData,
  );
  await bootstrapAccounts.init();
}

Future<void> ensureTestProfile(String name) async {
  final database = _profileDataTestDatabase;
  if (database == null) {
    throw StateError('seedTestSqlite must be called first');
  }
  if (await database.readProfileByName(name) != null) return;
  final profiles = await database.readProfiles();
  await database.upsertProfile(
    id: ['test-profile', profiles.length + 1].join('-'),
    name: name,
    sortOrder: profiles.length,
  );
}

/// Uses independent file connections so reopening exercises persistence.
Future<void> seedTestCandle({
  required String symbol,
  required DateTime date,
  required double close,
}) async {
  final database = _profileDataTestDatabase;
  if (database == null) {
    throw StateError('seedTestSqlite must be called first');
  }
  await database.upsertCandle(
    symbol: symbol,
    date: DateTime(date.year, date.month, date.day),
    open: close,
    high: close,
    low: close,
    close: close,
    volume: 0,
    adjClose: close,
  );
}

/// Uses independent file connections so reopening exercises persistence.

AccountManager testAccountManager() => AccountManager(
      profileDatabaseFactory: (name) => Database.connect(
        NativeDatabase(File('${_profileDirectory!.path}/$name.sqlite')),
      ),
      unifiedDatabase: _profileDataTestDatabase!,
    );
