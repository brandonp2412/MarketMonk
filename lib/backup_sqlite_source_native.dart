import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3/common.dart';
import 'package:typed_data/typed_buffers.dart';

Future<BackupSqliteSource> openBackupSqlite(Uint8List bytes) async {
  final fs = InMemoryFileSystem(
    name: 'market-monk-backup-${DateTime.now().microsecondsSinceEpoch}',
  );
  fs.fileData['/backup.sqlite'] = Uint8Buffer()..addAll(bytes);
  sqlite3.registerVirtualFileSystem(fs);
  try {
    final database = sqlite3.open(
      '/backup.sqlite',
      vfs: fs.name,
      mode: OpenMode.readOnly,
    );
    return BackupSqliteSource(database, () {
      database.close();
      sqlite3.unregisterVirtualFileSystem(fs);
    });
  } catch (_) {
    sqlite3.unregisterVirtualFileSystem(fs);
    rethrow;
  }
}

class BackupSqliteSource {
  final CommonDatabase database;
  final void Function() close;
  const BackupSqliteSource(this.database, this.close);
}
