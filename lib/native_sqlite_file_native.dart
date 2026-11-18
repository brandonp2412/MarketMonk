import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

QueryExecutor openNativeSqliteFile(File file) => NativeDatabase(file);
