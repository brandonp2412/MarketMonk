import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

typedef LineWriter = void Function(String line);

class MarketMonkCli {
  MarketMonkCli({
    LineWriter? out,
    LineWriter? err,
    Map<String, String>? environment,
    bool? color,
  })  : _out = out ?? print,
        _err = err ?? ((line) => stderr.writeln(line)),
        _environment = environment ?? Platform.environment,
        _useColor = color ??
            (out == null &&
                stdout.supportsAnsiEscapes &&
                !(environment ?? Platform.environment).containsKey('NO_COLOR'));

  final LineWriter _out;
  final LineWriter _err;
  final Map<String, String> _environment;
  bool _useColor;

  int run(List<String> arguments) {
    try {
      final args = CliArguments.parse(arguments);
      if (args.hasFlag('color')) _useColor = true;
      if (args.hasFlag('no-color')) _useColor = false;
      if (args.hasFlag('help') || args.positionals.isEmpty) {
        _printHelp();
        return 0;
      }

      switch (args.positionals.first) {
        case 'accounts':
          return _accounts(args);
        case 'info':
          return _withDatabase(args, (db, context) => _info(args, db, context));
        case 'trades':
          return _withDatabase(args, (db, context) => _trades(args, db));
        case 'holdings':
          return _withDatabase(args, (db, context) => _holdings(args, db));
        case 'candles':
          return _withDatabase(args, (db, context) => _candles(args, db));
        case 'backup':
          return _withDatabase(args, (db, context) => _backup(args, db));
        case 'query':
          return _withDatabase(args, (db, context) => _query(args, db));
        case 'help':
          _printHelp();
          return 0;
        default:
          throw CliUsageException('Unknown command: ${args.positionals.first}');
      }
    } on CliUsageException catch (error) {
      _err(_red('Error: ${error.message}'));
      _err(_dim('Run with --help for usage.'));
      return 64;
    } on Exception catch (error) {
      _err(_red('Error: $error'));
      return 1;
    }
  }

  int _accounts(CliArguments args) {
    final subcommand =
        args.positionals.length > 1 ? args.positionals[1] : 'list';
    if (subcommand != 'list') {
      throw const CliUsageException('accounts only supports: list');
    }

    final directory = _dataDirectory(args);
    if (!directory.existsSync()) {
      throw CliUsageException(
        'Market Monk data directory does not exist: ${directory.path}',
      );
    }

    final accounts = <Map<String, Object?>>[];
    for (final entity in directory.listSync()) {
      if (entity is! File) continue;
      final account = _accountNameFromDatabaseFile(p.basename(entity.path));
      if (account == null) continue;

      final db = sqlite.sqlite3.open(
        entity.path,
        mode: sqlite.OpenMode.readOnly,
      );
      try {
        accounts.add({
          'account': account,
          'file': entity.path,
          'schemaVersion': db.userVersion,
          'trades': _count(db, 'trades'),
          'candles': _count(db, 'candles'),
        });
      } finally {
        db.close();
      }
    }

    accounts.sort((a, b) {
      if (a['account'] == 'Default') return -1;
      if (b['account'] == 'Default') return 1;
      return (a['account'] as String).compareTo(b['account'] as String);
    });

    if (args.hasFlag('json')) {
      _out(const JsonEncoder.withIndent('  ').convert(accounts));
      return 0;
    }

    if (accounts.isEmpty) {
      _out('No Market Monk databases found in ${directory.path}');
      return 0;
    }

    _out(
      _formatTable(
        ['Account', 'Schema', 'Trades', 'Candles', 'Database'],
        accounts
            .map(
              (item) => [
                item['account'],
                item['schemaVersion'],
                item['trades'],
                item['candles'],
                item['file'],
              ],
            )
            .toList(),
      ),
    );
    return 0;
  }

  int _info(CliArguments args, sqlite.Database db, DatabaseContext context) {
    final integrity = db.select('PRAGMA integrity_check').first.values.first;
    final info = <String, Object?>{
      'account': context.account,
      'database': context.path,
      'schemaVersion': db.userVersion,
      'integrity': integrity,
      'trades': _count(db, 'trades'),
      'candles': _count(db, 'candles'),
    };

    if (args.hasFlag('json')) {
      _out(const JsonEncoder.withIndent('  ').convert(info));
    } else {
      for (final entry in info.entries) {
        _out('${entry.key}: ${entry.value}');
      }
    }
    return 0;
  }

