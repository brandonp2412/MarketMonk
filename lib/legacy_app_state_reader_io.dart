import 'dart:io';

import 'package:drift/native.dart';
import 'package:market_monk/app_state_database.dart';
import 'package:path_provider/path_provider.dart';

Future<Map<String, Object?>?> readLegacyAppStateFile() async {
  final directory = await getApplicationSupportDirectory();
  final file = File('${directory.path}/market-monk-app-state.sqlite');
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
