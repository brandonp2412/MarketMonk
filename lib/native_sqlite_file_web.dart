import 'dart:io';
import 'package:drift/drift.dart';

QueryExecutor openNativeSqliteFile(File file) => throw UnsupportedError(
      'Filesystem SQLite databases are unavailable on web',
    );