  int _trades(CliArguments args, sqlite.Database db) {
    if (args.positionals.length < 2) {
      throw const CliUsageException(
        'trades requires a subcommand: list, get, add, update, delete',
      );
    }

    switch (args.positionals[1]) {
      case 'list':
        return _tradesList(args, db);
      case 'get':
        return _tradesGet(args, db);
      case 'add':
        return _tradesAdd(args, db);
      case 'update':
        return _tradesUpdate(args, db);
      case 'delete':
        return _tradesDelete(args, db);
      default:
        throw CliUsageException(
          'Unknown trades subcommand: ${args.positionals[1]}',
        );
    }
  }

  int _tradesList(CliArguments args, sqlite.Database db) {
    final where = <String>[];
    final parameters = <Object?>[];

    final symbol = args.option('symbol');
    if (symbol != null) {
      where.add('UPPER(symbol) = ?');
      parameters.add(symbol.toUpperCase());
    }

    final since = args.option('since');
    if (since != null) {
      where.add('trade_date >= ?');
      parameters.add(_toSqliteDate(_parseDate(since)));
    }

    final until = args.option('until');
    if (until != null) {
      where.add('trade_date <= ?');
      parameters.add(_toSqliteDate(_parseDate(until)));
    }

    final limit = args.intOption('limit', fallback: 50);
    if (limit < 1 || limit > 10000) {
      throw const CliUsageException('--limit must be between 1 and 10000');
    }

    final sql = StringBuffer('''
SELECT id, symbol, name, quantity, price, trade_type, trade_date,
       realized_p_l, commission
FROM trades
''');
    if (where.isNotEmpty) sql.write('WHERE ${where.join(' AND ')}\n');
    sql.write('ORDER BY trade_date DESC, id DESC LIMIT ?');
    parameters.add(limit);

    final rows =
        db.select(sql.toString(), parameters).map(_tradeToMap).toList();
    if (args.hasFlag('json')) {
      _out(const JsonEncoder.withIndent('  ').convert(rows));
      return 0;
    }
    if (rows.isEmpty) {
      _out('No trades found.');
      return 0;
    }

    _out(
      _formatTable(
        [
          'ID',
          'Date',
          'Side',
          'Symbol',
          'Quantity',
          'Price',
          'Realized P&L',
          'Commission',
        ],
        rows
            .map(
              (row) => [
                row['id'],
                row['date'],
                row['side'],
                row['symbol'],
                _formatNumber(row['quantity'] as num),
                _formatNumber(row['price'] as num),
                _formatNumber(row['realizedPL'] as num),
                _formatNumber(row['commission'] as num),
              ],
            )
            .toList(),
      ),
    );
    return 0;
  }

  int _tradesGet(CliArguments args, sqlite.Database db) {
    final id = _positionalInt(args, 2, 'trade ID');
    final row = _tradeById(db, id);
    if (row == null) throw CliUsageException('Trade $id does not exist.');
    final mapped = _tradeToMap(row);

    if (args.hasFlag('json')) {
      _out(const JsonEncoder.withIndent('  ').convert(mapped));
    } else {
      for (final entry in mapped.entries) {
        _out('${entry.key}: ${entry.value}');
      }
    }
    return 0;
  }

  int _tradesAdd(CliArguments args, sqlite.Database db) {
    final symbol = _requiredOption(args, 'symbol').trim().toUpperCase();
    if (symbol.isEmpty)
      throw const CliUsageException('--symbol cannot be empty');

    final side = _parseSide(_requiredOption(args, 'side'));
    final quantity = _positiveDouble(args, 'quantity');
    final price = _positiveDouble(args, 'price');
    final name = args.option('name')?.trim();
    final date = args.option('date') == null
        ? DateTime.now()
        : _parseDate(args.option('date')!);
    final realizedPL = args.doubleOption('realized-pl', fallback: 0);
    final commission = args.doubleOption('commission', fallback: 0);
    final signedQuantity = side == TradeSide.buy ? quantity : -quantity;

    db.execute(
      '''
INSERT INTO trades (
  symbol, name, quantity, price, trade_type, trade_date, realized_p_l, commission
) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
''',
      [
        symbol,
        name == null || name.isEmpty ? symbol : name,
        signedQuantity,
        price,
        side == TradeSide.buy ? 'open' : 'close',
        _toSqliteDate(date),
        realizedPL,
        commission,
      ],
    );

    final id = db.lastInsertRowId;
    _out(
      args.hasFlag('json')
          ? jsonEncode({'id': id})
          : _green('Added ${side.label} trade $id for $symbol.'),
    );
    return 0;
  }

