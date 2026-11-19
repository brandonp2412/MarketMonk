import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

Future<bool> isUnifiedBackupSqlite(File file) async {
  final source = sqlite3.open(file.path, mode: OpenMode.readOnly);
  try {
    final names = source
        .select("SELECT name FROM sqlite_master WHERE type='table'")
        .map((row) => row['name'] as String)
        .toSet();
    return names.containsAll({
      'profiles',
      'app_state',
      'app_settings',
      'trades',
      'candles',
    });
  } finally {
    source.close();
  }
}
