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
import 'package:market_monk/unified_legacy_source.dart';

export 'package:market_monk/sqlite_settings.dart';

Directory? _profileDirectory;
UnifiedDatabase? _profileDataTestDatabase;

/// Seeds isolated real SQLite stores from a legacy fixture.
Future<void> seedTestSqlite(Map<String, Object?> values) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final directory = Directory.systemTemp.createTempSync('monk-test-profiles-');
  _profileDirectory = directory;
  final database = AppStateDatabase.connect(NativeDatabase.memory());
  final profileData = UnifiedDatabase.connect(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
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
    final snapshot = await readLegacyUnifiedSnapshot(
      appState: database,
      openProfileDatabase: (name) async => Database.connect(
        NativeDatabase(File('${directory.path}/$name.sqlite')),
      ),
    );
    await profileData.migrateLegacySnapshot(snapshot, replaceExisting: true);
    return SqliteSettings.load(database);
  }();
  await SqliteSettings.useInstance(loaded);
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

Future<void> seedTestCandle(
  String symbol,
  DateTime date,
  double close,
) async {
  final database = _profileDataTestDatabase;
  if (database == null) {
    throw StateError('seedTestSqlite must be called first');
  }
  await database.upsertCandle(
    symbol: symbol,
    date: date,
    open: close,
    high: close,
    low: close,
    close: close,
    volume: 0,
    adjClose: close,
  );
}

Future<void> seedTestTrade({
  String accountName = 'Default',
  required String symbol,
  required String name,
  required double quantity,
  required double price,
  required String tradeType,
  required DateTime tradeDate,
  double realizedPL = 0,
  double commission = 0,
}) async {
  final database = _profileDataTestDatabase;
  if (database == null) {
    throw StateError('seedTestSqlite must be called first');
  }
  final profile = await database.readProfileByName(accountName);
  if (profile == null) {
    throw StateError('Unknown test profile: $accountName');
  }
  await database.addTrade(
    profileId: profile.id,
    symbol: symbol,
    name: name,
    quantity: quantity,
    price: price,
    tradeType: tradeType,
    tradeDate: tradeDate,
    realizedPL: realizedPL,
    commission: commission,
  );
}

/// Uses independent file connections so reopening exercises persistence.
AccountManager testAccountManager() => AccountManager(
      profileDatabaseFactory: (name) => Database.connect(
        NativeDatabase(File('${_profileDirectory!.path}/$name.sqlite')),
      ),
      unifiedDatabase: _profileDataTestDatabase!,
    );