  int _tradesUpdate(CliArguments args, sqlite.Database db) {
    final id = _positionalInt(args, 2, 'trade ID');
    final existing = _tradeById(db, id);
    if (existing == null) throw CliUsageException('Trade $id does not exist.');

    final updates = <String>[];
    final parameters = <Object?>[];

    void set(String column, Object? value) {
      updates.add('$column = ?');
      parameters.add(value);
    }

    final symbol = args.option('symbol');
    if (symbol != null) {
      final normalized = symbol.trim().toUpperCase();
      if (normalized.isEmpty) {
        throw const CliUsageException('--symbol cannot be empty');
      }
      set('symbol', normalized);
    }

    final name = args.option('name');
    if (name != null) {
      final normalized = name.trim();
      if (normalized.isEmpty)
        throw const CliUsageException('--name cannot be empty');
      set('name', normalized);
    }

    final requestedSide = args.option('side');
    final existingSide = (existing['quantity'] as num).toDouble() < 0
        ? TradeSide.sell
        : TradeSide.buy;
    final side =
        requestedSide == null ? existingSide : _parseSide(requestedSide);

    if (args.option('quantity') != null || requestedSide != null) {
      final quantity = args.option('quantity') == null
          ? (existing['quantity'] as num).toDouble().abs()
          : _positiveDouble(args, 'quantity');
      set('quantity', side == TradeSide.buy ? quantity : -quantity);
      set('trade_type', side == TradeSide.buy ? 'open' : 'close');
    }

    if (args.option('price') != null)
      set('price', _positiveDouble(args, 'price'));
    if (args.option('date') != null) {
      set('trade_date', _toSqliteDate(_parseDate(args.option('date')!)));
    }
    if (args.option('realized-pl') != null) {
      set('realized_p_l', args.doubleOption('realized-pl'));
    }
    if (args.option('commission') != null) {
      set('commission', args.doubleOption('commission'));
    }

    if (updates.isEmpty) {
      throw const CliUsageException('No trade fields were supplied to update.');
    }

    parameters.add(id);
    db.execute(
      'UPDATE trades SET ${updates.join(', ')} WHERE id = ?',
      parameters,
    );
    _out(
      args.hasFlag('json')
          ? jsonEncode({'updated': id})
          : _green('Updated trade $id.'),
    );
    return 0;
  }

  int _tradesDelete(CliArguments args, sqlite.Database db) {
    final id = _positionalInt(args, 2, 'trade ID');
    if (!args.hasFlag('yes')) {
      throw CliUsageException('Refusing to delete trade $id without --yes.');
    }
    if (_tradeById(db, id) == null) {
      throw CliUsageException('Trade $id does not exist.');
    }

    db.execute('DELETE FROM trades WHERE id = ?', [id]);
    _out(
      args.hasFlag('json')
          ? jsonEncode({'deleted': id})
          : _green('Deleted trade $id.'),
    );
    return 0;
  }

  int _holdings(CliArguments args, sqlite.Database db) {
    final rows = db.select('''
SELECT symbol,
       MAX(name) AS name,
       SUM(quantity) AS quantity,
       COUNT(*) AS trades,
       MAX(trade_date) AS last_trade_date
FROM trades
GROUP BY symbol
HAVING ABS(SUM(quantity)) > 0.000000001
ORDER BY symbol
''');

    final holdings = rows
        .map(
          (row) => {
            'symbol': row['symbol'],
            'name': row['name'],
            'quantity': row['quantity'],
            'trades': row['trades'],
            'lastTradeDate': _dateFromSqlite(row['last_trade_date'] as int),
          },
        )
        .toList();

    if (args.hasFlag('json')) {
      _out(const JsonEncoder.withIndent('  ').convert(holdings));
      return 0;
    }
    if (holdings.isEmpty) {
      _out('No open holdings.');
      return 0;
    }

    _out(
      _formatTable(
        ['Symbol', 'Name', 'Quantity', 'Trades', 'Last trade'],
        holdings
            .map(
              (row) => [
                row['symbol'],
                row['name'],
                _formatNumber(row['quantity'] as num),
                row['trades'],
                row['lastTradeDate'],
              ],
            )
            .toList(),
      ),
    );
    return 0;
  }

