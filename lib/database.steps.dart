// dart format width=80
import 'package:drift/internal/versioned_schema.dart' as i0;
import 'package:drift/drift.dart' as i1;
import 'package:drift/drift.dart'; // ignore_for_file: type=lint,unused_import

// GENERATED BY drift_dev, DO NOT MODIFY.
final class Schema2 extends i0.VersionedSchema {
  Schema2({required super.database}) : super(version: 2);
  @override
  late final List<i1.DatabaseSchemaEntity> entities = [
    tickers,
  ];
  late final Shape0 tickers = Shape0(
      source: i0.VersionedTable(
        entityName: 'tickers',
        withoutRowId: false,
        isStrict: false,
        tableConstraints: [],
        columns: [
          _column_0,
          _column_1,
          _column_2,
          _column_3,
          _column_4,
          _column_5,
        ],
        attachedDatabase: database,
      ),
      alias: null);
}

class Shape0 extends i0.VersionedTable {
  Shape0({required super.source, required super.alias}) : super.aliased();
  i1.GeneratedColumn<int> get id =>
      columnsByName['id']! as i1.GeneratedColumn<int>;
  i1.GeneratedColumn<String> get symbol =>
      columnsByName['symbol']! as i1.GeneratedColumn<String>;
  i1.GeneratedColumn<double> get change =>
      columnsByName['change']! as i1.GeneratedColumn<double>;
  i1.GeneratedColumn<DateTime> get createdAt =>
      columnsByName['created_at']! as i1.GeneratedColumn<DateTime>;
  i1.GeneratedColumn<DateTime> get updatedAt =>
      columnsByName['updated_at']! as i1.GeneratedColumn<DateTime>;
  i1.GeneratedColumn<double> get amount =>
      columnsByName['amount']! as i1.GeneratedColumn<double>;
}

