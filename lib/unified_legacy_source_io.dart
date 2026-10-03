import 'dart:io';

import 'package:drift/native.dart';
import 'package:market_monk/app_state_database.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/unified_legacy_source.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<LegacyUnifiedSnapshot?> loadLegacyUnifiedSnapshot() async {
  final directory = await getApplicationSupportDirectory();
  final settingsFile = File(
    p.join(directory.path, 'market-monk.settings.sqlite'),
  );
  if (!await settingsFile.exists()) return null;

  final appState = AppStateDatabase.connect(NativeDatabase(settingsFile));
  try {
    return await readLegacyUnifiedSnapshot(
      appState: appState,
      openProfileDatabase: (profileName) async {
        final fileName = profileName == 'Default'
            ? 'market-monk.sqlite'
            : 'market-monk-$profileName.sqlite';
        final file = File(p.join(directory.path, fileName));
        if (!await file.exists()) return null;
        return Database.connect(NativeDatabase(file));
      },
    );
  } finally {
    await appState.close();
  }
}
