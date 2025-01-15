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
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
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
      [id, symbol, name, change, createdAt, updatedAt, amount];
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
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
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
  final String name;
  final double change;
  final DateTime createdAt;
  final DateTime updatedAt;
  final double amount;
  const TickersData(
      {required this.id,
      required this.symbol,
      required this.name,
      required this.change,
      required this.createdAt,
      required this.updatedAt,
      required this.amount});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['symbol'] = Variable<String>(symbol);
    map['name'] = Variable<String>(name);
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
      name: Value(name),
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
      name: serializer.fromJson<String>(json['name']),
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
      'name': serializer.toJson<String>(name),
      'change': serializer.toJson<double>(change),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'amount': serializer.toJson<double>(amount),
    };
  }

  TickersData copyWith(
          {int? id,
          String? symbol,
          String? name,
          double? change,
          DateTime? createdAt,
          DateTime? updatedAt,
          double? amount}) =>
      TickersData(
        id: id ?? this.id,
        symbol: symbol ?? this.symbol,
        name: name ?? this.name,
        change: change ?? this.change,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        amount: amount ?? this.amount,
      );
  TickersData copyWithCompanion(TickersCompanion data) {
    return TickersData(
      id: data.id.present ? data.id.value : this.id,
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      name: data.name.present ? data.name.value : this.name,
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
          ..write('name: $name, ')
          ..write('change: $change, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('amount: $amount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, symbol, name, change, createdAt, updatedAt, amount);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TickersData &&
          other.id == this.id &&
          other.symbol == this.symbol &&
          other.name == this.name &&
          other.change == this.change &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.amount == this.amount);
}

class TickersCompanion extends UpdateCompanion<TickersData> {
  final Value<int> id;
  final Value<String> symbol;
  final Value<String> name;
  final Value<double> change;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<double> amount;
  const TickersCompanion({
    this.id = const Value.absent(),
    this.symbol = const Value.absent(),
    this.name = const Value.absent(),
    this.change = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.amount = const Value.absent(),
  });
  TickersCompanion.insert({
    this.id = const Value.absent(),
    required String symbol,
    required String name,
    required double change,
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    required double amount,
  })  : symbol = Value(symbol),
        name = Value(name),
        change = Value(change),
        amount = Value(amount);
  static Insertable<TickersData> custom({
    Expression<int>? id,
    Expression<String>? symbol,
    Expression<String>? name,
    Expression<double>? change,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<double>? amount,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (symbol != null) 'symbol': symbol,
      if (name != null) 'name': name,
      if (change != null) 'change': change,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (amount != null) 'amount': amount,
    });
  }

  TickersCompanion copyWith(
      {Value<int>? id,
      Value<String>? symbol,
      Value<String>? name,
      Value<double>? change,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<double>? amount}) {
    return TickersCompanion(
      id: id ?? this.id,
      symbol: symbol ?? this.symbol,
      name: name ?? this.name,
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
    if (name.present) {
      map['name'] = Variable<String>(name.value);
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
          ..write('name: $name, ')
          ..write('change: $change, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('amount: $amount')
          ..write(')'))
        .toString();
  }
}

class Candles extends Table with TableInfo<Candles, CandlesData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Candles(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
      'date', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  late final GeneratedColumn<double> open = GeneratedColumn<double>(
      'open', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const CustomExpression('-1.0'));
  late final GeneratedColumn<double> high = GeneratedColumn<double>(
      'high', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const CustomExpression('-1.0'));
  late final GeneratedColumn<double> low = GeneratedColumn<double>(
      'low', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const CustomExpression('-1.0'));
  late final GeneratedColumn<double> close = GeneratedColumn<double>(
      'close', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const CustomExpression('-1.0'));
  late final GeneratedColumn<int> volume = GeneratedColumn<int>(
      'volume', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const CustomExpression('0'));
  late final GeneratedColumn<double> adjClose = GeneratedColumn<double>(
      'adj_close', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const CustomExpression('-1.0'));
  @override
  List<GeneratedColumn> get $columns =>
      [id, date, open, high, low, close, volume, adjClose];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'candles';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CandlesData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CandlesData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      date: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}date'])!,
      open: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}open'])!,
      high: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}high'])!,
      low: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}low'])!,
      close: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}close'])!,
      volume: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}volume'])!,
      adjClose: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}adj_close'])!,
    );
  }

  @override
  Candles createAlias(String alias) {
    return Candles(attachedDatabase, alias);
  }
}

