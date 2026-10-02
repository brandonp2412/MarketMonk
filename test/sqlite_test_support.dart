import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/app_state_database.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/legacy_preferences_migration.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/sqlite_settings.dart';

export 'package:market_monk/sqlite_settings.dart';

Directory? _profileDirectory;

/// Seeds isolated real SQLite stores from a legacy fixture.
Future<void> seedTestSqlite(Map<String, Object?> values) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final directory = Directory.systemTemp.createTempSync('monk-test-profiles-');
  _profileDirectory = directory;
  final database = AppStateDatabase.connect(NativeDatabase.memory());
  addTearDown(() async {
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
}

/// Uses independent file connections so reopening exercises persistence.
AccountManager testAccountManager() => AccountManager(
      profileDatabaseFactory: (name) => Database.connect(
        NativeDatabase(File('${_profileDirectory!.path}/$name.sqlite')),
      ),
    );
