import 'dart:io';

import 'package:drift/native.dart';
import 'package:market_monk/legacy_app_state_database.dart';
import 'package:market_monk/legacy_profile_database.dart';
import 'package:market_monk/legacy_database_source.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<LegacyDatabaseSnapshot?> loadLegacyDatabaseSnapshot() async {
  final directory = await getApplicationSupportDirectory();
  final settingsFile = File(
    p.join(directory.path, 'market-monk.settings.sqlite'),
  );
  if (!await settingsFile.exists()) return null;

  final appState = LegacyAppStateDatabase.connect(NativeDatabase(settingsFile));
  try {
    return await readLegacyDatabaseSnapshot(
      readSettings: appState.readSettings,
      readProfileNames: appState.readProfiles,
      readActiveProfile: appState.readActiveProfile,
      openProfileDatabase: (profileName) async {
        final fileName = profileName == 'Default'
            ? 'market-monk.sqlite'
            : 'market-monk-$profileName.sqlite';
        final file = File(p.join(directory.path, fileName));
        if (!await file.exists()) return null;
        return LegacyProfileDatabase.connect(NativeDatabase(file));
      },
    );
  } finally {
    await appState.close();
  }
}