class CandlesData extends DataClass implements Insertable<CandlesData> {
  final int id;
  final DateTime date;
  final double open;
  final double high;
  final double low;
  final double close;
  final int volume;
  final double adjClose;
  const CandlesData(
      {required this.id,
      required this.date,
      required this.open,
      required this.high,
      required this.low,
      required this.close,
      required this.volume,
      required this.adjClose});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['date'] = Variable<DateTime>(date);
    map['open'] = Variable<double>(open);
    map['high'] = Variable<double>(high);
    map['low'] = Variable<double>(low);
    map['close'] = Variable<double>(close);
    map['volume'] = Variable<int>(volume);
    map['adj_close'] = Variable<double>(adjClose);
    return map;
  }

  CandlesCompanion toCompanion(bool nullToAbsent) {
    return CandlesCompanion(
      id: Value(id),
      date: Value(date),
      open: Value(open),
      high: Value(high),
      low: Value(low),
      close: Value(close),
      volume: Value(volume),
      adjClose: Value(adjClose),
    );
  }

  factory CandlesData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CandlesData(
      id: serializer.fromJson<int>(json['id']),
      date: serializer.fromJson<DateTime>(json['date']),
      open: serializer.fromJson<double>(json['open']),
      high: serializer.fromJson<double>(json['high']),
      low: serializer.fromJson<double>(json['low']),
      close: serializer.fromJson<double>(json['close']),
      volume: serializer.fromJson<int>(json['volume']),
      adjClose: serializer.fromJson<double>(json['adjClose']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'date': serializer.toJson<DateTime>(date),
      'open': serializer.toJson<double>(open),
      'high': serializer.toJson<double>(high),
      'low': serializer.toJson<double>(low),
      'close': serializer.toJson<double>(close),
      'volume': serializer.toJson<int>(volume),
      'adjClose': serializer.toJson<double>(adjClose),
    };
  }

  CandlesData copyWith(
          {int? id,
          DateTime? date,
          double? open,
          double? high,
          double? low,
          double? close,
          int? volume,
          double? adjClose}) =>
      CandlesData(
        id: id ?? this.id,
        date: date ?? this.date,
        open: open ?? this.open,
        high: high ?? this.high,
        low: low ?? this.low,
        close: close ?? this.close,
        volume: volume ?? this.volume,
        adjClose: adjClose ?? this.adjClose,
      );
  CandlesData copyWithCompanion(CandlesCompanion data) {
    return CandlesData(
      id: data.id.present ? data.id.value : this.id,
      date: data.date.present ? data.date.value : this.date,
      open: data.open.present ? data.open.value : this.open,
      high: data.high.present ? data.high.value : this.high,
      low: data.low.present ? data.low.value : this.low,
      close: data.close.present ? data.close.value : this.close,
      volume: data.volume.present ? data.volume.value : this.volume,
      adjClose: data.adjClose.present ? data.adjClose.value : this.adjClose,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CandlesData(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('open: $open, ')
          ..write('high: $high, ')
          ..write('low: $low, ')
          ..write('close: $close, ')
          ..write('volume: $volume, ')
          ..write('adjClose: $adjClose')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, date, open, high, low, close, volume, adjClose);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CandlesData &&
          other.id == this.id &&
          other.date == this.date &&
          other.open == this.open &&
          other.high == this.high &&
          other.low == this.low &&
          other.close == this.close &&
          other.volume == this.volume &&
          other.adjClose == this.adjClose);
}

class CandlesCompanion extends UpdateCompanion<CandlesData> {
  final Value<int> id;
  final Value<DateTime> date;
  final Value<double> open;
  final Value<double> high;
  final Value<double> low;
  final Value<double> close;
  final Value<int> volume;
  final Value<double> adjClose;
  const CandlesCompanion({
    this.id = const Value.absent(),
    this.date = const Value.absent(),
    this.open = const Value.absent(),
    this.high = const Value.absent(),
    this.low = const Value.absent(),
    this.close = const Value.absent(),
    this.volume = const Value.absent(),
    this.adjClose = const Value.absent(),
  });
  CandlesCompanion.insert({
    this.id = const Value.absent(),
    required DateTime date,
    this.open = const Value.absent(),
    this.high = const Value.absent(),
    this.low = const Value.absent(),
    this.close = const Value.absent(),
    this.volume = const Value.absent(),
    this.adjClose = const Value.absent(),
  }) : date = Value(date);
  static Insertable<CandlesData> custom({
    Expression<int>? id,
    Expression<DateTime>? date,
    Expression<double>? open,
    Expression<double>? high,
    Expression<double>? low,
    Expression<double>? close,
    Expression<int>? volume,
    Expression<double>? adjClose,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (date != null) 'date': date,
      if (open != null) 'open': open,
      if (high != null) 'high': high,
      if (low != null) 'low': low,
      if (close != null) 'close': close,
      if (volume != null) 'volume': volume,
      if (adjClose != null) 'adj_close': adjClose,
    });
  }

  CandlesCompanion copyWith(
      {Value<int>? id,
      Value<DateTime>? date,
      Value<double>? open,
      Value<double>? high,
      Value<double>? low,
      Value<double>? close,
      Value<int>? volume,
      Value<double>? adjClose}) {
    return CandlesCompanion(
      id: id ?? this.id,
      date: date ?? this.date,
      open: open ?? this.open,
      high: high ?? this.high,
      low: low ?? this.low,
      close: close ?? this.close,
      volume: volume ?? this.volume,
      adjClose: adjClose ?? this.adjClose,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (open.present) {
      map['open'] = Variable<double>(open.value);
    }
    if (high.present) {
      map['high'] = Variable<double>(high.value);
    }
    if (low.present) {
      map['low'] = Variable<double>(low.value);
    }
    if (close.present) {
      map['close'] = Variable<double>(close.value);
    }
    if (volume.present) {
      map['volume'] = Variable<int>(volume.value);
    }
    if (adjClose.present) {
      map['adj_close'] = Variable<double>(adjClose.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CandlesCompanion(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('open: $open, ')
          ..write('high: $high, ')
          ..write('low: $low, ')
          ..write('close: $close, ')
          ..write('volume: $volume, ')
          ..write('adjClose: $adjClose')
          ..write(')'))
        .toString();
  }
}

class DatabaseAtV4 extends GeneratedDatabase {
  DatabaseAtV4(QueryExecutor e) : super(e);
  late final Tickers tickers = Tickers(this);
  late final Candles candles = Candles(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [tickers, candles];
  @override
  int get schemaVersion => 4;
}
