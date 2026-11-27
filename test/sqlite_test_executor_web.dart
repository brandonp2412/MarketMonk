import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

QueryExecutor createTestExecutor() => LazyDatabase(() async {
      final probed = await WasmDatabase.probe(
        databaseName: 'market_monk_screenshot',
        sqlite3Uri: Uri.parse('sqlite3.wasm'),
        driftWorkerUri: Uri.parse('drift_worker.dart.js'),
      );
      return probed.open(
        WasmStorageImplementation.inMemory,
        'market_monk_screenshot',
      );
    });
