// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
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
  static const VerificationMeta _symbolMeta = const VerificationMeta('symbol');
  @override
  late final GeneratedColumn<String> symbol = GeneratedColumn<String>(
      'symbol', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
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
      [id, symbol, date, open, high, low, close, volume, adjClose];
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
    if (data.containsKey('symbol')) {
      context.handle(_symbolMeta,
          symbol.isAcceptableOrUnknown(data['symbol']!, _symbolMeta));
    } else if (isInserting) {
      context.missing(_symbolMeta);
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
      symbol: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}symbol'])!,
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
  final String symbol;
  final DateTime date;
  final double open;
  final double high;
  final double low;
  final double close;
  final int volume;
  final double adjClose;
  const Candle(
      {required this.id,
      required this.symbol,
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
    map['symbol'] = Variable<String>(symbol);
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
      symbol: Value(symbol),
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
      symbol: serializer.fromJson<String>(json['symbol']),
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
      'symbol': serializer.toJson<String>(symbol),
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
          String? symbol,
          DateTime? date,
          double? open,
          double? high,
          double? low,
          double? close,
          int? volume,
          double? adjClose}) =>
      Candle(
        id: id ?? this.id,
        symbol: symbol ?? this.symbol,
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
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
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
          ..write('symbol: $symbol, ')
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
      Object.hash(id, symbol, date, open, high, low, close, volume, adjClose);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Candle &&
          other.id == this.id &&
          other.symbol == this.symbol &&
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
  final Value<String> symbol;
  final Value<DateTime> date;
  final Value<double> open;
  final Value<double> high;
  final Value<double> low;
  final Value<double> close;
  final Value<int> volume;
  final Value<double> adjClose;
  const CandlesCompanion({
    this.id = const Value.absent(),
    this.symbol = const Value.absent(),
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
    required String symbol,
    required DateTime date,
    this.open = const Value.absent(),
    this.high = const Value.absent(),
    this.low = const Value.absent(),
    this.close = const Value.absent(),
    this.volume = const Value.absent(),
    this.adjClose = const Value.absent(),
  })  : symbol = Value(symbol),
        date = Value(date);
  static Insertable<Candle> custom({
    Expression<int>? id,
    Expression<String>? symbol,
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
      if (symbol != null) 'symbol': symbol,
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
      Value<String>? symbol,
      Value<DateTime>? date,
      Value<double>? open,
      Value<double>? high,
      Value<double>? low,
      Value<double>? close,
      Value<int>? volume,
      Value<double>? adjClose}) {
    return CandlesCompanion(
      id: id ?? this.id,
      symbol: symbol ?? this.symbol,
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
    if (symbol.present) {
      map['symbol'] = Variable<String>(symbol.value);
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
          ..write('symbol: $symbol, ')
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

class $TradesTable extends Trades with TableInfo<$TradesTable, Trade> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TradesTable(this.attachedDatabase, [this._alias]);
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
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _quantityMeta =
      const VerificationMeta('quantity');
  @override
  late final GeneratedColumn<double> quantity = GeneratedColumn<double>(
      'quantity', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _priceMeta = const VerificationMeta('price');
  @override
  late final GeneratedColumn<double> price = GeneratedColumn<double>(
      'price', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _tradeTypeMeta =
      const VerificationMeta('tradeType');
  @override
  late final GeneratedColumn<String> tradeType = GeneratedColumn<String>(
      'trade_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _tradeDateMeta =
      const VerificationMeta('tradeDate');
  @override
  late final GeneratedColumn<DateTime> tradeDate = GeneratedColumn<DateTime>(
      'trade_date', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _realizedPLMeta =
      const VerificationMeta('realizedPL');
  @override
  late final GeneratedColumn<double> realizedPL = GeneratedColumn<double>(
      'realized_p_l', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0.0));
  static const VerificationMeta _commissionMeta =
      const VerificationMeta('commission');
  @override
  late final GeneratedColumn<double> commission = GeneratedColumn<double>(
      'commission', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0.0));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        symbol,
        name,
        quantity,
        price,
        tradeType,
        tradeDate,
        realizedPL,
        commission
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'trades';
  @override
  VerificationContext validateIntegrity(Insertable<Trade> instance,
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
    if (data.containsKey('quantity')) {
      context.handle(_quantityMeta,
          quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta));
    } else if (isInserting) {
      context.missing(_quantityMeta);
    }
    if (data.containsKey('price')) {
      context.handle(
          _priceMeta, price.isAcceptableOrUnknown(data['price']!, _priceMeta));
    } else if (isInserting) {
      context.missing(_priceMeta);
    }
    if (data.containsKey('trade_type')) {
      context.handle(_tradeTypeMeta,
          tradeType.isAcceptableOrUnknown(data['trade_type']!, _tradeTypeMeta));
    } else if (isInserting) {
      context.missing(_tradeTypeMeta);
    }
    if (data.containsKey('trade_date')) {
      context.handle(_tradeDateMeta,
          tradeDate.isAcceptableOrUnknown(data['trade_date']!, _tradeDateMeta));
    } else if (isInserting) {
      context.missing(_tradeDateMeta);
    }
    if (data.containsKey('realized_p_l')) {
      context.handle(
          _realizedPLMeta,
          realizedPL.isAcceptableOrUnknown(
              data['realized_p_l']!, _realizedPLMeta));
    }
    if (data.containsKey('commission')) {
      context.handle(
          _commissionMeta,
          commission.isAcceptableOrUnknown(
              data['commission']!, _commissionMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Trade map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Trade(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      symbol: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}symbol'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      quantity: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}quantity'])!,
      price: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}price'])!,
      tradeType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}trade_type'])!,
      tradeDate: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}trade_date'])!,
      realizedPL: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}realized_p_l'])!,
      commission: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}commission'])!,
    );
  }

  @override
  $TradesTable createAlias(String alias) {
    return $TradesTable(attachedDatabase, alias);
  }
}

