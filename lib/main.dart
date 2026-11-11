import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:market_monk/background_network_coordinator.dart';
import 'package:market_monk/backup_archive.dart';
import 'package:market_monk/crash_logger.dart';
import 'package:market_monk/debug_hotkeys.dart';
import 'package:market_monk/legacy_database_source.dart';
import 'package:market_monk/legacy_profile_database.dart' as legacy;
import 'package:market_monk/logging.dart';
import 'package:market_monk/profile_data_repository.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/sqlite_settings.dart';
import 'package:market_monk/vi_hotkeys.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'accounts/account_manager.dart';
import 'app.dart';

export 'accounts/account_manager.dart';
export 'app.dart';

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      installDesktopDebugHotkeys();
      backgroundNetworkCoordinator.observeAppLifecycle();
      await CrashLogger.install(fileName: 'marketmonk-crash.log');
      installTalkerErrorHandlers();
      talker.info('Starting Market Monk');

      final sqliteSettings = await SqliteSettings.getInstance();
      final database = profileDataDatabase;
      await database.migrateLegacyDatabases(
        snapshotLoader: () => readLegacyDatabaseSnapshot(
          readSettings: sqliteSettings.database.readSettings,
          readProfileNames: sqliteSettings.database.readProfileNames,
          readActiveProfile: sqliteSettings.database.readActiveProfile,
          openProfileDatabase: (name) async {
            final directory = await getApplicationSupportDirectory();
            final file = File(
              p.join(directory.path, databaseFileNameForAccount(name)),
            );
            if (!await file.exists()) return null;
            return legacy.LegacyProfileDatabase.connect(NativeDatabase(file));
          },
        ),
      );
      final settings = SettingsState();
      installDesktopViHotkeys(settings);
      final accounts = AccountManager(database: database);
      await Future.wait([settings.initialized, accounts.init()]);
      await sqliteSettings.cleanupLegacyAppStateAfterMigration();
      talker.info('Account manager initialized');

      runApp(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: accounts),
          ],
          child: const MyApp(),
        ),
      );
    },
    (error, stack) {
      CrashLogger.instance?.record(error, stack, context: 'zone');
      talker.handle(error, stack, 'Uncaught zone error');
    },
  );
}
