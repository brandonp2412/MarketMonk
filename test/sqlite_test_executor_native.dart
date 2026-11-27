import 'package:drift/drift.dart';
import 'package:drift/native.dart';

QueryExecutor createTestExecutor() => NativeDatabase.memory();