class Trade extends DataClass implements Insertable<Trade> {
  final int id;
  final String symbol;
  final String name;
  final double quantity;
  final double price;
  final String tradeType;
  final DateTime tradeDate;
  final double realizedPL;
  final double commission;
  const Trade(
      {required this.id,
      required this.symbol,
      required this.name,
      required this.quantity,
      required this.price,
      required this.tradeType,
      required this.tradeDate,
      required this.realizedPL,
      required this.commission});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['symbol'] = Variable<String>(symbol);
    map['name'] = Variable<String>(name);
    map['quantity'] = Variable<double>(quantity);
    map['price'] = Variable<double>(price);
    map['trade_type'] = Variable<String>(tradeType);
    map['trade_date'] = Variable<DateTime>(tradeDate);
    map['realized_p_l'] = Variable<double>(realizedPL);
    map['commission'] = Variable<double>(commission);
    return map;
  }

  TradesCompanion toCompanion(bool nullToAbsent) {
    return TradesCompanion(
      id: Value(id),
      symbol: Value(symbol),
      name: Value(name),
      quantity: Value(quantity),
      price: Value(price),
      tradeType: Value(tradeType),
      tradeDate: Value(tradeDate),
      realizedPL: Value(realizedPL),
      commission: Value(commission),
    );
  }

  factory Trade.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Trade(
      id: serializer.fromJson<int>(json['id']),
      symbol: serializer.fromJson<String>(json['symbol']),
      name: serializer.fromJson<String>(json['name']),
      quantity: serializer.fromJson<double>(json['quantity']),
      price: serializer.fromJson<double>(json['price']),
      tradeType: serializer.fromJson<String>(json['tradeType']),
      tradeDate: serializer.fromJson<DateTime>(json['tradeDate']),
      realizedPL: serializer.fromJson<double>(json['realizedPL']),
      commission: serializer.fromJson<double>(json['commission']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'symbol': serializer.toJson<String>(symbol),
      'name': serializer.toJson<String>(name),
      'quantity': serializer.toJson<double>(quantity),
      'price': serializer.toJson<double>(price),
      'tradeType': serializer.toJson<String>(tradeType),
      'tradeDate': serializer.toJson<DateTime>(tradeDate),
      'realizedPL': serializer.toJson<double>(realizedPL),
      'commission': serializer.toJson<double>(commission),
    };
  }

  Trade copyWith(
          {int? id,
          String? symbol,
          String? name,
          double? quantity,
          double? price,
          String? tradeType,
          DateTime? tradeDate,
          double? realizedPL,
          double? commission}) =>
      Trade(
        id: id ?? this.id,
        symbol: symbol ?? this.symbol,
        name: name ?? this.name,
        quantity: quantity ?? this.quantity,
        price: price ?? this.price,
        tradeType: tradeType ?? this.tradeType,
        tradeDate: tradeDate ?? this.tradeDate,
        realizedPL: realizedPL ?? this.realizedPL,
        commission: commission ?? this.commission,
      );
  Trade copyWithCompanion(TradesCompanion data) {
    return Trade(
      id: data.id.present ? data.id.value : this.id,
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      name: data.name.present ? data.name.value : this.name,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      price: data.price.present ? data.price.value : this.price,
      tradeType: data.tradeType.present ? data.tradeType.value : this.tradeType,
      tradeDate: data.tradeDate.present ? data.tradeDate.value : this.tradeDate,
      realizedPL:
          data.realizedPL.present ? data.realizedPL.value : this.realizedPL,
      commission:
          data.commission.present ? data.commission.value : this.commission,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Trade(')
          ..write('id: $id, ')
          ..write('symbol: $symbol, ')
          ..write('name: $name, ')
          ..write('quantity: $quantity, ')
          ..write('price: $price, ')
          ..write('tradeType: $tradeType, ')
          ..write('tradeDate: $tradeDate, ')
          ..write('realizedPL: $realizedPL, ')
          ..write('commission: $commission')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, symbol, name, quantity, price, tradeType,
      tradeDate, realizedPL, commission);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Trade &&
          other.id == this.id &&
          other.symbol == this.symbol &&
          other.name == this.name &&
          other.quantity == this.quantity &&
          other.price == this.price &&
          other.tradeType == this.tradeType &&
          other.tradeDate == this.tradeDate &&
          other.realizedPL == this.realizedPL &&
          other.commission == this.commission);
}

