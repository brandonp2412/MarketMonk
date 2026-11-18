import 'dart:typed_data';

import 'package:sqlite3/wasm.dart';
import 'package:typed_data/typed_buffers.dart';

Future<BackupSqliteSource> openBackupSqlite(Uint8List bytes) async {
  final sqlite = await WasmSqlite3.loadFromUrl(
    Uri.base.resolve('sqlite3.wasm'),
  );
  final fs = InMemoryFileSystem(
    name: 'market-monk-backup-${DateTime.now().microsecondsSinceEpoch}',
  );
  fs.fileData['/backup.sqlite'] = Uint8Buffer()..addAll(bytes);
  sqlite.registerVirtualFileSystem(fs);
  try {
    final database = sqlite.open(
      '/backup.sqlite',
      vfs: fs.name,
      mode: OpenMode.readOnly,
    );
    return BackupSqliteSource(database, () {
      database.close();
      sqlite.unregisterVirtualFileSystem(fs);
    });
  } catch (_) {
    sqlite.unregisterVirtualFileSystem(fs);
    rethrow;
  }
}

class BackupSqliteSource {
  final CommonDatabase database;
  final void Function() close;
  const BackupSqliteSource(this.database, this.close);
}
