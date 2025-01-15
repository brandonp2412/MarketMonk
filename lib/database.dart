import 'package:drift/drift.dart';
import 'package:drift/internal/versioned_schema.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:market_monk/database.steps.dart';
import 'package:market_monk/tables.dart';
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Tickers, Candles])
class Database extends _$Database {
  @override
  int get schemaVersion => 5;

  Database() : super(_openConnection());

  Database.connect(super.executor);

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'market-monk',
      native: const DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    );
  }

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onUpgrade: (m, from, to) async {
        // Following the advice from https://drift.simonbinder.eu/Migrations/api/#general-tips
        await customStatement('PRAGMA foreign_keys = OFF');

        await transaction(
          () => VersionedSchema.runMigrationSteps(
            migrator: m,
            from: from,
            to: to,
            steps: _upgrade,
          ),
        );

        if (kDebugMode) {
          final wrongForeignKeys =
              await customSelect('PRAGMA foreign_key_check').get();
          assert(
            wrongForeignKeys.isEmpty,
            '${wrongForeignKeys.map((e) => e.data)}',
          );
        }

        await customStatement('PRAGMA foreign_keys = ON');
      },
      beforeOpen: (details) async {
        if (kDebugMode) await validateDatabaseSchema();
      },
    );
  }

  static final _upgrade = migrationSteps(
    from1To2: (m, schema) async {
      await m.alterTable(
        TableMigration(
          schema.tickers,
        ),
      );
    },
    from2To3: (Migrator m, Schema3 schema) async {
      await schema.tickers.deleteAll();
      await m.addColumn(schema.tickers, schema.tickers.name);
    },
    from3To4: (Migrator m, Schema4 schema) async {
      await m.createTable(schema.candles);
    },
    from4To5: (Migrator m, Schema5 schema) async {
      await schema.tickers.deleteAll();
      await m.addColumn(schema.tickers, schema.tickers.price);
    },
  );
}
