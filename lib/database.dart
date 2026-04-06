import 'package:drift/drift.dart';
import 'package:drift/internal/versioned_schema.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:market_monk/database.steps.dart';
import 'package:market_monk/tables.dart';
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Candles, Trades])
class Database extends _$Database {
  @override
  int get schemaVersion => 9;

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
        await customStatement('PRAGMA foreign_keys = OFF');

        await transaction(
          () => VersionedSchema.runMigrationSteps(
            migrator: m,
            from: from,
            to: to,
            steps: _upgrade,
          ),
        );

        // The actual data/schema work for 8→9 happens here where we have
        // access to customStatement. The step registered in _upgrade is a
        // no-op that only advances the version number.
        if (from < 9 && to >= 9) {
          await _migrateTickersToTrades();
        }

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

  /// Converts tickers with no corresponding buy trades into open trades,
  /// recreates the candles table without the FK to tickers, then drops tickers.
  Future<void> _migrateTickersToTrades() async {
    // Guard: tickers might not exist if schema was already clean.
    final tableExists = await customSelect(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name='tickers'",
    ).get();
    if (tableExists.isEmpty) return;

    // Preserve any tickers that have no buy trades by recording them.
    await customStatement('''
      INSERT OR IGNORE INTO trades
        (symbol, name, quantity, price, trade_type, trade_date, realized_p_l, commission)
      SELECT
        symbol, name, amount, price, 'open',
        COALESCE(purchased_at, CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
        0.0, 0.0
      FROM tickers
      WHERE NOT EXISTS (
        SELECT 1 FROM trades t2
        WHERE t2.symbol = tickers.symbol AND t2.trade_type = 'open'
      )
    ''');

    // Recreate candles without the FK constraint that references tickers.
    await customStatement('''
      CREATE TABLE new_candles (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        symbol TEXT NOT NULL,
        date INTEGER NOT NULL,
        open REAL NOT NULL DEFAULT (-1.0),
        high REAL NOT NULL DEFAULT (-1.0),
        low REAL NOT NULL DEFAULT (-1.0),
        close REAL NOT NULL DEFAULT (-1.0),
        volume INTEGER NOT NULL DEFAULT 0,
        adj_close REAL NOT NULL DEFAULT (-1.0)
      )
    ''');
    await customStatement('INSERT INTO new_candles SELECT * FROM candles');
    await customStatement('DROP TABLE candles');
    await customStatement('ALTER TABLE new_candles RENAME TO candles');

    await customStatement('DROP TABLE tickers');
  }

  static final _upgrade = migrationSteps(
    from1To2: (m, schema) async {
      await m.alterTable(TableMigration(schema.tickers));
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
    from5To6: (Migrator m, Schema6 schema) async {
      await m.drop(schema.candles);
      await m.drop(schema.tickers);
      await m.createTable(schema.tickers);
    },
    from6To7: (Migrator m, Schema7 schema) async {
      await m.alterTable(TableMigration(schema.tickers));
    },
    from7To8: (Migrator m, Schema8 schema) async {
      await m.createTable(schema.trades);
    },
    // No-op: version bump only. Real work done in _migrateTickersToTrades().
    from8To9: (Migrator m, Schema9 schema) async {},
  );
}