class TradesCompanion extends UpdateCompanion<Trade> {
  final Value<int> id;
  final Value<String> symbol;
  final Value<String> name;
  final Value<double> quantity;
  final Value<double> price;
  final Value<String> tradeType;
  final Value<DateTime> tradeDate;
  final Value<double> realizedPL;
  final Value<double> commission;
  const TradesCompanion({
    this.id = const Value.absent(),
    this.symbol = const Value.absent(),
    this.name = const Value.absent(),
    this.quantity = const Value.absent(),
    this.price = const Value.absent(),
    this.tradeType = const Value.absent(),
    this.tradeDate = const Value.absent(),
    this.realizedPL = const Value.absent(),
    this.commission = const Value.absent(),
  });
  TradesCompanion.insert({
    this.id = const Value.absent(),
    required String symbol,
    required String name,
    required double quantity,
    required double price,
    required String tradeType,
    required DateTime tradeDate,
    this.realizedPL = const Value.absent(),
    this.commission = const Value.absent(),
  })  : symbol = Value(symbol),
        name = Value(name),
        quantity = Value(quantity),
        price = Value(price),
        tradeType = Value(tradeType),
        tradeDate = Value(tradeDate);
  static Insertable<Trade> custom({
    Expression<int>? id,
    Expression<String>? symbol,
    Expression<String>? name,
    Expression<double>? quantity,
    Expression<double>? price,
    Expression<String>? tradeType,
    Expression<DateTime>? tradeDate,
    Expression<double>? realizedPL,
    Expression<double>? commission,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (symbol != null) 'symbol': symbol,
      if (name != null) 'name': name,
      if (quantity != null) 'quantity': quantity,
      if (price != null) 'price': price,
      if (tradeType != null) 'trade_type': tradeType,
      if (tradeDate != null) 'trade_date': tradeDate,
      if (realizedPL != null) 'realized_p_l': realizedPL,
      if (commission != null) 'commission': commission,
    });
  }

  TradesCompanion copyWith(
      {Value<int>? id,
      Value<String>? symbol,
      Value<String>? name,
      Value<double>? quantity,
      Value<double>? price,
      Value<String>? tradeType,
      Value<DateTime>? tradeDate,
      Value<double>? realizedPL,
      Value<double>? commission}) {
    return TradesCompanion(
      id: id ?? this.id,
      symbol: symbol ?? this.symbol,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      tradeType: tradeType ?? this.tradeType,
      tradeDate: tradeDate ?? this.tradeDate,
      realizedPL: realizedPL ?? this.realizedPL,
      commission: commission ?? this.commission,
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
    if (quantity.present) {
      map['quantity'] = Variable<double>(quantity.value);
    }
    if (price.present) {
      map['price'] = Variable<double>(price.value);
    }
    if (tradeType.present) {
      map['trade_type'] = Variable<String>(tradeType.value);
    }
    if (tradeDate.present) {
      map['trade_date'] = Variable<DateTime>(tradeDate.value);
    }
    if (realizedPL.present) {
      map['realized_p_l'] = Variable<double>(realizedPL.value);
    }
    if (commission.present) {
      map['commission'] = Variable<double>(commission.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TradesCompanion(')
          ..write('id: $id, ')
          ..write('symbol: $symbol, ')
          ..write('name: $name, ')
          ..write('quantity: $quantity, ')
          ..write('price: $price, ')
          ..write('tradeType: $tradeType, ')
          ..write('tradeDate: $tradeDate, ')
          ..write('realizedPL: $realizedPL, ')
          ..write('commission: $commission')
          ..write(')'))
        .toString();
  }
}

class $IbkrProfileSettingsTable extends IbkrProfileSettings
    with TableInfo<$IbkrProfileSettingsTable, IbkrProfileSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $IbkrProfileSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _enabledMeta =
      const VerificationMeta('enabled');
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
      'enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("enabled" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _baseUrlMeta =
      const VerificationMeta('baseUrl');
  @override
  late final GeneratedColumn<String> baseUrl = GeneratedColumn<String>(
      'base_url', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _tokenMeta = const VerificationMeta('token');
  @override
  late final GeneratedColumn<String> token = GeneratedColumn<String>(
      'token', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  @override
  List<GeneratedColumn> get $columns => [id, enabled, baseUrl, token];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ibkr_profile_settings';
  @override
  VerificationContext validateIntegrity(Insertable<IbkrProfileSetting> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('enabled')) {
      context.handle(_enabledMeta,
          enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta));
    }
    if (data.containsKey('base_url')) {
      context.handle(_baseUrlMeta,
          baseUrl.isAcceptableOrUnknown(data['base_url']!, _baseUrlMeta));
    }
    if (data.containsKey('token')) {
      context.handle(
          _tokenMeta, token.isAcceptableOrUnknown(data['token']!, _tokenMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  IbkrProfileSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return IbkrProfileSetting(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      enabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}enabled'])!,
      baseUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}base_url'])!,
      token: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}token'])!,
    );
  }

  @override
  $IbkrProfileSettingsTable createAlias(String alias) {
    return $IbkrProfileSettingsTable(attachedDatabase, alias);
  }
}

class IbkrProfileSetting extends DataClass
    implements Insertable<IbkrProfileSetting> {
  final int id;
  final bool enabled;
  final String baseUrl;
  final String token;
  const IbkrProfileSetting(
      {required this.id,
      required this.enabled,
      required this.baseUrl,
      required this.token});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['enabled'] = Variable<bool>(enabled);
    map['base_url'] = Variable<String>(baseUrl);
    map['token'] = Variable<String>(token);
    return map;
  }

  IbkrProfileSettingsCompanion toCompanion(bool nullToAbsent) {
    return IbkrProfileSettingsCompanion(
      id: Value(id),
      enabled: Value(enabled),
      baseUrl: Value(baseUrl),
      token: Value(token),
    );
  }

  factory IbkrProfileSetting.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return IbkrProfileSetting(
      id: serializer.fromJson<int>(json['id']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      baseUrl: serializer.fromJson<String>(json['baseUrl']),
      token: serializer.fromJson<String>(json['token']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'enabled': serializer.toJson<bool>(enabled),
      'baseUrl': serializer.toJson<String>(baseUrl),
      'token': serializer.toJson<String>(token),
    };
  }

  IbkrProfileSetting copyWith(
          {int? id, bool? enabled, String? baseUrl, String? token}) =>
      IbkrProfileSetting(
        id: id ?? this.id,
        enabled: enabled ?? this.enabled,
        baseUrl: baseUrl ?? this.baseUrl,
        token: token ?? this.token,
      );
  IbkrProfileSetting copyWithCompanion(IbkrProfileSettingsCompanion data) {
    return IbkrProfileSetting(
      id: data.id.present ? data.id.value : this.id,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      baseUrl: data.baseUrl.present ? data.baseUrl.value : this.baseUrl,
      token: data.token.present ? data.token.value : this.token,
    );
  }

  @override
  String toString() {
    return (StringBuffer('IbkrProfileSetting(')
          ..write('id: $id, ')
          ..write('enabled: $enabled, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('token: $token')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, enabled, baseUrl, token);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is IbkrProfileSetting &&
          other.id == this.id &&
          other.enabled == this.enabled &&
          other.baseUrl == this.baseUrl &&
          other.token == this.token);
}

class IbkrProfileSettingsCompanion extends UpdateCompanion<IbkrProfileSetting> {
  final Value<int> id;
  final Value<bool> enabled;
  final Value<String> baseUrl;
  final Value<String> token;
  const IbkrProfileSettingsCompanion({
    this.id = const Value.absent(),
    this.enabled = const Value.absent(),
    this.baseUrl = const Value.absent(),
    this.token = const Value.absent(),
  });
  IbkrProfileSettingsCompanion.insert({
    this.id = const Value.absent(),
    this.enabled = const Value.absent(),
    this.baseUrl = const Value.absent(),
    this.token = const Value.absent(),
  });
  static Insertable<IbkrProfileSetting> custom({
    Expression<int>? id,
    Expression<bool>? enabled,
    Expression<String>? baseUrl,
    Expression<String>? token,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (enabled != null) 'enabled': enabled,
      if (baseUrl != null) 'base_url': baseUrl,
      if (token != null) 'token': token,
    });
  }

  IbkrProfileSettingsCompanion copyWith(
      {Value<int>? id,
      Value<bool>? enabled,
      Value<String>? baseUrl,
      Value<String>? token}) {
    return IbkrProfileSettingsCompanion(
      id: id ?? this.id,
      enabled: enabled ?? this.enabled,
      baseUrl: baseUrl ?? this.baseUrl,
      token: token ?? this.token,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (baseUrl.present) {
      map['base_url'] = Variable<String>(baseUrl.value);
    }
    if (token.present) {
      map['token'] = Variable<String>(token.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('IbkrProfileSettingsCompanion(')
          ..write('id: $id, ')
          ..write('enabled: $enabled, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('token: $token')
          ..write(')'))
        .toString();
  }
}

class $IbkrCacheEntriesTable extends IbkrCacheEntries
    with TableInfo<$IbkrCacheEntriesTable, IbkrCacheEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $IbkrCacheEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
      'kind', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _cacheKeyMeta =
      const VerificationMeta('cacheKey');
  @override
  late final GeneratedColumn<String> cacheKey = GeneratedColumn<String>(
      'cache_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadJsonMeta =
      const VerificationMeta('payloadJson');
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
      'payload_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _cachedAtMeta =
      const VerificationMeta('cachedAt');
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
      'cached_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [kind, cacheKey, payloadJson, cachedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ibkr_cache_entries';
  @override
  VerificationContext validateIntegrity(Insertable<IbkrCacheEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('kind')) {
      context.handle(
          _kindMeta, kind.isAcceptableOrUnknown(data['kind']!, _kindMeta));
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('cache_key')) {
      context.handle(_cacheKeyMeta,
          cacheKey.isAcceptableOrUnknown(data['cache_key']!, _cacheKeyMeta));
    } else if (isInserting) {
      context.missing(_cacheKeyMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
          _payloadJsonMeta,
          payloadJson.isAcceptableOrUnknown(
              data['payload_json']!, _payloadJsonMeta));
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(_cachedAtMeta,
          cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta));
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {kind, cacheKey};
  @override
  IbkrCacheEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return IbkrCacheEntry(
      kind: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kind'])!,
      cacheKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cache_key'])!,
      payloadJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload_json'])!,
      cachedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}cached_at'])!,
    );
  }

  @override
  $IbkrCacheEntriesTable createAlias(String alias) {
    return $IbkrCacheEntriesTable(attachedDatabase, alias);
  }
}

class IbkrCacheEntry extends DataClass implements Insertable<IbkrCacheEntry> {
  final String kind;
  final String cacheKey;
  final String payloadJson;
  final DateTime cachedAt;
  const IbkrCacheEntry(
      {required this.kind,
      required this.cacheKey,
      required this.payloadJson,
      required this.cachedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['kind'] = Variable<String>(kind);
    map['cache_key'] = Variable<String>(cacheKey);
    map['payload_json'] = Variable<String>(payloadJson);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  IbkrCacheEntriesCompanion toCompanion(bool nullToAbsent) {
    return IbkrCacheEntriesCompanion(
      kind: Value(kind),
      cacheKey: Value(cacheKey),
      payloadJson: Value(payloadJson),
      cachedAt: Value(cachedAt),
    );
  }

  factory IbkrCacheEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return IbkrCacheEntry(
      kind: serializer.fromJson<String>(json['kind']),
      cacheKey: serializer.fromJson<String>(json['cacheKey']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'kind': serializer.toJson<String>(kind),
      'cacheKey': serializer.toJson<String>(cacheKey),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  IbkrCacheEntry copyWith(
          {String? kind,
          String? cacheKey,
          String? payloadJson,
          DateTime? cachedAt}) =>
      IbkrCacheEntry(
        kind: kind ?? this.kind,
        cacheKey: cacheKey ?? this.cacheKey,
        payloadJson: payloadJson ?? this.payloadJson,
        cachedAt: cachedAt ?? this.cachedAt,
      );
  IbkrCacheEntry copyWithCompanion(IbkrCacheEntriesCompanion data) {
    return IbkrCacheEntry(
      kind: data.kind.present ? data.kind.value : this.kind,
      cacheKey: data.cacheKey.present ? data.cacheKey.value : this.cacheKey,
      payloadJson:
          data.payloadJson.present ? data.payloadJson.value : this.payloadJson,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('IbkrCacheEntry(')
          ..write('kind: $kind, ')
          ..write('cacheKey: $cacheKey, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(kind, cacheKey, payloadJson, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is IbkrCacheEntry &&
          other.kind == this.kind &&
          other.cacheKey == this.cacheKey &&
          other.payloadJson == this.payloadJson &&
          other.cachedAt == this.cachedAt);
}

class IbkrCacheEntriesCompanion extends UpdateCompanion<IbkrCacheEntry> {
  final Value<String> kind;
  final Value<String> cacheKey;
  final Value<String> payloadJson;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const IbkrCacheEntriesCompanion({
    this.kind = const Value.absent(),
    this.cacheKey = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  IbkrCacheEntriesCompanion.insert({
    required String kind,
    required String cacheKey,
    required String payloadJson,
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  })  : kind = Value(kind),
        cacheKey = Value(cacheKey),
        payloadJson = Value(payloadJson),
        cachedAt = Value(cachedAt);
  static Insertable<IbkrCacheEntry> custom({
    Expression<String>? kind,
    Expression<String>? cacheKey,
    Expression<String>? payloadJson,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (kind != null) 'kind': kind,
      if (cacheKey != null) 'cache_key': cacheKey,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  IbkrCacheEntriesCompanion copyWith(
      {Value<String>? kind,
      Value<String>? cacheKey,
      Value<String>? payloadJson,
      Value<DateTime>? cachedAt,
      Value<int>? rowid}) {
    return IbkrCacheEntriesCompanion(
      kind: kind ?? this.kind,
      cacheKey: cacheKey ?? this.cacheKey,
      payloadJson: payloadJson ?? this.payloadJson,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (cacheKey.present) {
      map['cache_key'] = Variable<String>(cacheKey.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('IbkrCacheEntriesCompanion(')
          ..write('kind: $kind, ')
          ..write('cacheKey: $cacheKey, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$Database extends GeneratedDatabase {
  _$Database(QueryExecutor e) : super(e);
  $DatabaseManager get managers => $DatabaseManager(this);
  late final $CandlesTable candles = $CandlesTable(this);
  late final $TradesTable trades = $TradesTable(this);
  late final $IbkrProfileSettingsTable ibkrProfileSettings =
      $IbkrProfileSettingsTable(this);
  late final $IbkrCacheEntriesTable ibkrCacheEntries =
      $IbkrCacheEntriesTable(this);
  late final Index idxCandlesSymbolDate = Index('idx_candles_symbol_date',
      'CREATE UNIQUE INDEX idx_candles_symbol_date ON candles (symbol, date)');
  late final Index idxTradesSymbolTradeDate = Index(
      'idx_trades_symbol_trade_date',
      'CREATE INDEX idx_trades_symbol_trade_date ON trades (symbol, trade_date)');
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        candles,
        trades,
        ibkrProfileSettings,
        ibkrCacheEntries,
        idxCandlesSymbolDate,
        idxTradesSymbolTradeDate
      ];
}

typedef $$CandlesTableCreateCompanionBuilder = CandlesCompanion Function({
  Value<int> id,
  required String symbol,
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
  Value<String> symbol,
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

  ColumnFilters<String> get symbol => $composableBuilder(
      column: $table.symbol, builder: (column) => ColumnFilters(column));

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

  ColumnOrderings<String> get symbol => $composableBuilder(
      column: $table.symbol, builder: (column) => ColumnOrderings(column));

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

  GeneratedColumn<String> get symbol =>
      $composableBuilder(column: $table.symbol, builder: (column) => column);

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
            Value<String> symbol = const Value.absent(),
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
            symbol: symbol,
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
            required String symbol,
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
            symbol: symbol,
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
typedef $$TradesTableCreateCompanionBuilder = TradesCompanion Function({
  Value<int> id,
  required String symbol,
  required String name,
  required double quantity,
  required double price,
  required String tradeType,
  required DateTime tradeDate,
  Value<double> realizedPL,
  Value<double> commission,
});
typedef $$TradesTableUpdateCompanionBuilder = TradesCompanion Function({
  Value<int> id,
  Value<String> symbol,
  Value<String> name,
  Value<double> quantity,
  Value<double> price,
  Value<String> tradeType,
  Value<DateTime> tradeDate,
  Value<double> realizedPL,
  Value<double> commission,
});

class $$TradesTableFilterComposer extends Composer<_$Database, $TradesTable> {
  $$TradesTableFilterComposer({
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

  ColumnFilters<double> get quantity => $composableBuilder(
      column: $table.quantity, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get price => $composableBuilder(
      column: $table.price, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tradeType => $composableBuilder(
      column: $table.tradeType, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get tradeDate => $composableBuilder(
      column: $table.tradeDate, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get realizedPL => $composableBuilder(
      column: $table.realizedPL, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get commission => $composableBuilder(
      column: $table.commission, builder: (column) => ColumnFilters(column));
}

class $$TradesTableOrderingComposer extends Composer<_$Database, $TradesTable> {
  $$TradesTableOrderingComposer({
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

  ColumnOrderings<double> get quantity => $composableBuilder(
      column: $table.quantity, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get price => $composableBuilder(
      column: $table.price, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tradeType => $composableBuilder(
      column: $table.tradeType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get tradeDate => $composableBuilder(
      column: $table.tradeDate, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get realizedPL => $composableBuilder(
      column: $table.realizedPL, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get commission => $composableBuilder(
      column: $table.commission, builder: (column) => ColumnOrderings(column));
}

class $$TradesTableAnnotationComposer
    extends Composer<_$Database, $TradesTable> {
  $$TradesTableAnnotationComposer({
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

  GeneratedColumn<double> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumn<double> get price =>
      $composableBuilder(column: $table.price, builder: (column) => column);

  GeneratedColumn<String> get tradeType =>
      $composableBuilder(column: $table.tradeType, builder: (column) => column);

  GeneratedColumn<DateTime> get tradeDate =>
      $composableBuilder(column: $table.tradeDate, builder: (column) => column);

  GeneratedColumn<double> get realizedPL => $composableBuilder(
      column: $table.realizedPL, builder: (column) => column);

  GeneratedColumn<double> get commission => $composableBuilder(
      column: $table.commission, builder: (column) => column);
}

class $$TradesTableTableManager extends RootTableManager<
    _$Database,
    $TradesTable,
    Trade,
    $$TradesTableFilterComposer,
    $$TradesTableOrderingComposer,
    $$TradesTableAnnotationComposer,
    $$TradesTableCreateCompanionBuilder,
    $$TradesTableUpdateCompanionBuilder,
    (Trade, BaseReferences<_$Database, $TradesTable, Trade>),
    Trade,
    PrefetchHooks Function()> {
  $$TradesTableTableManager(_$Database db, $TradesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TradesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TradesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TradesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> symbol = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<double> quantity = const Value.absent(),
            Value<double> price = const Value.absent(),
            Value<String> tradeType = const Value.absent(),
            Value<DateTime> tradeDate = const Value.absent(),
            Value<double> realizedPL = const Value.absent(),
            Value<double> commission = const Value.absent(),
          }) =>
              TradesCompanion(
            id: id,
            symbol: symbol,
            name: name,
            quantity: quantity,
            price: price,
            tradeType: tradeType,
            tradeDate: tradeDate,
            realizedPL: realizedPL,
            commission: commission,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String symbol,
            required String name,
            required double quantity,
            required double price,
            required String tradeType,
            required DateTime tradeDate,
            Value<double> realizedPL = const Value.absent(),
            Value<double> commission = const Value.absent(),
          }) =>
              TradesCompanion.insert(
            id: id,
            symbol: symbol,
            name: name,
            quantity: quantity,
            price: price,
            tradeType: tradeType,
            tradeDate: tradeDate,
            realizedPL: realizedPL,
            commission: commission,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TradesTableProcessedTableManager = ProcessedTableManager<
    _$Database,
    $TradesTable,
    Trade,
    $$TradesTableFilterComposer,
    $$TradesTableOrderingComposer,
    $$TradesTableAnnotationComposer,
    $$TradesTableCreateCompanionBuilder,
    $$TradesTableUpdateCompanionBuilder,
    (Trade, BaseReferences<_$Database, $TradesTable, Trade>),
    Trade,
    PrefetchHooks Function()>;
typedef $$IbkrProfileSettingsTableCreateCompanionBuilder
    = IbkrProfileSettingsCompanion Function({
  Value<int> id,
  Value<bool> enabled,
  Value<String> baseUrl,
  Value<String> token,
});
typedef $$IbkrProfileSettingsTableUpdateCompanionBuilder
    = IbkrProfileSettingsCompanion Function({
  Value<int> id,
  Value<bool> enabled,
  Value<String> baseUrl,
  Value<String> token,
});

class $$IbkrProfileSettingsTableFilterComposer
    extends Composer<_$Database, $IbkrProfileSettingsTable> {
  $$IbkrProfileSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get baseUrl => $composableBuilder(
      column: $table.baseUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get token => $composableBuilder(
      column: $table.token, builder: (column) => ColumnFilters(column));
}

class $$IbkrProfileSettingsTableOrderingComposer
    extends Composer<_$Database, $IbkrProfileSettingsTable> {
  $$IbkrProfileSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get baseUrl => $composableBuilder(
      column: $table.baseUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get token => $composableBuilder(
      column: $table.token, builder: (column) => ColumnOrderings(column));
}

class $$IbkrProfileSettingsTableAnnotationComposer
    extends Composer<_$Database, $IbkrProfileSettingsTable> {
  $$IbkrProfileSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<String> get baseUrl =>
      $composableBuilder(column: $table.baseUrl, builder: (column) => column);

  GeneratedColumn<String> get token =>
      $composableBuilder(column: $table.token, builder: (column) => column);
}

class $$IbkrProfileSettingsTableTableManager extends RootTableManager<
    _$Database,
    $IbkrProfileSettingsTable,
    IbkrProfileSetting,
    $$IbkrProfileSettingsTableFilterComposer,
    $$IbkrProfileSettingsTableOrderingComposer,
    $$IbkrProfileSettingsTableAnnotationComposer,
    $$IbkrProfileSettingsTableCreateCompanionBuilder,
    $$IbkrProfileSettingsTableUpdateCompanionBuilder,
    (
      IbkrProfileSetting,
      BaseReferences<_$Database, $IbkrProfileSettingsTable, IbkrProfileSetting>
    ),
    IbkrProfileSetting,
    PrefetchHooks Function()> {
  $$IbkrProfileSettingsTableTableManager(
      _$Database db, $IbkrProfileSettingsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$IbkrProfileSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$IbkrProfileSettingsTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$IbkrProfileSettingsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            Value<String> baseUrl = const Value.absent(),
            Value<String> token = const Value.absent(),
          }) =>
              IbkrProfileSettingsCompanion(
            id: id,
            enabled: enabled,
            baseUrl: baseUrl,
            token: token,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            Value<String> baseUrl = const Value.absent(),
            Value<String> token = const Value.absent(),
          }) =>
              IbkrProfileSettingsCompanion.insert(
            id: id,
            enabled: enabled,
            baseUrl: baseUrl,
            token: token,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$IbkrProfileSettingsTableProcessedTableManager = ProcessedTableManager<
    _$Database,
    $IbkrProfileSettingsTable,
    IbkrProfileSetting,
    $$IbkrProfileSettingsTableFilterComposer,
    $$IbkrProfileSettingsTableOrderingComposer,
    $$IbkrProfileSettingsTableAnnotationComposer,
    $$IbkrProfileSettingsTableCreateCompanionBuilder,
    $$IbkrProfileSettingsTableUpdateCompanionBuilder,
    (
      IbkrProfileSetting,
      BaseReferences<_$Database, $IbkrProfileSettingsTable, IbkrProfileSetting>
    ),
    IbkrProfileSetting,
    PrefetchHooks Function()>;
typedef $$IbkrCacheEntriesTableCreateCompanionBuilder
    = IbkrCacheEntriesCompanion Function({
  required String kind,
  required String cacheKey,
  required String payloadJson,
  required DateTime cachedAt,
  Value<int> rowid,
});
typedef $$IbkrCacheEntriesTableUpdateCompanionBuilder
    = IbkrCacheEntriesCompanion Function({
  Value<String> kind,
  Value<String> cacheKey,
  Value<String> payloadJson,
  Value<DateTime> cachedAt,
  Value<int> rowid,
});

class $$IbkrCacheEntriesTableFilterComposer
    extends Composer<_$Database, $IbkrCacheEntriesTable> {
  $$IbkrCacheEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cacheKey => $composableBuilder(
      column: $table.cacheKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnFilters(column));
}

class $$IbkrCacheEntriesTableOrderingComposer
    extends Composer<_$Database, $IbkrCacheEntriesTable> {
  $$IbkrCacheEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get kind => $composableBuilder(
      column: $table.kind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cacheKey => $composableBuilder(
      column: $table.cacheKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnOrderings(column));
}

class $$IbkrCacheEntriesTableAnnotationComposer
    extends Composer<_$Database, $IbkrCacheEntriesTable> {
  $$IbkrCacheEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get cacheKey =>
      $composableBuilder(column: $table.cacheKey, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$IbkrCacheEntriesTableTableManager extends RootTableManager<
    _$Database,
    $IbkrCacheEntriesTable,
    IbkrCacheEntry,
    $$IbkrCacheEntriesTableFilterComposer,
    $$IbkrCacheEntriesTableOrderingComposer,
    $$IbkrCacheEntriesTableAnnotationComposer,
    $$IbkrCacheEntriesTableCreateCompanionBuilder,
    $$IbkrCacheEntriesTableUpdateCompanionBuilder,
    (
      IbkrCacheEntry,
      BaseReferences<_$Database, $IbkrCacheEntriesTable, IbkrCacheEntry>
    ),
    IbkrCacheEntry,
    PrefetchHooks Function()> {
  $$IbkrCacheEntriesTableTableManager(
      _$Database db, $IbkrCacheEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$IbkrCacheEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$IbkrCacheEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$IbkrCacheEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> kind = const Value.absent(),
            Value<String> cacheKey = const Value.absent(),
            Value<String> payloadJson = const Value.absent(),
            Value<DateTime> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              IbkrCacheEntriesCompanion(
            kind: kind,
            cacheKey: cacheKey,
            payloadJson: payloadJson,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String kind,
            required String cacheKey,
            required String payloadJson,
            required DateTime cachedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              IbkrCacheEntriesCompanion.insert(
            kind: kind,
            cacheKey: cacheKey,
            payloadJson: payloadJson,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$IbkrCacheEntriesTableProcessedTableManager = ProcessedTableManager<
    _$Database,
    $IbkrCacheEntriesTable,
    IbkrCacheEntry,
    $$IbkrCacheEntriesTableFilterComposer,
    $$IbkrCacheEntriesTableOrderingComposer,
    $$IbkrCacheEntriesTableAnnotationComposer,
    $$IbkrCacheEntriesTableCreateCompanionBuilder,
    $$IbkrCacheEntriesTableUpdateCompanionBuilder,
    (
      IbkrCacheEntry,
      BaseReferences<_$Database, $IbkrCacheEntriesTable, IbkrCacheEntry>
    ),
    IbkrCacheEntry,
    PrefetchHooks Function()>;

class $DatabaseManager {
  final _$Database _db;
  $DatabaseManager(this._db);
  $$CandlesTableTableManager get candles =>
      $$CandlesTableTableManager(_db, _db.candles);
  $$TradesTableTableManager get trades =>
      $$TradesTableTableManager(_db, _db.trades);
  $$IbkrProfileSettingsTableTableManager get ibkrProfileSettings =>
      $$IbkrProfileSettingsTableTableManager(_db, _db.ibkrProfileSettings);
  $$IbkrCacheEntriesTableTableManager get ibkrCacheEntries =>
      $$IbkrCacheEntriesTableTableManager(_db, _db.ibkrCacheEntries);
}