  int _candles(CliArguments args, sqlite.Database db) {
    final subcommand =
        args.positionals.length > 1 ? args.positionals[1] : 'stats';
    switch (subcommand) {
      case 'stats':
        final symbol = args.option('symbol')?.toUpperCase();
        final rows = symbol == null
            ? db.select('''
SELECT symbol, COUNT(*) AS rows, MIN(date) AS first_date, MAX(date) AS last_date
FROM candles
GROUP BY symbol
ORDER BY symbol
''')
            : db.select(
                '''
SELECT symbol, COUNT(*) AS rows, MIN(date) AS first_date, MAX(date) AS last_date
FROM candles
WHERE UPPER(symbol) = ?
GROUP BY symbol
ORDER BY symbol
''',
                [symbol],
              );

        final stats = rows
            .map(
              (row) => {
                'symbol': row['symbol'],
                'rows': row['rows'],
                'firstDate': row['first_date'] == null
                    ? null
                    : _dateFromSqlite(row['first_date'] as int),
                'lastDate': row['last_date'] == null
                    ? null
                    : _dateFromSqlite(row['last_date'] as int),
              },
            )
            .toList();

        if (args.hasFlag('json')) {
          _out(const JsonEncoder.withIndent('  ').convert(stats));
        } else if (stats.isEmpty) {
          _out('No candle cache rows found.');
        } else {
          _out(
            _formatTable(
              ['Symbol', 'Rows', 'First', 'Last'],
              stats
                  .map(
                    (row) => [
                      row['symbol'],
                      row['rows'],
                      row['firstDate'],
                      row['lastDate'],
                    ],
                  )
                  .toList(),
            ),
          );
        }
        return 0;

      case 'clear':
        if (!args.hasFlag('yes')) {
          throw const CliUsageException(
            'Refusing to clear candle cache without --yes.',
          );
        }
        final symbol = args.option('symbol')?.toUpperCase();
        final before = _count(db, 'candles');
        if (symbol == null) {
          db.execute('DELETE FROM candles');
        } else {
          db.execute('DELETE FROM candles WHERE UPPER(symbol) = ?', [symbol]);
        }
        final removed = before - _count(db, 'candles');
        _out(
          args.hasFlag('json')
              ? jsonEncode({'deleted': removed, 'symbol': symbol})
              : _green(
                  'Deleted $removed candle cache rows${symbol == null ? '' : ' for $symbol'}.',
                ),
        );
        return 0;

      default:
        throw CliUsageException('Unknown candles subcommand: $subcommand');
    }
  }

  int _backup(CliArguments args, sqlite.Database db) {
    if (args.positionals.length < 2) {
      throw const CliUsageException('backup requires a destination path');
    }

    final destination = File(p.absolute(args.positionals[1]));
    if (destination.existsSync()) {
      if (!args.hasFlag('overwrite')) {
        throw const CliUsageException(
          'Backup destination already exists; pass --overwrite to replace it.',
        );
      }
      destination.deleteSync();
    }
    destination.parent.createSync(recursive: true);

    final escaped = destination.path.replaceAll("'", "''");
    db.execute("VACUUM INTO '$escaped'");

    final backupDb = sqlite.sqlite3.open(
      destination.path,
      mode: sqlite.OpenMode.readOnly,
    );
    try {
      final integrity =
          backupDb.select('PRAGMA integrity_check').first.values.first;
      if (integrity != 'ok') {
        throw StateError('Backup integrity check failed: $integrity');
      }
    } finally {
      backupDb.close();
    }

    _out(
      args.hasFlag('json')
          ? jsonEncode({'backup': destination.path})
          : _green('Backup written to ${destination.path}'),
    );
    return 0;
  }

