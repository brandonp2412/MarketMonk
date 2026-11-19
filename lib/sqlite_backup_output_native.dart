import 'dart:typed_data';

import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

Future<SqliteBackupOutput> openSqliteBackupOutput() async {
  final fs = InMemoryFileSystem(
    name: 'market-monk-export-${DateTime.now().microsecondsSinceEpoch}',
  );
  sqlite3.registerVirtualFileSystem(fs);
  try {
    final database = sqlite3.open('/market-monk.sqlite', vfs: fs.name);
    return SqliteBackupOutput(
      database,
      () {
        database.close();
        final file = fs.fileData['/market-monk.sqlite'];
        sqlite3.unregisterVirtualFileSystem(fs);
        if (file == null) {
          throw const FormatException('SQLite backup was not written');
        }
        return Uint8List.fromList(file);
      },
    );
  } catch (_) {
    sqlite3.unregisterVirtualFileSystem(fs);
    rethrow;
  }
}

class SqliteBackupOutput {
  const SqliteBackupOutput(this.database, this.closeAndRead);

  final CommonDatabase database;
  final Uint8List Function() closeAndRead;
}
