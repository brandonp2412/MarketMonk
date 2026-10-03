import 'dart:io';

import 'package:drift/native.dart';
import 'package:market_monk/app_state_database.dart';
import 'package:path_provider/path_provider.dart';

const _legacyAppStateFileName = 'market-monk-app-state.sqlite';

Future<File> _legacyAppStateFile() async {
  final directory = await getApplicationSupportDirectory();
  return File('${directory.path}/$_legacyAppStateFileName');
}

Future<Map<String, Object?>?> readLegacyAppStateFile() async {
  final file = await _legacyAppStateFile();
  if (!await file.exists()) return null;

  final database = AppStateDatabase.connect(NativeDatabase(file));
  try {
    final values = await database.readSettings();
    final profiles = await database.readProfiles();
    if (values.isEmpty && profiles.isEmpty) return null;
    values['accounts'] = profiles;
    values['activeAccount'] = await database.readActiveProfile();
    return values;
  } finally {
    await database.close();
  }
}

/// Removes the obsolete app-state database only after all legacy imports commit.
///
/// SQLite sidecars are removed as well. Missing files are treated as already
/// cleaned so an interrupted cleanup can safely retry on the next startup.
Future<void> deleteLegacyAppStateFile() async {
  final file = await _legacyAppStateFile();
  for (final suffix in ['', '-wal', '-shm', '-journal']) {
    final candidate = File('${file.path}$suffix');
    if (await candidate.exists()) {
      await candidate.delete();
    }
  }
}