  int _query(CliArguments args, sqlite.Database db) {
    if (args.positionals.length < 2) {
      throw const CliUsageException('query requires a SQL statement');
    }

    final sql = args.positionals.sublist(1).join(' ').trim();
    final normalized = sql.toLowerCase();
    const allowedPrefixes = ['select', 'pragma', 'with', 'explain'];
    if (!allowedPrefixes.any(normalized.startsWith)) {
      throw const CliUsageException(
        'query is read-only. Use specific trade/cache commands for writes.',
      );
    }

    db.execute('PRAGMA query_only = ON');
    final rows = db.select(sql);
    final mapped = rows
        .map((row) => {for (final column in row.keys) column: row[column]})
        .toList();

    if (args.hasFlag('json')) {
      _out(const JsonEncoder.withIndent('  ').convert(mapped));
      return 0;
    }
    if (mapped.isEmpty) {
      _out('Query returned no rows.');
      return 0;
    }

    final headers = mapped.first.keys.toList();
    _out(
      _formatTable(
        headers,
        mapped
            .map((row) => headers.map((header) => row[header]).toList())
            .toList(),
      ),
    );
    return 0;
  }

  int _withDatabase(
    CliArguments args,
    int Function(sqlite.Database db, DatabaseContext context) action,
  ) {
    final context = _databaseContext(args);
    final file = File(context.path);
    if (!file.existsSync()) {
      throw CliUsageException(
        'Database does not exist: ${file.path}\n'
        'Use "accounts list" to see discovered Market Monk databases.',
      );
    }

    final db = sqlite.sqlite3.open(file.path, mode: sqlite.OpenMode.readWrite);
    try {
      _requireExpectedSchema(db);
      return action(db, context);
    } finally {
      db.close();
    }
  }

  DatabaseContext _databaseContext(CliArguments args) {
    final explicit = args.option('db');
    if (explicit != null) {
      final absolute = p.absolute(explicit);
      return DatabaseContext(
        account: args.option('account') ?? p.basenameWithoutExtension(absolute),
        path: absolute,
      );
    }

    final account = args.option('account') ?? 'Default';
    final filename = account == 'Default'
        ? 'market-monk.sqlite'
        : 'market-monk-$account.sqlite';
    return DatabaseContext(
      account: account,
      path: p.join(_dataDirectory(args).path, filename),
    );
  }

  Directory _dataDirectory(CliArguments args) {
    final explicit = args.option('data-dir');
    if (explicit != null) return Directory(p.absolute(explicit));

    if (Platform.isLinux) {
      final base = _environment['XDG_DATA_HOME'] ??
          p.join(
            _environment['HOME'] ?? Directory.current.path,
            '.local',
            'share',
          );
      return Directory(p.join(base, 'com.codesail.market_monk'));
    }
    if (Platform.isMacOS) {
      final home = _environment['HOME'] ?? Directory.current.path;
      return Directory(
        p.join(
          home,
          'Library',
          'Application Support',
          'com.codesail.market_monk',
        ),
      );
    }
    if (Platform.isWindows) {
      final base = _environment['APPDATA'] ?? _environment['LOCALAPPDATA'];
      if (base != null) {
        return Directory(p.join(base, 'com.codesail.market_monk'));
      }
    }

    throw const CliUsageException(
      'Could not determine the Market Monk data directory. Pass --data-dir.',
    );
  }

  void _requireExpectedSchema(sqlite.Database db) {
    final tables = db
        .select(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('trades', 'candles')",
        )
        .map((row) => row['name'] as String)
        .toSet();
    if (!tables.contains('trades') || !tables.contains('candles')) {
      throw const CliUsageException(
        'This does not look like a Market Monk database '
        '(expected trades and candles tables).',
      );
    }
  }

