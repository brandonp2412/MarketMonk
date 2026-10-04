// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ProfilesTable extends Profiles
    with TableInfo<$ProfilesTable, StoredProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 128),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 256),
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [id, name, sortOrder, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'profiles';
  @override
  VerificationContext validateIntegrity(Insertable<StoredProfile> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta,
          sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StoredProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredProfile(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $ProfilesTable createAlias(String alias) {
    return $ProfilesTable(attachedDatabase, alias);
  }
}

class StoredProfile extends DataClass implements Insertable<StoredProfile> {
  final String id;
  final String name;
  final int sortOrder;
  final DateTime createdAt;
  const StoredProfile(
      {required this.id,
      required this.name,
      required this.sortOrder,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['sort_order'] = Variable<int>(sortOrder);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ProfilesCompanion toCompanion(bool nullToAbsent) {
    return ProfilesCompanion(
      id: Value(id),
      name: Value(name),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
    );
  }

  factory StoredProfile.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredProfile(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  StoredProfile copyWith(
          {String? id, String? name, int? sortOrder, DateTime? createdAt}) =>
      StoredProfile(
        id: id ?? this.id,
        name: name ?? this.name,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt ?? this.createdAt,
      );
  StoredProfile copyWithCompanion(ProfilesCompanion data) {
    return StoredProfile(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredProfile(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, sortOrder, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredProfile &&
          other.id == this.id &&
          other.name == this.name &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt);
}

class ProfilesCompanion extends UpdateCompanion<StoredProfile> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> sortOrder;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ProfilesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProfilesCompanion.insert({
    required String id,
    required String name,
    required int sortOrder,
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        sortOrder = Value(sortOrder);
  static Insertable<StoredProfile> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? sortOrder,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProfilesCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<int>? sortOrder,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return ProfilesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProfilesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppStateTable extends AppState
    with TableInfo<$AppStateTable, StoredAppState> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _activeProfileIdMeta =
      const VerificationMeta('activeProfileId');
  @override
  late final GeneratedColumn<String> activeProfileId = GeneratedColumn<String>(
      'active_profile_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES profiles (id) ON DELETE SET NULL'));
  @override
  List<GeneratedColumn> get $columns => [id, activeProfileId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_state';
  @override
  VerificationContext validateIntegrity(Insertable<StoredAppState> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('active_profile_id')) {
      context.handle(
          _activeProfileIdMeta,
          activeProfileId.isAcceptableOrUnknown(
              data['active_profile_id']!, _activeProfileIdMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StoredAppState map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredAppState(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      activeProfileId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}active_profile_id']),
    );
  }

  @override
  $AppStateTable createAlias(String alias) {
    return $AppStateTable(attachedDatabase, alias);
  }
}

class StoredAppState extends DataClass implements Insertable<StoredAppState> {
  final int id;
  final String? activeProfileId;
  const StoredAppState({required this.id, this.activeProfileId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || activeProfileId != null) {
      map['active_profile_id'] = Variable<String>(activeProfileId);
    }
    return map;
  }

  AppStateCompanion toCompanion(bool nullToAbsent) {
    return AppStateCompanion(
      id: Value(id),
      activeProfileId: activeProfileId == null && nullToAbsent
          ? const Value.absent()
          : Value(activeProfileId),
    );
  }

  factory StoredAppState.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredAppState(
      id: serializer.fromJson<int>(json['id']),
      activeProfileId: serializer.fromJson<String?>(json['activeProfileId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'activeProfileId': serializer.toJson<String?>(activeProfileId),
    };
  }

  StoredAppState copyWith(
          {int? id, Value<String?> activeProfileId = const Value.absent()}) =>
      StoredAppState(
        id: id ?? this.id,
        activeProfileId: activeProfileId.present
            ? activeProfileId.value
            : this.activeProfileId,
      );
  StoredAppState copyWithCompanion(AppStateCompanion data) {
    return StoredAppState(
      id: data.id.present ? data.id.value : this.id,
      activeProfileId: data.activeProfileId.present
          ? data.activeProfileId.value
          : this.activeProfileId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredAppState(')
          ..write('id: $id, ')
          ..write('activeProfileId: $activeProfileId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, activeProfileId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredAppState &&
          other.id == this.id &&
          other.activeProfileId == this.activeProfileId);
}

class AppStateCompanion extends UpdateCompanion<StoredAppState> {
  final Value<int> id;
  final Value<String?> activeProfileId;
  const AppStateCompanion({
    this.id = const Value.absent(),
    this.activeProfileId = const Value.absent(),
  });
  AppStateCompanion.insert({
    this.id = const Value.absent(),
    this.activeProfileId = const Value.absent(),
  });
  static Insertable<StoredAppState> custom({
    Expression<int>? id,
    Expression<String>? activeProfileId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (activeProfileId != null) 'active_profile_id': activeProfileId,
    });
  }

  AppStateCompanion copyWith(
      {Value<int>? id, Value<String?>? activeProfileId}) {
    return AppStateCompanion(
      id: id ?? this.id,
      activeProfileId: activeProfileId ?? this.activeProfileId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (activeProfileId.present) {
      map['active_profile_id'] = Variable<String>(activeProfileId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppStateCompanion(')
          ..write('id: $id, ')
          ..write('activeProfileId: $activeProfileId')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, StoredAppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueTypeMeta =
      const VerificationMeta('valueType');
  @override
  late final GeneratedColumn<String> valueType = GeneratedColumn<String>(
      'value_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [key, valueType, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(Insertable<StoredAppSetting> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value_type')) {
      context.handle(_valueTypeMeta,
          valueType.isAcceptableOrUnknown(data['value_type']!, _valueTypeMeta));
    } else if (isInserting) {
      context.missing(_valueTypeMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  StoredAppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredAppSetting(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      valueType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value_type'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value'])!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class StoredAppSetting extends DataClass
    implements Insertable<StoredAppSetting> {
  final String key;
  final String valueType;
  final String value;
  const StoredAppSetting(
      {required this.key, required this.valueType, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value_type'] = Variable<String>(valueType);
    map['value'] = Variable<String>(value);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(
      key: Value(key),
      valueType: Value(valueType),
      value: Value(value),
    );
  }

  factory StoredAppSetting.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredAppSetting(
      key: serializer.fromJson<String>(json['key']),
      valueType: serializer.fromJson<String>(json['valueType']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'valueType': serializer.toJson<String>(valueType),
      'value': serializer.toJson<String>(value),
    };
  }

  StoredAppSetting copyWith({String? key, String? valueType, String? value}) =>
      StoredAppSetting(
        key: key ?? this.key,
        valueType: valueType ?? this.valueType,
        value: value ?? this.value,
      );
  StoredAppSetting copyWithCompanion(AppSettingsCompanion data) {
    return StoredAppSetting(
      key: data.key.present ? data.key.value : this.key,
      valueType: data.valueType.present ? data.valueType.value : this.valueType,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredAppSetting(')
          ..write('key: $key, ')
          ..write('valueType: $valueType, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, valueType, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredAppSetting &&
          other.key == this.key &&
          other.valueType == this.valueType &&
          other.value == this.value);
}

class AppSettingsCompanion extends UpdateCompanion<StoredAppSetting> {
  final Value<String> key;
  final Value<String> valueType;
  final Value<String> value;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.valueType = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String valueType,
    required String value,
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        valueType = Value(valueType),
        value = Value(value);
  static Insertable<StoredAppSetting> custom({
    Expression<String>? key,
    Expression<String>? valueType,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (valueType != null) 'value_type': valueType,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith(
      {Value<String>? key,
      Value<String>? valueType,
      Value<String>? value,
      Value<int>? rowid}) {
    return AppSettingsCompanion(
      key: key ?? this.key,
      valueType: valueType ?? this.valueType,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (valueType.present) {
      map['value_type'] = Variable<String>(valueType.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('valueType: $valueType, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TradesTable extends Trades with TableInfo<$TradesTable, StoredTrade> {
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
  static const VerificationMeta _profileIdMeta =
      const VerificationMeta('profileId');
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
      'profile_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES profiles (id) ON DELETE CASCADE'));
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
        profileId,
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
  VerificationContext validateIntegrity(Insertable<StoredTrade> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('profile_id')) {
      context.handle(_profileIdMeta,
          profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta));
    } else if (isInserting) {
      context.missing(_profileIdMeta);
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
  StoredTrade map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredTrade(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      profileId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}profile_id'])!,
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

class StoredTrade extends DataClass implements Insertable<StoredTrade> {
  final int id;
  final String profileId;
  final String symbol;
  final String name;
  final double quantity;
  final double price;
  final String tradeType;
  final DateTime tradeDate;
  final double realizedPL;
  final double commission;
  const StoredTrade(
      {required this.id,
      required this.profileId,
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
    map['profile_id'] = Variable<String>(profileId);
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
      profileId: Value(profileId),
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

  factory StoredTrade.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredTrade(
      id: serializer.fromJson<int>(json['id']),
      profileId: serializer.fromJson<String>(json['profileId']),
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
      'profileId': serializer.toJson<String>(profileId),
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

  StoredTrade copyWith(
          {int? id,
          String? profileId,
          String? symbol,
          String? name,
          double? quantity,
          double? price,
          String? tradeType,
          DateTime? tradeDate,
          double? realizedPL,
          double? commission}) =>
      StoredTrade(
        id: id ?? this.id,
        profileId: profileId ?? this.profileId,
        symbol: symbol ?? this.symbol,
        name: name ?? this.name,
        quantity: quantity ?? this.quantity,
        price: price ?? this.price,
        tradeType: tradeType ?? this.tradeType,
        tradeDate: tradeDate ?? this.tradeDate,
        realizedPL: realizedPL ?? this.realizedPL,
        commission: commission ?? this.commission,
      );
  StoredTrade copyWithCompanion(TradesCompanion data) {
    return StoredTrade(
      id: data.id.present ? data.id.value : this.id,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
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
    return (StringBuffer('StoredTrade(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
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
  int get hashCode => Object.hash(id, profileId, symbol, name, quantity, price,
      tradeType, tradeDate, realizedPL, commission);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredTrade &&
          other.id == this.id &&
          other.profileId == this.profileId &&
          other.symbol == this.symbol &&
          other.name == this.name &&
          other.quantity == this.quantity &&
          other.price == this.price &&
          other.tradeType == this.tradeType &&
          other.tradeDate == this.tradeDate &&
          other.realizedPL == this.realizedPL &&
          other.commission == this.commission);
}

class TradesCompanion extends UpdateCompanion<StoredTrade> {
  final Value<int> id;
  final Value<String> profileId;
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
    this.profileId = const Value.absent(),
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
    required String profileId,
    required String symbol,
    required String name,
    required double quantity,
    required double price,
    required String tradeType,
    required DateTime tradeDate,
    this.realizedPL = const Value.absent(),
    this.commission = const Value.absent(),
  })  : profileId = Value(profileId),
        symbol = Value(symbol),
        name = Value(name),
        quantity = Value(quantity),
        price = Value(price),
        tradeType = Value(tradeType),
        tradeDate = Value(tradeDate);
  static Insertable<StoredTrade> custom({
    Expression<int>? id,
    Expression<String>? profileId,
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
      if (profileId != null) 'profile_id': profileId,
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
      Value<String>? profileId,
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
      profileId: profileId ?? this.profileId,
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
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
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
          ..write('profileId: $profileId, ')
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

class $IbkrSettingsTable extends IbkrSettings
    with TableInfo<$IbkrSettingsTable, StoredIbkrSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $IbkrSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _profileIdMeta =
      const VerificationMeta('profileId');
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
      'profile_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES profiles (id) ON DELETE CASCADE'));
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
  List<GeneratedColumn> get $columns => [profileId, enabled, baseUrl, token];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ibkr_settings';
  @override
  VerificationContext validateIntegrity(Insertable<StoredIbkrSetting> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('profile_id')) {
      context.handle(_profileIdMeta,
          profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta));
    } else if (isInserting) {
      context.missing(_profileIdMeta);
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
  Set<GeneratedColumn> get $primaryKey => {profileId};
  @override
  StoredIbkrSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredIbkrSetting(
      profileId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}profile_id'])!,
      enabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}enabled'])!,
      baseUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}base_url'])!,
      token: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}token'])!,
    );
  }

  @override
  $IbkrSettingsTable createAlias(String alias) {
    return $IbkrSettingsTable(attachedDatabase, alias);
  }
}

class StoredIbkrSetting extends DataClass
    implements Insertable<StoredIbkrSetting> {
  final String profileId;
  final bool enabled;
  final String baseUrl;
  final String token;
  const StoredIbkrSetting(
      {required this.profileId,
      required this.enabled,
      required this.baseUrl,
      required this.token});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['profile_id'] = Variable<String>(profileId);
    map['enabled'] = Variable<bool>(enabled);
    map['base_url'] = Variable<String>(baseUrl);
    map['token'] = Variable<String>(token);
    return map;
  }

  IbkrSettingsCompanion toCompanion(bool nullToAbsent) {
    return IbkrSettingsCompanion(
      profileId: Value(profileId),
      enabled: Value(enabled),
      baseUrl: Value(baseUrl),
      token: Value(token),
    );
  }

  factory StoredIbkrSetting.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredIbkrSetting(
      profileId: serializer.fromJson<String>(json['profileId']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      baseUrl: serializer.fromJson<String>(json['baseUrl']),
      token: serializer.fromJson<String>(json['token']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'profileId': serializer.toJson<String>(profileId),
      'enabled': serializer.toJson<bool>(enabled),
      'baseUrl': serializer.toJson<String>(baseUrl),
      'token': serializer.toJson<String>(token),
    };
  }

  StoredIbkrSetting copyWith(
          {String? profileId, bool? enabled, String? baseUrl, String? token}) =>
      StoredIbkrSetting(
        profileId: profileId ?? this.profileId,
        enabled: enabled ?? this.enabled,
        baseUrl: baseUrl ?? this.baseUrl,
        token: token ?? this.token,
      );
  StoredIbkrSetting copyWithCompanion(IbkrSettingsCompanion data) {
    return StoredIbkrSetting(
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      baseUrl: data.baseUrl.present ? data.baseUrl.value : this.baseUrl,
      token: data.token.present ? data.token.value : this.token,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredIbkrSetting(')
          ..write('profileId: $profileId, ')
          ..write('enabled: $enabled, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('token: $token')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(profileId, enabled, baseUrl, token);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredIbkrSetting &&
          other.profileId == this.profileId &&
          other.enabled == this.enabled &&
          other.baseUrl == this.baseUrl &&
          other.token == this.token);
}

class IbkrSettingsCompanion extends UpdateCompanion<StoredIbkrSetting> {
  final Value<String> profileId;
  final Value<bool> enabled;
  final Value<String> baseUrl;
  final Value<String> token;
  final Value<int> rowid;
  const IbkrSettingsCompanion({
    this.profileId = const Value.absent(),
    this.enabled = const Value.absent(),
    this.baseUrl = const Value.absent(),
    this.token = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  IbkrSettingsCompanion.insert({
    required String profileId,
    this.enabled = const Value.absent(),
    this.baseUrl = const Value.absent(),
    this.token = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : profileId = Value(profileId);
  static Insertable<StoredIbkrSetting> custom({
    Expression<String>? profileId,
    Expression<bool>? enabled,
    Expression<String>? baseUrl,
    Expression<String>? token,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (profileId != null) 'profile_id': profileId,
      if (enabled != null) 'enabled': enabled,
      if (baseUrl != null) 'base_url': baseUrl,
      if (token != null) 'token': token,
      if (rowid != null) 'rowid': rowid,
    });
  }

  IbkrSettingsCompanion copyWith(
      {Value<String>? profileId,
      Value<bool>? enabled,
      Value<String>? baseUrl,
      Value<String>? token,
      Value<int>? rowid}) {
    return IbkrSettingsCompanion(
      profileId: profileId ?? this.profileId,
      enabled: enabled ?? this.enabled,
      baseUrl: baseUrl ?? this.baseUrl,
      token: token ?? this.token,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
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
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('IbkrSettingsCompanion(')
          ..write('profileId: $profileId, ')
          ..write('enabled: $enabled, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('token: $token, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $IbkrCacheEntriesTable extends IbkrCacheEntries
    with TableInfo<$IbkrCacheEntriesTable, StoredIbkrCacheEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $IbkrCacheEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _profileIdMeta =
      const VerificationMeta('profileId');
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
      'profile_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES profiles (id) ON DELETE CASCADE'));
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
  List<GeneratedColumn> get $columns =>
      [profileId, kind, cacheKey, payloadJson, cachedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ibkr_cache_entries';
  @override
  VerificationContext validateIntegrity(
      Insertable<StoredIbkrCacheEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('profile_id')) {
      context.handle(_profileIdMeta,
          profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta));
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
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
  Set<GeneratedColumn> get $primaryKey => {profileId, kind, cacheKey};
  @override
  StoredIbkrCacheEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredIbkrCacheEntry(
      profileId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}profile_id'])!,
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

class StoredIbkrCacheEntry extends DataClass
    implements Insertable<StoredIbkrCacheEntry> {
  final String profileId;
  final String kind;
  final String cacheKey;
  final String payloadJson;
  final DateTime cachedAt;
  const StoredIbkrCacheEntry(
      {required this.profileId,
      required this.kind,
      required this.cacheKey,
      required this.payloadJson,
      required this.cachedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['profile_id'] = Variable<String>(profileId);
    map['kind'] = Variable<String>(kind);
    map['cache_key'] = Variable<String>(cacheKey);
    map['payload_json'] = Variable<String>(payloadJson);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  IbkrCacheEntriesCompanion toCompanion(bool nullToAbsent) {
    return IbkrCacheEntriesCompanion(
      profileId: Value(profileId),
      kind: Value(kind),
      cacheKey: Value(cacheKey),
      payloadJson: Value(payloadJson),
      cachedAt: Value(cachedAt),
    );
  }

  factory StoredIbkrCacheEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredIbkrCacheEntry(
      profileId: serializer.fromJson<String>(json['profileId']),
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
      'profileId': serializer.toJson<String>(profileId),
      'kind': serializer.toJson<String>(kind),
      'cacheKey': serializer.toJson<String>(cacheKey),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  StoredIbkrCacheEntry copyWith(
          {String? profileId,
          String? kind,
          String? cacheKey,
          String? payloadJson,
          DateTime? cachedAt}) =>
      StoredIbkrCacheEntry(
        profileId: profileId ?? this.profileId,
        kind: kind ?? this.kind,
        cacheKey: cacheKey ?? this.cacheKey,
        payloadJson: payloadJson ?? this.payloadJson,
        cachedAt: cachedAt ?? this.cachedAt,
      );
  StoredIbkrCacheEntry copyWithCompanion(IbkrCacheEntriesCompanion data) {
    return StoredIbkrCacheEntry(
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      kind: data.kind.present ? data.kind.value : this.kind,
      cacheKey: data.cacheKey.present ? data.cacheKey.value : this.cacheKey,
      payloadJson:
          data.payloadJson.present ? data.payloadJson.value : this.payloadJson,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredIbkrCacheEntry(')
          ..write('profileId: $profileId, ')
          ..write('kind: $kind, ')
          ..write('cacheKey: $cacheKey, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(profileId, kind, cacheKey, payloadJson, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredIbkrCacheEntry &&
          other.profileId == this.profileId &&
          other.kind == this.kind &&
          other.cacheKey == this.cacheKey &&
          other.payloadJson == this.payloadJson &&
          other.cachedAt == this.cachedAt);
}

class IbkrCacheEntriesCompanion extends UpdateCompanion<StoredIbkrCacheEntry> {
  final Value<String> profileId;
  final Value<String> kind;
  final Value<String> cacheKey;
  final Value<String> payloadJson;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const IbkrCacheEntriesCompanion({
    this.profileId = const Value.absent(),
    this.kind = const Value.absent(),
    this.cacheKey = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  IbkrCacheEntriesCompanion.insert({
    required String profileId,
    required String kind,
    required String cacheKey,
    required String payloadJson,
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  })  : profileId = Value(profileId),
        kind = Value(kind),
        cacheKey = Value(cacheKey),
        payloadJson = Value(payloadJson),
        cachedAt = Value(cachedAt);
  static Insertable<StoredIbkrCacheEntry> custom({
    Expression<String>? profileId,
    Expression<String>? kind,
    Expression<String>? cacheKey,
    Expression<String>? payloadJson,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (profileId != null) 'profile_id': profileId,
      if (kind != null) 'kind': kind,
      if (cacheKey != null) 'cache_key': cacheKey,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  IbkrCacheEntriesCompanion copyWith(
      {Value<String>? profileId,
      Value<String>? kind,
      Value<String>? cacheKey,
      Value<String>? payloadJson,
      Value<DateTime>? cachedAt,
      Value<int>? rowid}) {
    return IbkrCacheEntriesCompanion(
      profileId: profileId ?? this.profileId,
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
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
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
          ..write('profileId: $profileId, ')
          ..write('kind: $kind, ')
          ..write('cacheKey: $cacheKey, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CandlesTable extends Candles
    with TableInfo<$CandlesTable, StoredCandle> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CandlesTable(this.attachedDatabase, [this._alias]);
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
      [symbol, date, open, high, low, close, volume, adjClose];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'candles';
  @override
  VerificationContext validateIntegrity(Insertable<StoredCandle> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
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
  Set<GeneratedColumn> get $primaryKey => {symbol, date};
  @override
  StoredCandle map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredCandle(
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

class StoredCandle extends DataClass implements Insertable<StoredCandle> {
  final String symbol;
  final DateTime date;
  final double open;
  final double high;
  final double low;
  final double close;
  final int volume;
  final double adjClose;
  const StoredCandle(
      {required this.symbol,
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

  factory StoredCandle.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredCandle(
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

  StoredCandle copyWith(
          {String? symbol,
          DateTime? date,
          double? open,
          double? high,
          double? low,
          double? close,
          int? volume,
          double? adjClose}) =>
      StoredCandle(
        symbol: symbol ?? this.symbol,
        date: date ?? this.date,
        open: open ?? this.open,
        high: high ?? this.high,
        low: low ?? this.low,
        close: close ?? this.close,
        volume: volume ?? this.volume,
        adjClose: adjClose ?? this.adjClose,
      );
  StoredCandle copyWithCompanion(CandlesCompanion data) {
    return StoredCandle(
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
    return (StringBuffer('StoredCandle(')
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
      Object.hash(symbol, date, open, high, low, close, volume, adjClose);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredCandle &&
          other.symbol == this.symbol &&
          other.date == this.date &&
          other.open == this.open &&
          other.high == this.high &&
          other.low == this.low &&
          other.close == this.close &&
          other.volume == this.volume &&
          other.adjClose == this.adjClose);
}

class CandlesCompanion extends UpdateCompanion<StoredCandle> {
  final Value<String> symbol;
  final Value<DateTime> date;
  final Value<double> open;
  final Value<double> high;
  final Value<double> low;
  final Value<double> close;
  final Value<int> volume;
  final Value<double> adjClose;
  final Value<int> rowid;
  const CandlesCompanion({
    this.symbol = const Value.absent(),
    this.date = const Value.absent(),
    this.open = const Value.absent(),
    this.high = const Value.absent(),
    this.low = const Value.absent(),
    this.close = const Value.absent(),
    this.volume = const Value.absent(),
    this.adjClose = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CandlesCompanion.insert({
    required String symbol,
    required DateTime date,
    this.open = const Value.absent(),
    this.high = const Value.absent(),
    this.low = const Value.absent(),
    this.close = const Value.absent(),
    this.volume = const Value.absent(),
    this.adjClose = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : symbol = Value(symbol),
        date = Value(date);
  static Insertable<StoredCandle> custom({
    Expression<String>? symbol,
    Expression<DateTime>? date,
    Expression<double>? open,
    Expression<double>? high,
    Expression<double>? low,
    Expression<double>? close,
    Expression<int>? volume,
    Expression<double>? adjClose,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (symbol != null) 'symbol': symbol,
      if (date != null) 'date': date,
      if (open != null) 'open': open,
      if (high != null) 'high': high,
      if (low != null) 'low': low,
      if (close != null) 'close': close,
      if (volume != null) 'volume': volume,
      if (adjClose != null) 'adj_close': adjClose,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CandlesCompanion copyWith(
      {Value<String>? symbol,
      Value<DateTime>? date,
      Value<double>? open,
      Value<double>? high,
      Value<double>? low,
      Value<double>? close,
      Value<int>? volume,
      Value<double>? adjClose,
      Value<int>? rowid}) {
    return CandlesCompanion(
      symbol: symbol ?? this.symbol,
      date: date ?? this.date,
      open: open ?? this.open,
      high: high ?? this.high,
      low: low ?? this.low,
      close: close ?? this.close,
      volume: volume ?? this.volume,
      adjClose: adjClose ?? this.adjClose,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
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
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CandlesCompanion(')
          ..write('symbol: $symbol, ')
          ..write('date: $date, ')
          ..write('open: $open, ')
          ..write('high: $high, ')
          ..write('low: $low, ')
          ..write('close: $close, ')
          ..write('volume: $volume, ')
          ..write('adjClose: $adjClose, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SymbolMetadataTable extends SymbolMetadata
    with TableInfo<$SymbolMetadataTable, StoredSymbolMetadata> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SymbolMetadataTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _symbolMeta = const VerificationMeta('symbol');
  @override
  late final GeneratedColumn<String> symbol = GeneratedColumn<String>(
      'symbol', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _displayNameMeta =
      const VerificationMeta('displayName');
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
      'display_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _currencyMeta =
      const VerificationMeta('currency');
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
      'currency', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _exchangeMeta =
      const VerificationMeta('exchange');
  @override
  late final GeneratedColumn<String> exchange = GeneratedColumn<String>(
      'exchange', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _quoteTypeMeta =
      const VerificationMeta('quoteType');
  @override
  late final GeneratedColumn<String> quoteType = GeneratedColumn<String>(
      'quote_type', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _payloadJsonMeta =
      const VerificationMeta('payloadJson');
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
      'payload_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _cachedAtMeta =
      const VerificationMeta('cachedAt');
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
      'cached_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        symbol,
        displayName,
        currency,
        exchange,
        quoteType,
        payloadJson,
        cachedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'symbol_metadata';
  @override
  VerificationContext validateIntegrity(
      Insertable<StoredSymbolMetadata> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('symbol')) {
      context.handle(_symbolMeta,
          symbol.isAcceptableOrUnknown(data['symbol']!, _symbolMeta));
    } else if (isInserting) {
      context.missing(_symbolMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
          _displayNameMeta,
          displayName.isAcceptableOrUnknown(
              data['display_name']!, _displayNameMeta));
    }
    if (data.containsKey('currency')) {
      context.handle(_currencyMeta,
          currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta));
    }
    if (data.containsKey('exchange')) {
      context.handle(_exchangeMeta,
          exchange.isAcceptableOrUnknown(data['exchange']!, _exchangeMeta));
    }
    if (data.containsKey('quote_type')) {
      context.handle(_quoteTypeMeta,
          quoteType.isAcceptableOrUnknown(data['quote_type']!, _quoteTypeMeta));
    }
    if (data.containsKey('payload_json')) {
      context.handle(
          _payloadJsonMeta,
          payloadJson.isAcceptableOrUnknown(
              data['payload_json']!, _payloadJsonMeta));
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
  Set<GeneratedColumn> get $primaryKey => {symbol};
  @override
  StoredSymbolMetadata map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredSymbolMetadata(
      symbol: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}symbol'])!,
      displayName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}display_name']),
      currency: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}currency']),
      exchange: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}exchange']),
      quoteType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}quote_type']),
      payloadJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload_json']),
      cachedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}cached_at'])!,
    );
  }

  @override
  $SymbolMetadataTable createAlias(String alias) {
    return $SymbolMetadataTable(attachedDatabase, alias);
  }
}

class StoredSymbolMetadata extends DataClass
    implements Insertable<StoredSymbolMetadata> {
  final String symbol;
  final String? displayName;
  final String? currency;
  final String? exchange;
  final String? quoteType;
  final String? payloadJson;
  final DateTime cachedAt;
  const StoredSymbolMetadata(
      {required this.symbol,
      this.displayName,
      this.currency,
      this.exchange,
      this.quoteType,
      this.payloadJson,
      required this.cachedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['symbol'] = Variable<String>(symbol);
    if (!nullToAbsent || displayName != null) {
      map['display_name'] = Variable<String>(displayName);
    }
    if (!nullToAbsent || currency != null) {
      map['currency'] = Variable<String>(currency);
    }
    if (!nullToAbsent || exchange != null) {
      map['exchange'] = Variable<String>(exchange);
    }
    if (!nullToAbsent || quoteType != null) {
      map['quote_type'] = Variable<String>(quoteType);
    }
    if (!nullToAbsent || payloadJson != null) {
      map['payload_json'] = Variable<String>(payloadJson);
    }
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  SymbolMetadataCompanion toCompanion(bool nullToAbsent) {
    return SymbolMetadataCompanion(
      symbol: Value(symbol),
      displayName: displayName == null && nullToAbsent
          ? const Value.absent()
          : Value(displayName),
      currency: currency == null && nullToAbsent
          ? const Value.absent()
          : Value(currency),
      exchange: exchange == null && nullToAbsent
          ? const Value.absent()
          : Value(exchange),
      quoteType: quoteType == null && nullToAbsent
          ? const Value.absent()
          : Value(quoteType),
      payloadJson: payloadJson == null && nullToAbsent
          ? const Value.absent()
          : Value(payloadJson),
      cachedAt: Value(cachedAt),
    );
  }

  factory StoredSymbolMetadata.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredSymbolMetadata(
      symbol: serializer.fromJson<String>(json['symbol']),
      displayName: serializer.fromJson<String?>(json['displayName']),
      currency: serializer.fromJson<String?>(json['currency']),
      exchange: serializer.fromJson<String?>(json['exchange']),
      quoteType: serializer.fromJson<String?>(json['quoteType']),
      payloadJson: serializer.fromJson<String?>(json['payloadJson']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'symbol': serializer.toJson<String>(symbol),
      'displayName': serializer.toJson<String?>(displayName),
      'currency': serializer.toJson<String?>(currency),
      'exchange': serializer.toJson<String?>(exchange),
      'quoteType': serializer.toJson<String?>(quoteType),
      'payloadJson': serializer.toJson<String?>(payloadJson),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  StoredSymbolMetadata copyWith(
          {String? symbol,
          Value<String?> displayName = const Value.absent(),
          Value<String?> currency = const Value.absent(),
          Value<String?> exchange = const Value.absent(),
          Value<String?> quoteType = const Value.absent(),
          Value<String?> payloadJson = const Value.absent(),
          DateTime? cachedAt}) =>
      StoredSymbolMetadata(
        symbol: symbol ?? this.symbol,
        displayName: displayName.present ? displayName.value : this.displayName,
        currency: currency.present ? currency.value : this.currency,
        exchange: exchange.present ? exchange.value : this.exchange,
        quoteType: quoteType.present ? quoteType.value : this.quoteType,
        payloadJson: payloadJson.present ? payloadJson.value : this.payloadJson,
        cachedAt: cachedAt ?? this.cachedAt,
      );
  StoredSymbolMetadata copyWithCompanion(SymbolMetadataCompanion data) {
    return StoredSymbolMetadata(
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      displayName:
          data.displayName.present ? data.displayName.value : this.displayName,
      currency: data.currency.present ? data.currency.value : this.currency,
      exchange: data.exchange.present ? data.exchange.value : this.exchange,
      quoteType: data.quoteType.present ? data.quoteType.value : this.quoteType,
      payloadJson:
          data.payloadJson.present ? data.payloadJson.value : this.payloadJson,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredSymbolMetadata(')
          ..write('symbol: $symbol, ')
          ..write('displayName: $displayName, ')
          ..write('currency: $currency, ')
          ..write('exchange: $exchange, ')
          ..write('quoteType: $quoteType, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(symbol, displayName, currency, exchange,
      quoteType, payloadJson, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredSymbolMetadata &&
          other.symbol == this.symbol &&
          other.displayName == this.displayName &&
          other.currency == this.currency &&
          other.exchange == this.exchange &&
          other.quoteType == this.quoteType &&
          other.payloadJson == this.payloadJson &&
          other.cachedAt == this.cachedAt);
}

class SymbolMetadataCompanion extends UpdateCompanion<StoredSymbolMetadata> {
  final Value<String> symbol;
  final Value<String?> displayName;
  final Value<String?> currency;
  final Value<String?> exchange;
  final Value<String?> quoteType;
  final Value<String?> payloadJson;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const SymbolMetadataCompanion({
    this.symbol = const Value.absent(),
    this.displayName = const Value.absent(),
    this.currency = const Value.absent(),
    this.exchange = const Value.absent(),
    this.quoteType = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SymbolMetadataCompanion.insert({
    required String symbol,
    this.displayName = const Value.absent(),
    this.currency = const Value.absent(),
    this.exchange = const Value.absent(),
    this.quoteType = const Value.absent(),
    this.payloadJson = const Value.absent(),
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  })  : symbol = Value(symbol),
        cachedAt = Value(cachedAt);
  static Insertable<StoredSymbolMetadata> custom({
    Expression<String>? symbol,
    Expression<String>? displayName,
    Expression<String>? currency,
    Expression<String>? exchange,
    Expression<String>? quoteType,
    Expression<String>? payloadJson,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (symbol != null) 'symbol': symbol,
      if (displayName != null) 'display_name': displayName,
      if (currency != null) 'currency': currency,
      if (exchange != null) 'exchange': exchange,
      if (quoteType != null) 'quote_type': quoteType,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SymbolMetadataCompanion copyWith(
      {Value<String>? symbol,
      Value<String?>? displayName,
      Value<String?>? currency,
      Value<String?>? exchange,
      Value<String?>? quoteType,
      Value<String?>? payloadJson,
      Value<DateTime>? cachedAt,
      Value<int>? rowid}) {
    return SymbolMetadataCompanion(
      symbol: symbol ?? this.symbol,
      displayName: displayName ?? this.displayName,
      currency: currency ?? this.currency,
      exchange: exchange ?? this.exchange,
      quoteType: quoteType ?? this.quoteType,
      payloadJson: payloadJson ?? this.payloadJson,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (symbol.present) {
      map['symbol'] = Variable<String>(symbol.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (exchange.present) {
      map['exchange'] = Variable<String>(exchange.value);
    }
    if (quoteType.present) {
      map['quote_type'] = Variable<String>(quoteType.value);
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
    return (StringBuffer('SymbolMetadataCompanion(')
          ..write('symbol: $symbol, ')
          ..write('displayName: $displayName, ')
          ..write('currency: $currency, ')
          ..write('exchange: $exchange, ')
          ..write('quoteType: $quoteType, ')
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
  late final $ProfilesTable profiles = $ProfilesTable(this);
  late final $AppStateTable appState = $AppStateTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $TradesTable trades = $TradesTable(this);
  late final $IbkrSettingsTable ibkrSettings = $IbkrSettingsTable(this);
  late final $IbkrCacheEntriesTable ibkrCacheEntries =
      $IbkrCacheEntriesTable(this);
  late final $CandlesTable candles = $CandlesTable(this);
  late final $SymbolMetadataTable symbolMetadata = $SymbolMetadataTable(this);
  late final Index idxUnifiedProfilesSortOrder = Index(
      'idx_unified_profiles_sort_order',
      'CREATE INDEX idx_unified_profiles_sort_order ON profiles (sort_order)');
  late final Index idxUnifiedTradesProfileSymbolDate = Index(
      'idx_unified_trades_profile_symbol_date',
      'CREATE INDEX idx_unified_trades_profile_symbol_date ON trades (profile_id, symbol, trade_date)');
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        profiles,
        appState,
        appSettings,
        trades,
        ibkrSettings,
        ibkrCacheEntries,
        candles,
        symbolMetadata,
        idxUnifiedProfilesSortOrder,
        idxUnifiedTradesProfileSymbolDate
      ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules(
        [
          WritePropagation(
            on: TableUpdateQuery.onTableName('profiles',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('app_state', kind: UpdateKind.update),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('profiles',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('trades', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('profiles',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('ibkr_settings', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('profiles',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('ibkr_cache_entries', kind: UpdateKind.delete),
            ],
          ),
        ],
      );
}

typedef $$ProfilesTableCreateCompanionBuilder = ProfilesCompanion Function({
  required String id,
  required String name,
  required int sortOrder,
  Value<DateTime> createdAt,
  Value<int> rowid,
});
typedef $$ProfilesTableUpdateCompanionBuilder = ProfilesCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<int> sortOrder,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

final class $$ProfilesTableReferences
    extends BaseReferences<_$Database, $ProfilesTable, StoredProfile> {
  $$ProfilesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$AppStateTable, List<StoredAppState>>
      _appStateRefsTable(_$Database db) =>
          MultiTypedResultKey.fromTable(db.appState,
              aliasName: 'profiles__id__app_state__active_profile_id');

  $$AppStateTableProcessedTableManager get appStateRefs {
    final manager = $$AppStateTableTableManager($_db, $_db.appState).filter(
        (f) => f.activeProfileId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_appStateRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$TradesTable, List<StoredTrade>> _tradesRefsTable(
          _$Database db) =>
      MultiTypedResultKey.fromTable(db.trades,
          aliasName: 'profiles__id__trades__profile_id');

  $$TradesTableProcessedTableManager get tradesRefs {
    final manager = $$TradesTableTableManager($_db, $_db.trades)
        .filter((f) => f.profileId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_tradesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$IbkrSettingsTable, List<StoredIbkrSetting>>
      _ibkrSettingsRefsTable(_$Database db) =>
          MultiTypedResultKey.fromTable(db.ibkrSettings,
              aliasName: 'profiles__id__ibkr_settings__profile_id');

  $$IbkrSettingsTableProcessedTableManager get ibkrSettingsRefs {
    final manager = $$IbkrSettingsTableTableManager($_db, $_db.ibkrSettings)
        .filter((f) => f.profileId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_ibkrSettingsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$IbkrCacheEntriesTable, List<StoredIbkrCacheEntry>>
      _ibkrCacheEntriesRefsTable(_$Database db) =>
          MultiTypedResultKey.fromTable(db.ibkrCacheEntries,
              aliasName: 'profiles__id__ibkr_cache_entries__profile_id');

  $$IbkrCacheEntriesTableProcessedTableManager get ibkrCacheEntriesRefs {
    final manager = $$IbkrCacheEntriesTableTableManager(
            $_db, $_db.ibkrCacheEntries)
        .filter((f) => f.profileId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_ibkrCacheEntriesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$ProfilesTableFilterComposer
    extends Composer<_$Database, $ProfilesTable> {
  $$ProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  Expression<bool> appStateRefs(
      Expression<bool> Function($$AppStateTableFilterComposer f) f) {
    final $$AppStateTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.appState,
        getReferencedColumn: (t) => t.activeProfileId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AppStateTableFilterComposer(
              $db: $db,
              $table: $db.appState,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> tradesRefs(
      Expression<bool> Function($$TradesTableFilterComposer f) f) {
    final $$TradesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.trades,
        getReferencedColumn: (t) => t.profileId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TradesTableFilterComposer(
              $db: $db,
              $table: $db.trades,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> ibkrSettingsRefs(
      Expression<bool> Function($$IbkrSettingsTableFilterComposer f) f) {
    final $$IbkrSettingsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.ibkrSettings,
        getReferencedColumn: (t) => t.profileId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$IbkrSettingsTableFilterComposer(
              $db: $db,
              $table: $db.ibkrSettings,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> ibkrCacheEntriesRefs(
      Expression<bool> Function($$IbkrCacheEntriesTableFilterComposer f) f) {
    final $$IbkrCacheEntriesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.ibkrCacheEntries,
        getReferencedColumn: (t) => t.profileId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$IbkrCacheEntriesTableFilterComposer(
              $db: $db,
              $table: $db.ibkrCacheEntries,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ProfilesTableOrderingComposer
    extends Composer<_$Database, $ProfilesTable> {
  $$ProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$ProfilesTableAnnotationComposer
    extends Composer<_$Database, $ProfilesTable> {
  $$ProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> appStateRefs<T extends Object>(
      Expression<T> Function($$AppStateTableAnnotationComposer a) f) {
    final $$AppStateTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.appState,
        getReferencedColumn: (t) => t.activeProfileId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AppStateTableAnnotationComposer(
              $db: $db,
              $table: $db.appState,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> tradesRefs<T extends Object>(
      Expression<T> Function($$TradesTableAnnotationComposer a) f) {
    final $$TradesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.trades,
        getReferencedColumn: (t) => t.profileId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TradesTableAnnotationComposer(
              $db: $db,
              $table: $db.trades,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> ibkrSettingsRefs<T extends Object>(
      Expression<T> Function($$IbkrSettingsTableAnnotationComposer a) f) {
    final $$IbkrSettingsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.ibkrSettings,
        getReferencedColumn: (t) => t.profileId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$IbkrSettingsTableAnnotationComposer(
              $db: $db,
              $table: $db.ibkrSettings,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> ibkrCacheEntriesRefs<T extends Object>(
      Expression<T> Function($$IbkrCacheEntriesTableAnnotationComposer a) f) {
    final $$IbkrCacheEntriesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.ibkrCacheEntries,
        getReferencedColumn: (t) => t.profileId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$IbkrCacheEntriesTableAnnotationComposer(
              $db: $db,
              $table: $db.ibkrCacheEntries,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ProfilesTableTableManager extends RootTableManager<
    _$Database,
    $ProfilesTable,
    StoredProfile,
    $$ProfilesTableFilterComposer,
    $$ProfilesTableOrderingComposer,
    $$ProfilesTableAnnotationComposer,
    $$ProfilesTableCreateCompanionBuilder,
    $$ProfilesTableUpdateCompanionBuilder,
    (StoredProfile, $$ProfilesTableReferences),
    StoredProfile,
    PrefetchHooks Function(
        {bool appStateRefs,
        bool tradesRefs,
        bool ibkrSettingsRefs,
        bool ibkrCacheEntriesRefs})> {
  $$ProfilesTableTableManager(_$Database db, $ProfilesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProfilesCompanion(
            id: id,
            name: name,
            sortOrder: sortOrder,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            required int sortOrder,
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProfilesCompanion.insert(
            id: id,
            name: name,
            sortOrder: sortOrder,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$ProfilesTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: (
              {appStateRefs = false,
              tradesRefs = false,
              ibkrSettingsRefs = false,
              ibkrCacheEntriesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (appStateRefs) db.appState,
                if (tradesRefs) db.trades,
                if (ibkrSettingsRefs) db.ibkrSettings,
                if (ibkrCacheEntriesRefs) db.ibkrCacheEntries
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (appStateRefs)
                    await $_getPrefetchedData<StoredProfile, $ProfilesTable,
                            StoredAppState>(
                        currentTable: table,
                        referencedTable:
                            $$ProfilesTableReferences._appStateRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ProfilesTableReferences(db, table, p0)
                                .appStateRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.activeProfileId == item.id),
                        typedResults: items),
                  if (tradesRefs)
                    await $_getPrefetchedData<StoredProfile, $ProfilesTable,
                            StoredTrade>(
                        currentTable: table,
                        referencedTable:
                            $$ProfilesTableReferences._tradesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ProfilesTableReferences(db, table, p0).tradesRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.profileId == item.id),
                        typedResults: items),
                  if (ibkrSettingsRefs)
                    await $_getPrefetchedData<StoredProfile, $ProfilesTable,
                            StoredIbkrSetting>(
                        currentTable: table,
                        referencedTable: $$ProfilesTableReferences
                            ._ibkrSettingsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ProfilesTableReferences(db, table, p0)
                                .ibkrSettingsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.profileId == item.id),
                        typedResults: items),
                  if (ibkrCacheEntriesRefs)
                    await $_getPrefetchedData<StoredProfile, $ProfilesTable,
                            StoredIbkrCacheEntry>(
                        currentTable: table,
                        referencedTable: $$ProfilesTableReferences
                            ._ibkrCacheEntriesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ProfilesTableReferences(db, table, p0)
                                .ibkrCacheEntriesRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.profileId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$ProfilesTableProcessedTableManager = ProcessedTableManager<
    _$Database,
    $ProfilesTable,
    StoredProfile,
    $$ProfilesTableFilterComposer,
    $$ProfilesTableOrderingComposer,
    $$ProfilesTableAnnotationComposer,
    $$ProfilesTableCreateCompanionBuilder,
    $$ProfilesTableUpdateCompanionBuilder,
    (StoredProfile, $$ProfilesTableReferences),
    StoredProfile,
    PrefetchHooks Function(
        {bool appStateRefs,
        bool tradesRefs,
        bool ibkrSettingsRefs,
        bool ibkrCacheEntriesRefs})>;
typedef $$AppStateTableCreateCompanionBuilder = AppStateCompanion Function({
  Value<int> id,
  Value<String?> activeProfileId,
});
typedef $$AppStateTableUpdateCompanionBuilder = AppStateCompanion Function({
  Value<int> id,
  Value<String?> activeProfileId,
});

final class $$AppStateTableReferences
    extends BaseReferences<_$Database, $AppStateTable, StoredAppState> {
  $$AppStateTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ProfilesTable _activeProfileIdTable(_$Database db) =>
      db.profiles.createAlias('app_state__active_profile_id__profiles__id');

  $$ProfilesTableProcessedTableManager? get activeProfileId {
    final $_column = $_itemColumn<String>('active_profile_id');
    if ($_column == null) return null;
    final manager = $$ProfilesTableTableManager($_db, $_db.profiles)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_activeProfileIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$AppStateTableFilterComposer
    extends Composer<_$Database, $AppStateTable> {
  $$AppStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  $$ProfilesTableFilterComposer get activeProfileId {
    final $$ProfilesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.activeProfileId,
        referencedTable: $db.profiles,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProfilesTableFilterComposer(
              $db: $db,
              $table: $db.profiles,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$AppStateTableOrderingComposer
    extends Composer<_$Database, $AppStateTable> {
  $$AppStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  $$ProfilesTableOrderingComposer get activeProfileId {
    final $$ProfilesTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.activeProfileId,
        referencedTable: $db.profiles,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProfilesTableOrderingComposer(
              $db: $db,
              $table: $db.profiles,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$AppStateTableAnnotationComposer
    extends Composer<_$Database, $AppStateTable> {
  $$AppStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  $$ProfilesTableAnnotationComposer get activeProfileId {
    final $$ProfilesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.activeProfileId,
        referencedTable: $db.profiles,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProfilesTableAnnotationComposer(
              $db: $db,
              $table: $db.profiles,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$AppStateTableTableManager extends RootTableManager<
    _$Database,
    $AppStateTable,
    StoredAppState,
    $$AppStateTableFilterComposer,
    $$AppStateTableOrderingComposer,
    $$AppStateTableAnnotationComposer,
    $$AppStateTableCreateCompanionBuilder,
    $$AppStateTableUpdateCompanionBuilder,
    (StoredAppState, $$AppStateTableReferences),
    StoredAppState,
    PrefetchHooks Function({bool activeProfileId})> {
  $$AppStateTableTableManager(_$Database db, $AppStateTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String?> activeProfileId = const Value.absent(),
          }) =>
              AppStateCompanion(
            id: id,
            activeProfileId: activeProfileId,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String?> activeProfileId = const Value.absent(),
          }) =>
              AppStateCompanion.insert(
            id: id,
            activeProfileId: activeProfileId,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$AppStateTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({activeProfileId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (activeProfileId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.activeProfileId,
                    referencedTable:
                        $$AppStateTableReferences._activeProfileIdTable(db),
                    referencedColumn:
                        $$AppStateTableReferences._activeProfileIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$AppStateTableProcessedTableManager = ProcessedTableManager<
    _$Database,
    $AppStateTable,
    StoredAppState,
    $$AppStateTableFilterComposer,
    $$AppStateTableOrderingComposer,
    $$AppStateTableAnnotationComposer,
    $$AppStateTableCreateCompanionBuilder,
    $$AppStateTableUpdateCompanionBuilder,
    (StoredAppState, $$AppStateTableReferences),
    StoredAppState,
    PrefetchHooks Function({bool activeProfileId})>;
typedef $$AppSettingsTableCreateCompanionBuilder = AppSettingsCompanion
    Function({
  required String key,
  required String valueType,
  required String value,
  Value<int> rowid,
});
typedef $$AppSettingsTableUpdateCompanionBuilder = AppSettingsCompanion
    Function({
  Value<String> key,
  Value<String> valueType,
  Value<String> value,
  Value<int> rowid,
});

class $$AppSettingsTableFilterComposer
    extends Composer<_$Database, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get valueType => $composableBuilder(
      column: $table.valueType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnFilters(column));
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$Database, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get valueType => $composableBuilder(
      column: $table.valueType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnOrderings(column));
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$Database, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get valueType =>
      $composableBuilder(column: $table.valueType, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$AppSettingsTableTableManager extends RootTableManager<
    _$Database,
    $AppSettingsTable,
    StoredAppSetting,
    $$AppSettingsTableFilterComposer,
    $$AppSettingsTableOrderingComposer,
    $$AppSettingsTableAnnotationComposer,
    $$AppSettingsTableCreateCompanionBuilder,
    $$AppSettingsTableUpdateCompanionBuilder,
    (
      StoredAppSetting,
      BaseReferences<_$Database, $AppSettingsTable, StoredAppSetting>
    ),
    StoredAppSetting,
    PrefetchHooks Function()> {
  $$AppSettingsTableTableManager(_$Database db, $AppSettingsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> valueType = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AppSettingsCompanion(
            key: key,
            valueType: valueType,
            value: value,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            required String valueType,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) =>
              AppSettingsCompanion.insert(
            key: key,
            valueType: valueType,
            value: value,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AppSettingsTableProcessedTableManager = ProcessedTableManager<
    _$Database,
    $AppSettingsTable,
    StoredAppSetting,
    $$AppSettingsTableFilterComposer,
    $$AppSettingsTableOrderingComposer,
    $$AppSettingsTableAnnotationComposer,
    $$AppSettingsTableCreateCompanionBuilder,
    $$AppSettingsTableUpdateCompanionBuilder,
    (
      StoredAppSetting,
      BaseReferences<_$Database, $AppSettingsTable, StoredAppSetting>
    ),
    StoredAppSetting,
    PrefetchHooks Function()>;
typedef $$TradesTableCreateCompanionBuilder = TradesCompanion Function({
  Value<int> id,
  required String profileId,
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
  Value<String> profileId,
  Value<String> symbol,
  Value<String> name,
  Value<double> quantity,
  Value<double> price,
  Value<String> tradeType,
  Value<DateTime> tradeDate,
  Value<double> realizedPL,
  Value<double> commission,
});

final class $$TradesTableReferences
    extends BaseReferences<_$Database, $TradesTable, StoredTrade> {
  $$TradesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ProfilesTable _profileIdTable(_$Database db) =>
      db.profiles.createAlias('trades__profile_id__profiles__id');

  $$ProfilesTableProcessedTableManager get profileId {
    final $_column = $_itemColumn<String>('profile_id')!;

    final manager = $$ProfilesTableTableManager($_db, $_db.profiles)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_profileIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

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

  $$ProfilesTableFilterComposer get profileId {
    final $$ProfilesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.profileId,
        referencedTable: $db.profiles,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProfilesTableFilterComposer(
              $db: $db,
              $table: $db.profiles,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
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

  $$ProfilesTableOrderingComposer get profileId {
    final $$ProfilesTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.profileId,
        referencedTable: $db.profiles,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProfilesTableOrderingComposer(
              $db: $db,
              $table: $db.profiles,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
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

  $$ProfilesTableAnnotationComposer get profileId {
    final $$ProfilesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.profileId,
        referencedTable: $db.profiles,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProfilesTableAnnotationComposer(
              $db: $db,
              $table: $db.profiles,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TradesTableTableManager extends RootTableManager<
    _$Database,
    $TradesTable,
    StoredTrade,
    $$TradesTableFilterComposer,
    $$TradesTableOrderingComposer,
    $$TradesTableAnnotationComposer,
    $$TradesTableCreateCompanionBuilder,
    $$TradesTableUpdateCompanionBuilder,
    (StoredTrade, $$TradesTableReferences),
    StoredTrade,
    PrefetchHooks Function({bool profileId})> {
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
            Value<String> profileId = const Value.absent(),
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
            profileId: profileId,
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
            required String profileId,
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
            profileId: profileId,
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
              .map((e) =>
                  (e.readTable(table), $$TradesTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({profileId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (profileId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.profileId,
                    referencedTable:
                        $$TradesTableReferences._profileIdTable(db),
                    referencedColumn:
                        $$TradesTableReferences._profileIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$TradesTableProcessedTableManager = ProcessedTableManager<
    _$Database,
    $TradesTable,
    StoredTrade,
    $$TradesTableFilterComposer,
    $$TradesTableOrderingComposer,
    $$TradesTableAnnotationComposer,
    $$TradesTableCreateCompanionBuilder,
    $$TradesTableUpdateCompanionBuilder,
    (StoredTrade, $$TradesTableReferences),
    StoredTrade,
    PrefetchHooks Function({bool profileId})>;
typedef $$IbkrSettingsTableCreateCompanionBuilder = IbkrSettingsCompanion
    Function({
  required String profileId,
  Value<bool> enabled,
  Value<String> baseUrl,
  Value<String> token,
  Value<int> rowid,
});
typedef $$IbkrSettingsTableUpdateCompanionBuilder = IbkrSettingsCompanion
    Function({
  Value<String> profileId,
  Value<bool> enabled,
  Value<String> baseUrl,
  Value<String> token,
  Value<int> rowid,
});

final class $$IbkrSettingsTableReferences
    extends BaseReferences<_$Database, $IbkrSettingsTable, StoredIbkrSetting> {
  $$IbkrSettingsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ProfilesTable _profileIdTable(_$Database db) =>
      db.profiles.createAlias('ibkr_settings__profile_id__profiles__id');

  $$ProfilesTableProcessedTableManager get profileId {
    final $_column = $_itemColumn<String>('profile_id')!;

    final manager = $$ProfilesTableTableManager($_db, $_db.profiles)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_profileIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$IbkrSettingsTableFilterComposer
    extends Composer<_$Database, $IbkrSettingsTable> {
  $$IbkrSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get baseUrl => $composableBuilder(
      column: $table.baseUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get token => $composableBuilder(
      column: $table.token, builder: (column) => ColumnFilters(column));

  $$ProfilesTableFilterComposer get profileId {
    final $$ProfilesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.profileId,
        referencedTable: $db.profiles,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProfilesTableFilterComposer(
              $db: $db,
              $table: $db.profiles,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$IbkrSettingsTableOrderingComposer
    extends Composer<_$Database, $IbkrSettingsTable> {
  $$IbkrSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get baseUrl => $composableBuilder(
      column: $table.baseUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get token => $composableBuilder(
      column: $table.token, builder: (column) => ColumnOrderings(column));

  $$ProfilesTableOrderingComposer get profileId {
    final $$ProfilesTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.profileId,
        referencedTable: $db.profiles,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProfilesTableOrderingComposer(
              $db: $db,
              $table: $db.profiles,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$IbkrSettingsTableAnnotationComposer
    extends Composer<_$Database, $IbkrSettingsTable> {
  $$IbkrSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<String> get baseUrl =>
      $composableBuilder(column: $table.baseUrl, builder: (column) => column);

  GeneratedColumn<String> get token =>
      $composableBuilder(column: $table.token, builder: (column) => column);

  $$ProfilesTableAnnotationComposer get profileId {
    final $$ProfilesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.profileId,
        referencedTable: $db.profiles,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProfilesTableAnnotationComposer(
              $db: $db,
              $table: $db.profiles,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$IbkrSettingsTableTableManager extends RootTableManager<
    _$Database,
    $IbkrSettingsTable,
    StoredIbkrSetting,
    $$IbkrSettingsTableFilterComposer,
    $$IbkrSettingsTableOrderingComposer,
    $$IbkrSettingsTableAnnotationComposer,
    $$IbkrSettingsTableCreateCompanionBuilder,
    $$IbkrSettingsTableUpdateCompanionBuilder,
    (StoredIbkrSetting, $$IbkrSettingsTableReferences),
    StoredIbkrSetting,
    PrefetchHooks Function({bool profileId})> {
  $$IbkrSettingsTableTableManager(_$Database db, $IbkrSettingsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$IbkrSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$IbkrSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$IbkrSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> profileId = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            Value<String> baseUrl = const Value.absent(),
            Value<String> token = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              IbkrSettingsCompanion(
            profileId: profileId,
            enabled: enabled,
            baseUrl: baseUrl,
            token: token,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String profileId,
            Value<bool> enabled = const Value.absent(),
            Value<String> baseUrl = const Value.absent(),
            Value<String> token = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              IbkrSettingsCompanion.insert(
            profileId: profileId,
            enabled: enabled,
            baseUrl: baseUrl,
            token: token,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$IbkrSettingsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({profileId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (profileId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.profileId,
                    referencedTable:
                        $$IbkrSettingsTableReferences._profileIdTable(db),
                    referencedColumn:
                        $$IbkrSettingsTableReferences._profileIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$IbkrSettingsTableProcessedTableManager = ProcessedTableManager<
    _$Database,
    $IbkrSettingsTable,
    StoredIbkrSetting,
    $$IbkrSettingsTableFilterComposer,
    $$IbkrSettingsTableOrderingComposer,
    $$IbkrSettingsTableAnnotationComposer,
    $$IbkrSettingsTableCreateCompanionBuilder,
    $$IbkrSettingsTableUpdateCompanionBuilder,
    (StoredIbkrSetting, $$IbkrSettingsTableReferences),
    StoredIbkrSetting,
    PrefetchHooks Function({bool profileId})>;
typedef $$IbkrCacheEntriesTableCreateCompanionBuilder
    = IbkrCacheEntriesCompanion Function({
  required String profileId,
  required String kind,
  required String cacheKey,
  required String payloadJson,
  required DateTime cachedAt,
  Value<int> rowid,
});
typedef $$IbkrCacheEntriesTableUpdateCompanionBuilder
    = IbkrCacheEntriesCompanion Function({
  Value<String> profileId,
  Value<String> kind,
  Value<String> cacheKey,
  Value<String> payloadJson,
  Value<DateTime> cachedAt,
  Value<int> rowid,
});

final class $$IbkrCacheEntriesTableReferences extends BaseReferences<_$Database,
    $IbkrCacheEntriesTable, StoredIbkrCacheEntry> {
  $$IbkrCacheEntriesTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $ProfilesTable _profileIdTable(_$Database db) =>
      db.profiles.createAlias('ibkr_cache_entries__profile_id__profiles__id');

  $$ProfilesTableProcessedTableManager get profileId {
    final $_column = $_itemColumn<String>('profile_id')!;

    final manager = $$ProfilesTableTableManager($_db, $_db.profiles)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_profileIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

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

  $$ProfilesTableFilterComposer get profileId {
    final $$ProfilesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.profileId,
        referencedTable: $db.profiles,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProfilesTableFilterComposer(
              $db: $db,
              $table: $db.profiles,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
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

  $$ProfilesTableOrderingComposer get profileId {
    final $$ProfilesTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.profileId,
        referencedTable: $db.profiles,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProfilesTableOrderingComposer(
              $db: $db,
              $table: $db.profiles,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
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

  $$ProfilesTableAnnotationComposer get profileId {
    final $$ProfilesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.profileId,
        referencedTable: $db.profiles,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProfilesTableAnnotationComposer(
              $db: $db,
              $table: $db.profiles,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$IbkrCacheEntriesTableTableManager extends RootTableManager<
    _$Database,
    $IbkrCacheEntriesTable,
    StoredIbkrCacheEntry,
    $$IbkrCacheEntriesTableFilterComposer,
    $$IbkrCacheEntriesTableOrderingComposer,
    $$IbkrCacheEntriesTableAnnotationComposer,
    $$IbkrCacheEntriesTableCreateCompanionBuilder,
    $$IbkrCacheEntriesTableUpdateCompanionBuilder,
    (StoredIbkrCacheEntry, $$IbkrCacheEntriesTableReferences),
    StoredIbkrCacheEntry,
    PrefetchHooks Function({bool profileId})> {
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
            Value<String> profileId = const Value.absent(),
            Value<String> kind = const Value.absent(),
            Value<String> cacheKey = const Value.absent(),
            Value<String> payloadJson = const Value.absent(),
            Value<DateTime> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              IbkrCacheEntriesCompanion(
            profileId: profileId,
            kind: kind,
            cacheKey: cacheKey,
            payloadJson: payloadJson,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String profileId,
            required String kind,
            required String cacheKey,
            required String payloadJson,
            required DateTime cachedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              IbkrCacheEntriesCompanion.insert(
            profileId: profileId,
            kind: kind,
            cacheKey: cacheKey,
            payloadJson: payloadJson,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$IbkrCacheEntriesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({profileId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (profileId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.profileId,
                    referencedTable:
                        $$IbkrCacheEntriesTableReferences._profileIdTable(db),
                    referencedColumn: $$IbkrCacheEntriesTableReferences
                        ._profileIdTable(db)
                        .id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$IbkrCacheEntriesTableProcessedTableManager = ProcessedTableManager<
    _$Database,
    $IbkrCacheEntriesTable,
    StoredIbkrCacheEntry,
    $$IbkrCacheEntriesTableFilterComposer,
    $$IbkrCacheEntriesTableOrderingComposer,
    $$IbkrCacheEntriesTableAnnotationComposer,
    $$IbkrCacheEntriesTableCreateCompanionBuilder,
    $$IbkrCacheEntriesTableUpdateCompanionBuilder,
    (StoredIbkrCacheEntry, $$IbkrCacheEntriesTableReferences),
    StoredIbkrCacheEntry,
    PrefetchHooks Function({bool profileId})>;
typedef $$CandlesTableCreateCompanionBuilder = CandlesCompanion Function({
  required String symbol,
  required DateTime date,
  Value<double> open,
  Value<double> high,
  Value<double> low,
  Value<double> close,
  Value<int> volume,
  Value<double> adjClose,
  Value<int> rowid,
});
typedef $$CandlesTableUpdateCompanionBuilder = CandlesCompanion Function({
  Value<String> symbol,
  Value<DateTime> date,
  Value<double> open,
  Value<double> high,
  Value<double> low,
  Value<double> close,
  Value<int> volume,
  Value<double> adjClose,
  Value<int> rowid,
});

class $$CandlesTableFilterComposer extends Composer<_$Database, $CandlesTable> {
  $$CandlesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
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
    StoredCandle,
    $$CandlesTableFilterComposer,
    $$CandlesTableOrderingComposer,
    $$CandlesTableAnnotationComposer,
    $$CandlesTableCreateCompanionBuilder,
    $$CandlesTableUpdateCompanionBuilder,
    (StoredCandle, BaseReferences<_$Database, $CandlesTable, StoredCandle>),
    StoredCandle,
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
            Value<String> symbol = const Value.absent(),
            Value<DateTime> date = const Value.absent(),
            Value<double> open = const Value.absent(),
            Value<double> high = const Value.absent(),
            Value<double> low = const Value.absent(),
            Value<double> close = const Value.absent(),
            Value<int> volume = const Value.absent(),
            Value<double> adjClose = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CandlesCompanion(
            symbol: symbol,
            date: date,
            open: open,
            high: high,
            low: low,
            close: close,
            volume: volume,
            adjClose: adjClose,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String symbol,
            required DateTime date,
            Value<double> open = const Value.absent(),
            Value<double> high = const Value.absent(),
            Value<double> low = const Value.absent(),
            Value<double> close = const Value.absent(),
            Value<int> volume = const Value.absent(),
            Value<double> adjClose = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CandlesCompanion.insert(
            symbol: symbol,
            date: date,
            open: open,
            high: high,
            low: low,
            close: close,
            volume: volume,
            adjClose: adjClose,
            rowid: rowid,
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
    StoredCandle,
    $$CandlesTableFilterComposer,
    $$CandlesTableOrderingComposer,
    $$CandlesTableAnnotationComposer,
    $$CandlesTableCreateCompanionBuilder,
    $$CandlesTableUpdateCompanionBuilder,
    (StoredCandle, BaseReferences<_$Database, $CandlesTable, StoredCandle>),
    StoredCandle,
    PrefetchHooks Function()>;
typedef $$SymbolMetadataTableCreateCompanionBuilder = SymbolMetadataCompanion
    Function({
  required String symbol,
  Value<String?> displayName,
  Value<String?> currency,
  Value<String?> exchange,
  Value<String?> quoteType,
  Value<String?> payloadJson,
  required DateTime cachedAt,
  Value<int> rowid,
});
typedef $$SymbolMetadataTableUpdateCompanionBuilder = SymbolMetadataCompanion
    Function({
  Value<String> symbol,
  Value<String?> displayName,
  Value<String?> currency,
  Value<String?> exchange,
  Value<String?> quoteType,
  Value<String?> payloadJson,
  Value<DateTime> cachedAt,
  Value<int> rowid,
});

class $$SymbolMetadataTableFilterComposer
    extends Composer<_$Database, $SymbolMetadataTable> {
  $$SymbolMetadataTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get symbol => $composableBuilder(
      column: $table.symbol, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get currency => $composableBuilder(
      column: $table.currency, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get exchange => $composableBuilder(
      column: $table.exchange, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get quoteType => $composableBuilder(
      column: $table.quoteType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnFilters(column));
}

class $$SymbolMetadataTableOrderingComposer
    extends Composer<_$Database, $SymbolMetadataTable> {
  $$SymbolMetadataTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get symbol => $composableBuilder(
      column: $table.symbol, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get currency => $composableBuilder(
      column: $table.currency, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get exchange => $composableBuilder(
      column: $table.exchange, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get quoteType => $composableBuilder(
      column: $table.quoteType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnOrderings(column));
}

class $$SymbolMetadataTableAnnotationComposer
    extends Composer<_$Database, $SymbolMetadataTable> {
  $$SymbolMetadataTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get symbol =>
      $composableBuilder(column: $table.symbol, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<String> get exchange =>
      $composableBuilder(column: $table.exchange, builder: (column) => column);

  GeneratedColumn<String> get quoteType =>
      $composableBuilder(column: $table.quoteType, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$SymbolMetadataTableTableManager extends RootTableManager<
    _$Database,
    $SymbolMetadataTable,
    StoredSymbolMetadata,
    $$SymbolMetadataTableFilterComposer,
    $$SymbolMetadataTableOrderingComposer,
    $$SymbolMetadataTableAnnotationComposer,
    $$SymbolMetadataTableCreateCompanionBuilder,
    $$SymbolMetadataTableUpdateCompanionBuilder,
    (
      StoredSymbolMetadata,
      BaseReferences<_$Database, $SymbolMetadataTable, StoredSymbolMetadata>
    ),
    StoredSymbolMetadata,
    PrefetchHooks Function()> {
  $$SymbolMetadataTableTableManager(_$Database db, $SymbolMetadataTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SymbolMetadataTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SymbolMetadataTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SymbolMetadataTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> symbol = const Value.absent(),
            Value<String?> displayName = const Value.absent(),
            Value<String?> currency = const Value.absent(),
            Value<String?> exchange = const Value.absent(),
            Value<String?> quoteType = const Value.absent(),
            Value<String?> payloadJson = const Value.absent(),
            Value<DateTime> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SymbolMetadataCompanion(
            symbol: symbol,
            displayName: displayName,
            currency: currency,
            exchange: exchange,
            quoteType: quoteType,
            payloadJson: payloadJson,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String symbol,
            Value<String?> displayName = const Value.absent(),
            Value<String?> currency = const Value.absent(),
            Value<String?> exchange = const Value.absent(),
            Value<String?> quoteType = const Value.absent(),
            Value<String?> payloadJson = const Value.absent(),
            required DateTime cachedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              SymbolMetadataCompanion.insert(
            symbol: symbol,
            displayName: displayName,
            currency: currency,
            exchange: exchange,
            quoteType: quoteType,
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

typedef $$SymbolMetadataTableProcessedTableManager = ProcessedTableManager<
    _$Database,
    $SymbolMetadataTable,
    StoredSymbolMetadata,
    $$SymbolMetadataTableFilterComposer,
    $$SymbolMetadataTableOrderingComposer,
    $$SymbolMetadataTableAnnotationComposer,
    $$SymbolMetadataTableCreateCompanionBuilder,
    $$SymbolMetadataTableUpdateCompanionBuilder,
    (
      StoredSymbolMetadata,
      BaseReferences<_$Database, $SymbolMetadataTable, StoredSymbolMetadata>
    ),
    StoredSymbolMetadata,
    PrefetchHooks Function()>;

class $DatabaseManager {
  final _$Database _db;
  $DatabaseManager(this._db);
  $$ProfilesTableTableManager get profiles =>
      $$ProfilesTableTableManager(_db, _db.profiles);
  $$AppStateTableTableManager get appState =>
      $$AppStateTableTableManager(_db, _db.appState);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$TradesTableTableManager get trades =>
      $$TradesTableTableManager(_db, _db.trades);
  $$IbkrSettingsTableTableManager get ibkrSettings =>
      $$IbkrSettingsTableTableManager(_db, _db.ibkrSettings);
  $$IbkrCacheEntriesTableTableManager get ibkrCacheEntries =>
      $$IbkrCacheEntriesTableTableManager(_db, _db.ibkrCacheEntries);
  $$CandlesTableTableManager get candles =>
      $$CandlesTableTableManager(_db, _db.candles);
  $$SymbolMetadataTableTableManager get symbolMetadata =>
      $$SymbolMetadataTableTableManager(_db, _db.symbolMetadata);
}
