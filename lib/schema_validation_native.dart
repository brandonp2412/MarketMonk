import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';

Future<void> validateDatabaseSchema(GeneratedDatabase database) =>
    database.validateDatabaseSchema();
