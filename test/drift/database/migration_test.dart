// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'dart:ffi';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:market_monk/database.dart';
import 'package:sqlite3/open.dart';
import 'package:test/test.dart';

import 'generated/schema.dart';
import 'generated/schema_v7.dart' as v7;
import 'generated/schema_v8.dart' as v8;
import 'generated/schema_v9.dart' as v9;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    open.overrideForAll(() => DynamicLibrary.open('libsqlite3.so.0'));
    verifier = SchemaVerifier(GeneratedHelper());
  });
}
