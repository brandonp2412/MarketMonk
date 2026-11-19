import 'dart:typed_data';

import 'package:sqlite3/wasm.dart';

Future<SqliteBackupOutput> openSqliteBackupOutput() async {
  final sqlite =
      await WasmSqlite3.loadFromUrl(Uri.base.resolve('sqlite3.wasm'));
  final fs = InMemoryFileSystem(
    name: 'market-monk-export-${DateTime.now().microsecondsSinceEpoch}',
  );
  sqlite.registerVirtualFileSystem(fs);
  try {
    final database = sqlite.open('/market-monk.sqlite', vfs: fs.name);
    return SqliteBackupOutput(
      database,
      () {
        database.close();
        final file = fs.fileData['/market-monk.sqlite'];
        sqlite.unregisterVirtualFileSystem(fs);
        if (file == null) {
          throw const FormatException('SQLite backup was not written');
        }
        return Uint8List.fromList(file);
      },
    );
  } catch (_) {
    sqlite.unregisterVirtualFileSystem(fs);
    rethrow;
  }
}

class SqliteBackupOutput {
  const SqliteBackupOutput(this.database, this.closeAndRead);

  final CommonDatabase database;
  final Uint8List Function() closeAndRead;
}
