// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $TickersTable extends Tickers with TableInfo<$TickersTable, Ticker> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TickersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _symbolMeta = const VerificationMeta('symbol');
  @override
  late final GeneratedColumn<String> symbol = GeneratedColumn<String>(
      'symbol', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _changeMeta = const VerificationMeta('change');
  @override
  late final GeneratedColumn<double> change = GeneratedColumn<double>(
      'change', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
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
  VerificationContext validateIntegrity(Insertable<Ticker> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('symbol')) {
      context.handle(_symbolMeta,
          symbol.isAcceptableOrUnknown(data['symbol']!, _symbolMeta));
    } else if (isInserting) {
      context.missing(_symbolMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('change')) {
      context.handle(_changeMeta,
          change.isAcceptableOrUnknown(data['change']!, _changeMeta));
    } else if (isInserting) {
      context.missing(_changeMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('amount')) {
      context.handle(_amountMeta,
          amount.isAcceptableOrUnknown(data['amount']!, _amountMeta));
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Ticker map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Ticker(
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
  $TickersTable createAlias(String alias) {
    return $TickersTable(attachedDatabase, alias);
  }
}

class Ticker extends DataClass implements Insertable<Ticker> {
  final int id;
  final String symbol;
  final String name;
  final double change;
  final DateTime createdAt;
  final DateTime updatedAt;
  final double amount;
  const Ticker(
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

  factory Ticker.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Ticker(
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

  Ticker copyWith(
          {int? id,
          String? symbol,
          String? name,
          double? change,
          DateTime? createdAt,
          DateTime? updatedAt,
          double? amount}) =>
      Ticker(
        id: id ?? this.id,
        symbol: symbol ?? this.symbol,
        name: name ?? this.name,
        change: change ?? this.change,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        amount: amount ?? this.amount,
      );
  Ticker copyWithCompanion(TickersCompanion data) {
    return Ticker(
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
    return (StringBuffer('Ticker(')
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
      (other is Ticker &&
          other.id == this.id &&
          other.symbol == this.symbol &&
          other.name == this.name &&
          other.change == this.change &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.amount == this.amount);
}

class TickersCompanion extends UpdateCompanion<Ticker> {
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
  static Insertable<Ticker> custom({
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

class $CandlesTable extends Candles with TableInfo<$CandlesTable, Candle> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CandlesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
      'date', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _openMeta = const VerificationMeta('open');
  @override
  late final GeneratedColumn<double> open = GeneratedColumn<double>(
      'open', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(-1.0));
  static const VerificationMeta _highMeta = const VerificationMeta('high');
  @override
  late final GeneratedColumn<double> high = GeneratedColumn<double>(
      'high', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(-1.0));
  static const VerificationMeta _lowMeta = const VerificationMeta('low');
  @override
  late final GeneratedColumn<double> low = GeneratedColumn<double>(
      'low', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(-1.0));
  static const VerificationMeta _closeMeta = const VerificationMeta('close');
  @override
  late final GeneratedColumn<double> close = GeneratedColumn<double>(
      'close', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(-1.0));
  static const VerificationMeta _volumeMeta = const VerificationMeta('volume');
  @override
  late final GeneratedColumn<int> volume = GeneratedColumn<int>(
      'volume', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _adjCloseMeta =
      const VerificationMeta('adjClose');
  @override
  late final GeneratedColumn<double> adjClose = GeneratedColumn<double>(
      'adj_close', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(-1.0));
  @override
  List<GeneratedColumn> get $columns =>
      [id, date, open, high, low, close, volume, adjClose];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'candles';
  @override
  VerificationContext validateIntegrity(Insertable<Candle> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('date')) {
      context.handle(
          _dateMeta, date.isAcceptableOrUnknown(data['date']!, _dateMeta));
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('open')) {
      context.handle(
          _openMeta, open.isAcceptableOrUnknown(data['open']!, _openMeta));
    }
    if (data.containsKey('high')) {
      context.handle(
          _highMeta, high.isAcceptableOrUnknown(data['high']!, _highMeta));
    }
    if (data.containsKey('low')) {
      context.handle(
          _lowMeta, low.isAcceptableOrUnknown(data['low']!, _lowMeta));
    }
    if (data.containsKey('close')) {
      context.handle(
          _closeMeta, close.isAcceptableOrUnknown(data['close']!, _closeMeta));
    }
    if (data.containsKey('volume')) {
      context.handle(_volumeMeta,
          volume.isAcceptableOrUnknown(data['volume']!, _volumeMeta));
    }
    if (data.containsKey('adj_close')) {
      context.handle(_adjCloseMeta,
          adjClose.isAcceptableOrUnknown(data['adj_close']!, _adjCloseMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Candle map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Candle(
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
  $CandlesTable createAlias(String alias) {
    return $CandlesTable(attachedDatabase, alias);
  }
}

class Candle extends DataClass implements Insertable<Candle> {
  final int id;
  final DateTime date;
  final double open;
  final double high;
  final double low;
  final double close;
  final int volume;
  final double adjClose;
  const Candle(
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

  factory Candle.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Candle(
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

  Candle copyWith(
          {int? id,
          DateTime? date,
          double? open,
          double? high,
          double? low,
          double? close,
          int? volume,
          double? adjClose}) =>
      Candle(
        id: id ?? this.id,
        date: date ?? this.date,
        open: open ?? this.open,
        high: high ?? this.high,
        low: low ?? this.low,
        close: close ?? this.close,
        volume: volume ?? this.volume,
        adjClose: adjClose ?? this.adjClose,
      );
  Candle copyWithCompanion(CandlesCompanion data) {
    return Candle(
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
    return (StringBuffer('Candle(')
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
      (other is Candle &&
          other.id == this.id &&
          other.date == this.date &&
          other.open == this.open &&
          other.high == this.high &&
          other.low == this.low &&
          other.close == this.close &&
          other.volume == this.volume &&
          other.adjClose == this.adjClose);
}

class CandlesCompanion extends UpdateCompanion<Candle> {
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
  static Insertable<Candle> custom({
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

abstract class _$Database extends GeneratedDatabase {
  _$Database(QueryExecutor e) : super(e);
  $DatabaseManager get managers => $DatabaseManager(this);
  late final $TickersTable tickers = $TickersTable(this);
  late final $CandlesTable candles = $CandlesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [tickers, candles];
}

typedef $$TickersTableCreateCompanionBuilder = TickersCompanion Function({
  Value<int> id,
  required String symbol,
  required String name,
  required double change,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  required double amount,
});
typedef $$TickersTableUpdateCompanionBuilder = TickersCompanion Function({
  Value<int> id,
  Value<String> symbol,
  Value<String> name,
  Value<double> change,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<double> amount,
});

class $$TickersTableFilterComposer extends Composer<_$Database, $TickersTable> {
  $$TickersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get symbol => $composableBuilder(
      column: $table.symbol, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get change => $composableBuilder(
      column: $table.change, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnFilters(column));
}

class $$TickersTableOrderingComposer
    extends Composer<_$Database, $TickersTable> {
  $$TickersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get symbol => $composableBuilder(
      column: $table.symbol, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get change => $composableBuilder(
      column: $table.change, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnOrderings(column));
}

class $$TickersTableAnnotationComposer
    extends Composer<_$Database, $TickersTable> {
  $$TickersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get symbol =>
      $composableBuilder(column: $table.symbol, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<double> get change =>
      $composableBuilder(column: $table.change, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);
}

class $$TickersTableTableManager extends RootTableManager<
    _$Database,
    $TickersTable,
    Ticker,
    $$TickersTableFilterComposer,
    $$TickersTableOrderingComposer,
    $$TickersTableAnnotationComposer,
    $$TickersTableCreateCompanionBuilder,
    $$TickersTableUpdateCompanionBuilder,
    (Ticker, BaseReferences<_$Database, $TickersTable, Ticker>),
    Ticker,
    PrefetchHooks Function()> {
  $$TickersTableTableManager(_$Database db, $TickersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TickersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TickersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TickersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> symbol = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<double> change = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<double> amount = const Value.absent(),
          }) =>
              TickersCompanion(
            id: id,
            symbol: symbol,
            name: name,
            change: change,
            createdAt: createdAt,
            updatedAt: updatedAt,
            amount: amount,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String symbol,
            required String name,
            required double change,
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            required double amount,
          }) =>
              TickersCompanion.insert(
            id: id,
            symbol: symbol,
            name: name,
            change: change,
            createdAt: createdAt,
            updatedAt: updatedAt,
            amount: amount,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TickersTableProcessedTableManager = ProcessedTableManager<
    _$Database,
    $TickersTable,
    Ticker,
    $$TickersTableFilterComposer,
    $$TickersTableOrderingComposer,
    $$TickersTableAnnotationComposer,
    $$TickersTableCreateCompanionBuilder,
    $$TickersTableUpdateCompanionBuilder,
    (Ticker, BaseReferences<_$Database, $TickersTable, Ticker>),
    Ticker,
    PrefetchHooks Function()>;
typedef $$CandlesTableCreateCompanionBuilder = CandlesCompanion Function({
  Value<int> id,
  required DateTime date,
  Value<double> open,
  Value<double> high,
  Value<double> low,
  Value<double> close,
  Value<int> volume,
  Value<double> adjClose,
});
typedef $$CandlesTableUpdateCompanionBuilder = CandlesCompanion Function({
  Value<int> id,
  Value<DateTime> date,
  Value<double> open,
  Value<double> high,
  Value<double> low,
  Value<double> close,
  Value<int> volume,
  Value<double> adjClose,
});

class $$CandlesTableFilterComposer extends Composer<_$Database, $CandlesTable> {
  $$CandlesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get date => $composableBuilder(
      column: $table.date, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get open => $composableBuilder(
      column: $table.open, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get high => $composableBuilder(
      column: $table.high, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get low => $composableBuilder(
      column: $table.low, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get close => $composableBuilder(
      column: $table.close, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get volume => $composableBuilder(
      column: $table.volume, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get adjClose => $composableBuilder(
      column: $table.adjClose, builder: (column) => ColumnFilters(column));
}

class $$CandlesTableOrderingComposer
    extends Composer<_$Database, $CandlesTable> {
  $$CandlesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get date => $composableBuilder(
      column: $table.date, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get open => $composableBuilder(
      column: $table.open, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get high => $composableBuilder(
      column: $table.high, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get low => $composableBuilder(
      column: $table.low, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get close => $composableBuilder(
      column: $table.close, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get volume => $composableBuilder(
      column: $table.volume, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get adjClose => $composableBuilder(
      column: $table.adjClose, builder: (column) => ColumnOrderings(column));
}

class $$CandlesTableAnnotationComposer
    extends Composer<_$Database, $CandlesTable> {
  $$CandlesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<double> get open =>
      $composableBuilder(column: $table.open, builder: (column) => column);

  GeneratedColumn<double> get high =>
      $composableBuilder(column: $table.high, builder: (column) => column);

  GeneratedColumn<double> get low =>
      $composableBuilder(column: $table.low, builder: (column) => column);

  GeneratedColumn<double> get close =>
      $composableBuilder(column: $table.close, builder: (column) => column);

  GeneratedColumn<int> get volume =>
      $composableBuilder(column: $table.volume, builder: (column) => column);

  GeneratedColumn<double> get adjClose =>
      $composableBuilder(column: $table.adjClose, builder: (column) => column);
}

class $$CandlesTableTableManager extends RootTableManager<
    _$Database,
    $CandlesTable,
    Candle,
    $$CandlesTableFilterComposer,
    $$CandlesTableOrderingComposer,
    $$CandlesTableAnnotationComposer,
    $$CandlesTableCreateCompanionBuilder,
    $$CandlesTableUpdateCompanionBuilder,
    (Candle, BaseReferences<_$Database, $CandlesTable, Candle>),
    Candle,
    PrefetchHooks Function()> {
  $$CandlesTableTableManager(_$Database db, $CandlesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CandlesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CandlesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CandlesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<DateTime> date = const Value.absent(),
            Value<double> open = const Value.absent(),
            Value<double> high = const Value.absent(),
            Value<double> low = const Value.absent(),
            Value<double> close = const Value.absent(),
            Value<int> volume = const Value.absent(),
            Value<double> adjClose = const Value.absent(),
          }) =>
              CandlesCompanion(
            id: id,
            date: date,
            open: open,
            high: high,
            low: low,
            close: close,
            volume: volume,
            adjClose: adjClose,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required DateTime date,
            Value<double> open = const Value.absent(),
            Value<double> high = const Value.absent(),
            Value<double> low = const Value.absent(),
            Value<double> close = const Value.absent(),
            Value<int> volume = const Value.absent(),
            Value<double> adjClose = const Value.absent(),
          }) =>
              CandlesCompanion.insert(
            id: id,
            date: date,
            open: open,
            high: high,
            low: low,
            close: close,
            volume: volume,
            adjClose: adjClose,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CandlesTableProcessedTableManager = ProcessedTableManager<
    _$Database,
    $CandlesTable,
    Candle,
    $$CandlesTableFilterComposer,
    $$CandlesTableOrderingComposer,
    $$CandlesTableAnnotationComposer,
    $$CandlesTableCreateCompanionBuilder,
    $$CandlesTableUpdateCompanionBuilder,
    (Candle, BaseReferences<_$Database, $CandlesTable, Candle>),
    Candle,
    PrefetchHooks Function()>;

class $DatabaseManager {
  final _$Database _db;
  $DatabaseManager(this._db);
  $$TickersTableTableManager get tickers =>
      $$TickersTableTableManager(_db, _db.tickers);
  $$CandlesTableTableManager get candles =>
      $$CandlesTableTableManager(_db, _db.candles);
}