i1.GeneratedColumn<int> _column_0(String aliasedName) =>
    i1.GeneratedColumn<int>('id', aliasedName, false,
        hasAutoIncrement: true,
        type: i1.DriftSqlType.int,
        defaultConstraints:
            i1.GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
i1.GeneratedColumn<String> _column_1(String aliasedName) =>
    i1.GeneratedColumn<String>('symbol', aliasedName, false,
        type: i1.DriftSqlType.string,
        defaultConstraints: i1.GeneratedColumn.constraintIsAlways('UNIQUE'));
i1.GeneratedColumn<double> _column_2(String aliasedName) =>
    i1.GeneratedColumn<double>('change', aliasedName, false,
        type: i1.DriftSqlType.double);
i1.GeneratedColumn<DateTime> _column_3(String aliasedName) =>
    i1.GeneratedColumn<DateTime>('created_at', aliasedName, false,
        type: i1.DriftSqlType.dateTime,
        defaultValue: const CustomExpression(
            'CAST(strftime(\'%s\', CURRENT_TIMESTAMP) AS INTEGER)'));
i1.GeneratedColumn<DateTime> _column_4(String aliasedName) =>
    i1.GeneratedColumn<DateTime>('updated_at', aliasedName, false,
        type: i1.DriftSqlType.dateTime,
        defaultValue: const CustomExpression(
            'CAST(strftime(\'%s\', CURRENT_TIMESTAMP) AS INTEGER)'));
i1.GeneratedColumn<double> _column_5(String aliasedName) =>
    i1.GeneratedColumn<double>('amount', aliasedName, false,
        type: i1.DriftSqlType.double);

final class Schema3 extends i0.VersionedSchema {
  Schema3({required super.database}) : super(version: 3);
  @override
  late final List<i1.DatabaseSchemaEntity> entities = [
    tickers,
  ];
  late final Shape1 tickers = Shape1(
      source: i0.VersionedTable(
        entityName: 'tickers',
        withoutRowId: false,
        isStrict: false,
        tableConstraints: [],
        columns: [
          _column_0,
          _column_1,
          _column_6,
          _column_2,
          _column_3,
          _column_4,
          _column_5,
        ],
        attachedDatabase: database,
      ),
      alias: null);
}

class Shape1 extends i0.VersionedTable {
  Shape1({required super.source, required super.alias}) : super.aliased();
  i1.GeneratedColumn<int> get id =>
      columnsByName['id']! as i1.GeneratedColumn<int>;
  i1.GeneratedColumn<String> get symbol =>
      columnsByName['symbol']! as i1.GeneratedColumn<String>;
  i1.GeneratedColumn<String> get name =>
      columnsByName['name']! as i1.GeneratedColumn<String>;
  i1.GeneratedColumn<double> get change =>
      columnsByName['change']! as i1.GeneratedColumn<double>;
  i1.GeneratedColumn<DateTime> get createdAt =>
      columnsByName['created_at']! as i1.GeneratedColumn<DateTime>;
  i1.GeneratedColumn<DateTime> get updatedAt =>
      columnsByName['updated_at']! as i1.GeneratedColumn<DateTime>;
  i1.GeneratedColumn<double> get amount =>
      columnsByName['amount']! as i1.GeneratedColumn<double>;
}

i1.GeneratedColumn<String> _column_6(String aliasedName) =>
    i1.GeneratedColumn<String>('name', aliasedName, false,
        type: i1.DriftSqlType.string);

final class Schema4 extends i0.VersionedSchema {
  Schema4({required super.database}) : super(version: 4);
  @override
  late final List<i1.DatabaseSchemaEntity> entities = [
    tickers,
    candles,
  ];
  late final Shape1 tickers = Shape1(
      source: i0.VersionedTable(
        entityName: 'tickers',
        withoutRowId: false,
        isStrict: false,
        tableConstraints: [],
        columns: [
          _column_0,
          _column_1,
          _column_6,
          _column_2,
          _column_3,
          _column_4,
          _column_5,
        ],
        attachedDatabase: database,
      ),
      alias: null);
  late final Shape2 candles = Shape2(
      source: i0.VersionedTable(
        entityName: 'candles',
        withoutRowId: false,
        isStrict: false,
        tableConstraints: [],
        columns: [
          _column_0,
          _column_7,
          _column_8,
          _column_9,
          _column_10,
          _column_11,
          _column_12,
          _column_13,
          _column_14,
        ],
        attachedDatabase: database,
      ),
      alias: null);
}

class Shape2 extends i0.VersionedTable {
  Shape2({required super.source, required super.alias}) : super.aliased();
  i1.GeneratedColumn<int> get id =>
      columnsByName['id']! as i1.GeneratedColumn<int>;
  i1.GeneratedColumn<String> get symbol =>
      columnsByName['symbol']! as i1.GeneratedColumn<String>;
  i1.GeneratedColumn<DateTime> get date =>
      columnsByName['date']! as i1.GeneratedColumn<DateTime>;
  i1.GeneratedColumn<double> get open =>
      columnsByName['open']! as i1.GeneratedColumn<double>;
  i1.GeneratedColumn<double> get high =>
      columnsByName['high']! as i1.GeneratedColumn<double>;
  i1.GeneratedColumn<double> get low =>
      columnsByName['low']! as i1.GeneratedColumn<double>;
  i1.GeneratedColumn<double> get close =>
      columnsByName['close']! as i1.GeneratedColumn<double>;
  i1.GeneratedColumn<int> get volume =>
      columnsByName['volume']! as i1.GeneratedColumn<int>;
  i1.GeneratedColumn<double> get adjClose =>
      columnsByName['adj_close']! as i1.GeneratedColumn<double>;
}

i1.GeneratedColumn<String> _column_7(String aliasedName) =>
    i1.GeneratedColumn<String>('symbol', aliasedName, false,
        type: i1.DriftSqlType.string,
        defaultConstraints: i1.GeneratedColumn.constraintIsAlways(
            'REFERENCES tickers (symbol)'));
i1.GeneratedColumn<DateTime> _column_8(String aliasedName) =>
    i1.GeneratedColumn<DateTime>('date', aliasedName, false,
        type: i1.DriftSqlType.dateTime);
i1.GeneratedColumn<double> _column_9(String aliasedName) =>
    i1.GeneratedColumn<double>('open', aliasedName, false,
        type: i1.DriftSqlType.double,
        defaultValue: const CustomExpression('-1.0'));
i1.GeneratedColumn<double> _column_10(String aliasedName) =>
    i1.GeneratedColumn<double>('high', aliasedName, false,
        type: i1.DriftSqlType.double,
        defaultValue: const CustomExpression('-1.0'));
i1.GeneratedColumn<double> _column_11(String aliasedName) =>
    i1.GeneratedColumn<double>('low', aliasedName, false,
        type: i1.DriftSqlType.double,
        defaultValue: const CustomExpression('-1.0'));
i1.GeneratedColumn<double> _column_12(String aliasedName) =>
    i1.GeneratedColumn<double>('close', aliasedName, false,
        type: i1.DriftSqlType.double,
        defaultValue: const CustomExpression('-1.0'));
i1.GeneratedColumn<int> _column_13(String aliasedName) =>
    i1.GeneratedColumn<int>('volume', aliasedName, false,
        type: i1.DriftSqlType.int, defaultValue: const CustomExpression('0'));
i1.GeneratedColumn<double> _column_14(String aliasedName) =>
    i1.GeneratedColumn<double>('adj_close', aliasedName, false,
        type: i1.DriftSqlType.double,
        defaultValue: const CustomExpression('-1.0'));

final class Schema5 extends i0.VersionedSchema {
  Schema5({required super.database}) : super(version: 5);
  @override
  late final List<i1.DatabaseSchemaEntity> entities = [
    tickers,
    candles,
  ];
  late final Shape3 tickers = Shape3(
      source: i0.VersionedTable(
        entityName: 'tickers',
        withoutRowId: false,
        isStrict: false,
        tableConstraints: [],
        columns: [
          _column_0,
          _column_1,
          _column_6,
          _column_2,
          _column_3,
          _column_4,
          _column_5,
          _column_15,
        ],
        attachedDatabase: database,
      ),
      alias: null);
  late final Shape2 candles = Shape2(
      source: i0.VersionedTable(
        entityName: 'candles',
        withoutRowId: false,
        isStrict: false,
        tableConstraints: [],
        columns: [
          _column_0,
          _column_7,
          _column_8,
          _column_9,
          _column_10,
          _column_11,
          _column_12,
          _column_13,
          _column_14,
        ],
        attachedDatabase: database,
      ),
      alias: null);
}

class Shape3 extends i0.VersionedTable {
  Shape3({required super.source, required super.alias}) : super.aliased();
  i1.GeneratedColumn<int> get id =>
      columnsByName['id']! as i1.GeneratedColumn<int>;
  i1.GeneratedColumn<String> get symbol =>
      columnsByName['symbol']! as i1.GeneratedColumn<String>;
  i1.GeneratedColumn<String> get name =>
      columnsByName['name']! as i1.GeneratedColumn<String>;
  i1.GeneratedColumn<double> get change =>
      columnsByName['change']! as i1.GeneratedColumn<double>;
  i1.GeneratedColumn<DateTime> get createdAt =>
      columnsByName['created_at']! as i1.GeneratedColumn<DateTime>;
  i1.GeneratedColumn<DateTime> get updatedAt =>
      columnsByName['updated_at']! as i1.GeneratedColumn<DateTime>;
  i1.GeneratedColumn<double> get amount =>
      columnsByName['amount']! as i1.GeneratedColumn<double>;
  i1.GeneratedColumn<double> get price =>
      columnsByName['price']! as i1.GeneratedColumn<double>;
}

i1.GeneratedColumn<double> _column_15(String aliasedName) =>
    i1.GeneratedColumn<double>('price', aliasedName, false,
        type: i1.DriftSqlType.double);
i0.MigrationStepWithVersion migrationSteps({
  required Future<void> Function(i1.Migrator m, Schema2 schema) from1To2,
  required Future<void> Function(i1.Migrator m, Schema3 schema) from2To3,
  required Future<void> Function(i1.Migrator m, Schema4 schema) from3To4,
  required Future<void> Function(i1.Migrator m, Schema5 schema) from4To5,
}) {
  return (currentVersion, database) async {
    switch (currentVersion) {
      case 1:
        final schema = Schema2(database: database);
        final migrator = i1.Migrator(database, schema);
        await from1To2(migrator, schema);
        return 2;
      case 2:
        final schema = Schema3(database: database);
        final migrator = i1.Migrator(database, schema);
        await from2To3(migrator, schema);
        return 3;
      case 3:
        final schema = Schema4(database: database);
        final migrator = i1.Migrator(database, schema);
        await from3To4(migrator, schema);
        return 4;
      case 4:
        final schema = Schema5(database: database);
        final migrator = i1.Migrator(database, schema);
        await from4To5(migrator, schema);
        return 5;
      default:
        throw ArgumentError.value('Unknown migration from $currentVersion');
    }
  };
}

i1.OnUpgrade stepByStep({
  required Future<void> Function(i1.Migrator m, Schema2 schema) from1To2,
  required Future<void> Function(i1.Migrator m, Schema3 schema) from2To3,
  required Future<void> Function(i1.Migrator m, Schema4 schema) from3To4,
  required Future<void> Function(i1.Migrator m, Schema5 schema) from4To5,
}) =>
    i0.VersionedSchema.stepByStepHelper(
        step: migrationSteps(
      from1To2: from1To2,
      from2To3: from2To3,
      from3To4: from3To4,
      from4To5: from4To5,
    ));
