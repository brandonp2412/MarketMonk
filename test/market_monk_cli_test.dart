import 'dart:io';

import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import '../tool/src/market_monk_cli.dart';

void main() {
  test('global boolean flags do not consume the command', () {
    final args = CliArguments.parse(['--json', 'accounts', 'list']);
    expect(args.hasFlag('json'), isTrue);
    expect(args.positionals, ['accounts', 'list']);
  });

  group('trade CRUD', () {
    late Directory tempDir;
    late String databasePath;
    late List<String> stdoutLines;
    late List<String> stderrLines;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('market-monk-cli-test-');
      databasePath = '${tempDir.path}/market-monk.sqlite';
      _createDatabase(databasePath);
      stdoutLines = [];
      stderrLines = [];
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    MarketMonkCli cli() => MarketMonkCli(
          out: stdoutLines.add,
          err: stderrLines.add,
        );

    test('adds, updates, and deletes a trade with app-compatible signs', () {
      final addExit = cli().run([
        '--db',
        databasePath,
        'trades',
        'add',
        '--symbol',
        'vti',
        '--name',
        'Vanguard Total Stock Market ETF',
        '--side',
        'buy',
        '--quantity',
        '2.5',
        '--price',
        '312.45',
        '--date',
        '2026-10-02T14:30:00+13:00',
      ]);
      expect(addExit, 0);

      var db = sqlite.sqlite3.open(databasePath);
      var row = db.select('SELECT * FROM trades').single;
      expect(row['symbol'], 'VTI');
      expect(row['quantity'], 2.5);
      expect(row['trade_type'], 'open');
      final id = row['id'] as int;
      db.close();

      final updateExit = cli().run([
        '--db',
        databasePath,
        'trades',
        'update',
        id.toString(),
        '--side',
        'sell',
        '--quantity',
        '1.25',
        '--price',
        '320',
        '--realized-pl',
        '12.5',
      ]);
      expect(updateExit, 0);

      db = sqlite.sqlite3.open(databasePath);
      row = db.select('SELECT * FROM trades WHERE id = ?', [id]).single;
      expect(row['quantity'], -1.25);
      expect(row['trade_type'], 'close');
      expect(row['price'], 320.0);
      expect(row['realized_p_l'], 12.5);
      db.close();

      final refusedExit = cli().run([
        '--db',
        databasePath,
        'trades',
        'delete',
        id.toString(),
      ]);
      expect(refusedExit, 64);

      db = sqlite.sqlite3.open(databasePath);
      expect(db.select('SELECT COUNT(*) AS n FROM trades').single['n'], 1);
      db.close();

      final deleteExit = cli().run([
        '--db',
        databasePath,
        'trades',
        'delete',
        id.toString(),
        '--yes',
      ]);
      expect(deleteExit, 0);

      db = sqlite.sqlite3.open(databasePath);
      expect(db.select('SELECT COUNT(*) AS n FROM trades').single['n'], 0);
      db.close();
    });

    test('query rejects mutating SQL', () {
      final exitCode = cli().run([
        '--db',
        databasePath,
        'query',
        'DELETE FROM trades',
      ]);

      expect(exitCode, 64);
      expect(stderrLines.join('\n'), contains('query is read-only'));
    });

    test('backup produces an integrity-checked database', () {
      final backupPath = '${tempDir.path}/backup.sqlite';
      final exitCode = cli().run([
        '--db',
        databasePath,
        'backup',
        backupPath,
      ]);

      expect(exitCode, 0);
      final db = sqlite.sqlite3.open(
        backupPath,
        mode: sqlite.OpenMode.readOnly,
      );
      expect(db.select('PRAGMA integrity_check').single.values.single, 'ok');
      db.close();
    });
  });
}

void _createDatabase(String path) {
  final db = sqlite.sqlite3.open(path);
  db.execute('''
CREATE TABLE trades (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  symbol TEXT NOT NULL,
  name TEXT NOT NULL,
  quantity REAL NOT NULL,
  price REAL NOT NULL,
  trade_type TEXT NOT NULL,
  trade_date INTEGER NOT NULL,
  realized_p_l REAL NOT NULL DEFAULT 0,
  commission REAL NOT NULL DEFAULT 0
);
''');
  db.execute('''
CREATE TABLE candles (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  symbol TEXT NOT NULL,
  date INTEGER NOT NULL,
  open REAL NOT NULL DEFAULT -1,
  high REAL NOT NULL DEFAULT -1,
  low REAL NOT NULL DEFAULT -1,
  close REAL NOT NULL DEFAULT -1,
  volume INTEGER NOT NULL DEFAULT 0,
  adj_close REAL NOT NULL DEFAULT -1
);
''');
  db.userVersion = 10;
  db.close();
}
