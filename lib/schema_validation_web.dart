import 'package:drift/drift.dart';

Future<void> validateDatabaseSchema(GeneratedDatabase database) async {
  final result = await database.customSelect('PRAGMA quick_check').getSingle();
  if (result.read<String>('quick_check') != 'ok') {
    throw StateError('Database integrity check failed');
  }
}