  sqlite.Row? _tradeById(sqlite.Database db, int id) {
    final rows = db.select(
      '''
SELECT id, symbol, name, quantity, price, trade_type, trade_date,
       realized_p_l, commission
FROM trades
WHERE id = ?
''',
      [id],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Map<String, Object?> _tradeToMap(sqlite.Row row) {
    final quantity = (row['quantity'] as num).toDouble();
    return {
      'id': row['id'],
      'date': _dateFromSqlite(row['trade_date'] as int),
      'side': quantity < 0 ? 'sell' : 'buy',
      'symbol': row['symbol'],
      'name': row['name'],
      'quantity': quantity.abs(),
      'price': row['price'],
      'realizedPL': row['realized_p_l'],
      'commission': row['commission'],
    };
  }

  int _count(sqlite.Database db, String table) {
    try {
      return db.select('SELECT COUNT(*) AS count FROM $table').first['count']
          as int;
    } on sqlite.SqliteException {
      return 0;
    }
  }

  String? _accountNameFromDatabaseFile(String filename) {
    if (filename == 'market-monk.sqlite') return 'Default';
    const prefix = 'market-monk-';
    const suffix = '.sqlite';
    if (!filename.startsWith(prefix) || !filename.endsWith(suffix)) return null;
    final account = filename.substring(
      prefix.length,
      filename.length - suffix.length,
    );
    return account.isEmpty ? null : account;
  }

  DateTime _parseDate(String input) {
    final parsed = DateTime.tryParse(input);
    if (parsed == null) {
      throw CliUsageException(
        'Invalid date "$input". Use ISO-8601, e.g. 2026-10-02 or '
        '2026-10-02T14:30:00+13:00.',
      );
    }
    return parsed;
  }

  int _toSqliteDate(DateTime value) =>
      value.toUtc().millisecondsSinceEpoch ~/ 1000;

  String _dateFromSqlite(int seconds) => DateTime.fromMillisecondsSinceEpoch(
        seconds * 1000,
        isUtc: true,
      ).toLocal().toIso8601String();

  TradeSide _parseSide(String raw) {
    switch (raw.toLowerCase()) {
      case 'buy':
      case 'open':
        return TradeSide.buy;
      case 'sell':
      case 'close':
        return TradeSide.sell;
      default:
        throw const CliUsageException('--side must be buy or sell');
    }
  }

  String _requiredOption(CliArguments args, String name) {
    final value = args.option(name);
    if (value == null) throw CliUsageException('--$name is required');
    return value;
  }

  double _positiveDouble(CliArguments args, String name) {
    final value = args.doubleOption(name);
    if (value <= 0)
      throw CliUsageException('--$name must be greater than zero');
    return value;
  }

  int _positionalInt(CliArguments args, int index, String label) {
    if (args.positionals.length <= index) {
      throw CliUsageException('$label is required');
    }
    final value = int.tryParse(args.positionals[index]);
    if (value == null || value < 1) {
      throw CliUsageException('$label must be a positive integer');
    }
    return value;
  }

  String _formatNumber(num value) {
    final doubleValue = value.toDouble();
    if (doubleValue == doubleValue.roundToDouble()) {
      return doubleValue.toInt().toString();
    }
    return doubleValue.toStringAsFixed(8).replaceFirst(RegExp(r'0+$'), '');
  }

  String _ansi(String text, String code) =>
      _useColor ? '\x1B[${code}m$text\x1B[0m' : text;

  String _cyan(String text, {bool bold = false}) =>
      _ansi(text, bold ? '1;36' : '36');

  String _green(String text) => _ansi(text, '32');

  String _red(String text) => _ansi(text, '31');

  String _dim(String text) => _ansi(text, '2');

  String _formatTable(List<String> headers, List<List<Object?>> rows) {
    final renderedRows = [
      headers,
      ...rows.map(
        (row) => row.map((value) => value?.toString() ?? '').toList(),
      ),
    ];
    final widths = List<int>.generate(
      headers.length,
      (column) => renderedRows
          .map((row) => row[column].length)
          .reduce((left, right) => left > right ? left : right),
    );

    String render(List<String> row) => List<String>.generate(
          row.length,
          (index) => row[index].padRight(widths[index]),
        ).join('  ').trimRight();

    return [
      _cyan(render(renderedRows.first), bold: true),
      _dim(widths.map((width) => '─' * width).join('  ')),
      ...renderedRows.skip(1).map(render),
    ].join('\n');
  }

  void _printHelp() {
    _out(
      [
        _cyan('Market Monk CLI', bold: true),
        '',
        'Usage:',
        '  mm [global options] <command>',
        '',
        'Global options:',
        '  --account NAME       Use a named Market Monk account (default: Default)',
        '  --db PATH            Use an explicit SQLite database path',
        '  --data-dir PATH      Override the Market Monk application-support directory',
        '  --json               Emit machine-readable JSON where supported',
        '  --color              Force ANSI color output',
        '  --no-color           Disable ANSI color output',
        '  --help               Show this help',
        '',
        'Commands:',
        '  accounts list',
        '      Discover Market Monk account databases.',
        '',
        '  info',
        '      Show database path, schema, integrity, and row counts.',
        '',
        '  trades list [--symbol SYMBOL] [--since DATE] [--until DATE] [--limit N]',
        '  trades get ID',
        '  trades add --symbol SYMBOL --side buy|sell --quantity QTY --price PRICE',
        '             [--name NAME] [--date ISO8601] [--realized-pl VALUE]',
        '             [--commission VALUE]',
        '  trades update ID [--symbol SYMBOL] [--name NAME] [--side buy|sell]',
        '                   [--quantity QTY] [--price PRICE] [--date ISO8601]',
        '                   [--realized-pl VALUE] [--commission VALUE]',
        '  trades delete ID --yes',
        '      Read and edit the user trade ledger.',
        '',
        '  holdings',
        '      Show net non-zero quantities derived from trades.',
        '',
        '  candles stats [--symbol SYMBOL]',
        '  candles clear [--symbol SYMBOL] --yes',
        '      Inspect or clear downloaded market-data cache rows.',
        '',
        '  backup PATH [--overwrite]',
        '      Create a consistent SQLite backup.',
        '',
        '  query "SELECT ..."',
        '      Run read-only SELECT/PRAGMA/WITH/EXPLAIN SQL.',
        '',
        'Examples:',
        '  mm accounts list',
        '  mm --account 1 trades list --symbol VTI',
        '  mm trades add --symbol VTI --side buy --quantity 2 --price 312.45',
        '  mm trades update 12 --price 313.10',
        '  mm trades delete 12 --yes',
        '  mm backup ~/backups/market-monk.sqlite',
      ].join('\n'),
    );
  }
}

class CliArguments {
  CliArguments._(this.positionals, this._options);

  final List<String> positionals;
  final Map<String, String?> _options;

  static CliArguments parse(List<String> raw) {
    final positionals = <String>[];
    final options = <String, String?>{};

    for (var i = 0; i < raw.length; i++) {
      final token = raw[i];
      if (!token.startsWith('--')) {
        positionals.add(token);
        continue;
      }

      final option = token.substring(2);
      if (option.isEmpty) throw CliUsageException('Invalid option: $token');

      final equals = option.indexOf('=');
      if (equals >= 0) {
        options[option.substring(0, equals)] = option.substring(equals + 1);
        continue;
      }

      const booleanOptions = {
        'help',
        'json',
        'yes',
        'overwrite',
        'color',
        'no-color',
      };
      if (booleanOptions.contains(option)) {
        options[option] = null;
        continue;
      }

      String? value;
      if (i + 1 < raw.length && !raw[i + 1].startsWith('--')) {
        value = raw[++i];
      }
      options[option] = value;
    }

    return CliArguments._(positionals, options);
  }

  bool hasFlag(String name) => _options.containsKey(name);

  String? option(String name) {
    if (!_options.containsKey(name)) return null;
    final value = _options[name];
    if (value == null) throw CliUsageException('--$name requires a value');
    return value;
  }

  int intOption(String name, {int? fallback}) {
    final raw = option(name);
    if (raw == null) {
      if (fallback != null) return fallback;
      throw CliUsageException('--$name is required');
    }
    final value = int.tryParse(raw);
    if (value == null) throw CliUsageException('--$name must be an integer');
    return value;
  }

  double doubleOption(String name, {double? fallback}) {
    final raw = option(name);
    if (raw == null) {
      if (fallback != null) return fallback;
      throw CliUsageException('--$name is required');
    }
    final value = double.tryParse(raw);
    if (value == null || !value.isFinite) {
      throw CliUsageException('--$name must be a finite number');
    }
    return value;
  }
}

class DatabaseContext {
  const DatabaseContext({required this.account, required this.path});

  final String account;
  final String path;
}

class CliUsageException implements Exception {
  const CliUsageException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum TradeSide {
  buy('buy'),
  sell('sell');

  const TradeSide(this.label);

  final String label;
}
