// dart format width=80
// GENERATED CODE, DO NOT EDIT BY HAND.
// ignore_for_file: type=lint
import 'package:drift/drift.dart';

class Tickers extends Table with TableInfo<Tickers, TickersData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Tickers(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  late final GeneratedColumn<String> symbol = GeneratedColumn<String>(
      'symbol', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  late final GeneratedColumn<double> change = GeneratedColumn<double>(
      'change', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: const CustomExpression(
          'CAST(strftime(\'%s\', CURRENT_TIMESTAMP) AS INTEGER)'));
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: const CustomExpression(
          'CAST(strftime(\'%s\', CURRENT_TIMESTAMP) AS INTEGER)'));
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
      'amount', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, symbol, change, createdAt, updatedAt, amount];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tickers';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TickersData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TickersData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      symbol: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}symbol'])!,
      change: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}change'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      amount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}amount'])!,
    );
  }

  @override
  Tickers createAlias(String alias) {
    return Tickers(attachedDatabase, alias);
  }
}

class TickersData extends DataClass implements Insertable<TickersData> {
  final int id;
  final String symbol;
  final double change;
  final DateTime createdAt;
  final DateTime updatedAt;
  final double amount;
  const TickersData(
      {required this.id,
      required this.symbol,
      required this.change,
      required this.createdAt,
      required this.updatedAt,
      required this.amount});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['symbol'] = Variable<String>(symbol);
    map['change'] = Variable<double>(change);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['amount'] = Variable<double>(amount);
    return map;
  }

  TickersCompanion toCompanion(bool nullToAbsent) {
    return TickersCompanion(
      id: Value(id),
      symbol: Value(symbol),
      change: Value(change),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      amount: Value(amount),
    );
  }

  factory TickersData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TickersData(
      id: serializer.fromJson<int>(json['id']),
      symbol: serializer.fromJson<String>(json['symbol']),
      change: serializer.fromJson<double>(json['change']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      amount: serializer.fromJson<double>(json['amount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'symbol': serializer.toJson<String>(symbol),
      'change': serializer.toJson<double>(change),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'amount': serializer.toJson<double>(amount),
    };
  }

  TickersData copyWith(
          {int? id,
          String? symbol,
          double? change,
          DateTime? createdAt,
          DateTime? updatedAt,
          double? amount}) =>
      TickersData(
        id: id ?? this.id,
        symbol: symbol ?? this.symbol,
        change: change ?? this.change,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        amount: amount ?? this.amount,
      );
  TickersData copyWithCompanion(TickersCompanion data) {
    return TickersData(
      id: data.id.present ? data.id.value : this.id,
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      change: data.change.present ? data.change.value : this.change,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      amount: data.amount.present ? data.amount.value : this.amount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TickersData(')
          ..write('id: $id, ')
          ..write('symbol: $symbol, ')
          ..write('change: $change, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('amount: $amount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, symbol, change, createdAt, updatedAt, amount);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TickersData &&
          other.id == this.id &&
          other.symbol == this.symbol &&
          other.change == this.change &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.amount == this.amount);
}

class TickersCompanion extends UpdateCompanion<TickersData> {
  final Value<int> id;
  final Value<String> symbol;
  final Value<double> change;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<double> amount;
  const TickersCompanion({
    this.id = const Value.absent(),
    this.symbol = const Value.absent(),
    this.change = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.amount = const Value.absent(),
  });
  TickersCompanion.insert({
    this.id = const Value.absent(),
    required String symbol,
    required double change,
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    required double amount,
  })  : symbol = Value(symbol),
        change = Value(change),
        amount = Value(amount);
  static Insertable<TickersData> custom({
    Expression<int>? id,
    Expression<String>? symbol,
    Expression<double>? change,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<double>? amount,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (symbol != null) 'symbol': symbol,
      if (change != null) 'change': change,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (amount != null) 'amount': amount,
    });
  }

  TickersCompanion copyWith(
      {Value<int>? id,
      Value<String>? symbol,
      Value<double>? change,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<double>? amount}) {
    return TickersCompanion(
      id: id ?? this.id,
      symbol: symbol ?? this.symbol,
      change: change ?? this.change,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      amount: amount ?? this.amount,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (symbol.present) {
      map['symbol'] = Variable<String>(symbol.value);
    }
    if (change.present) {
      map['change'] = Variable<double>(change.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TickersCompanion(')
          ..write('id: $id, ')
          ..write('symbol: $symbol, ')
          ..write('change: $change, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('amount: $amount')
          ..write(')'))
        .toString();
  }
}

class DatabaseAtV2 extends GeneratedDatabase {
  DatabaseAtV2(QueryExecutor e) : super(e);
  late final Tickers tickers = Tickers(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [tickers];
  @override
  int get schemaVersion => 2;
}
