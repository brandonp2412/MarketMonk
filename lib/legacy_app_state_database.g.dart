// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'legacy_app_state_database.dart';

// ignore_for_file: type=lint
class $AppProfilesTable extends AppProfiles
    with TableInfo<$AppProfilesTable, AppProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [name, sortOrder];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_profiles';
  @override
  VerificationContext validateIntegrity(Insertable<AppProfile> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {name};
  @override
  AppProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppProfile(
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
    );
  }

  @override
  $AppProfilesTable createAlias(String alias) {
    return $AppProfilesTable(attachedDatabase, alias);
  }
}

class AppProfile extends DataClass implements Insertable<AppProfile> {
  final String name;
  final int sortOrder;
  const AppProfile({required this.name, required this.sortOrder});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['name'] = Variable<String>(name);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  AppProfilesCompanion toCompanion(bool nullToAbsent) {
    return AppProfilesCompanion(
      name: Value(name),
      sortOrder: Value(sortOrder),
    );
  }

  factory AppProfile.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppProfile(
      name: serializer.fromJson<String>(json['name']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'name': serializer.toJson<String>(name),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  AppProfile copyWith({String? name, int? sortOrder}) => AppProfile(
        name: name ?? this.name,
        sortOrder: sortOrder ?? this.sortOrder,
      );
  AppProfile copyWithCompanion(AppProfilesCompanion data) {
    return AppProfile(
      name: data.name.present ? data.name.value : this.name,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppProfile(')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(name, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppProfile &&
          other.name == this.name &&
          other.sortOrder == this.sortOrder);
}

class AppProfilesCompanion extends UpdateCompanion<AppProfile> {
  final Value<String> name;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const AppProfilesCompanion({
    this.name = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppProfilesCompanion.insert({
    required String name,
    required int sortOrder,
    this.rowid = const Value.absent(),
  })  : name = Value(name),
        sortOrder = Value(sortOrder);
  static Insertable<AppProfile> custom({
    Expression<String>? name,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (name != null) 'name': name,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppProfilesCompanion copyWith(
      {Value<String>? name, Value<int>? sortOrder, Value<int>? rowid}) {
    return AppProfilesCompanion(
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppProfilesCompanion(')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
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
  VerificationContext validateIntegrity(Insertable<AppSetting> instance,
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
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
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

class AppSetting extends DataClass implements Insertable<AppSetting> {
  final String key;
  final String valueType;
  final String value;
  const AppSetting(
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

  factory AppSetting.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
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

  AppSetting copyWith({String? key, String? valueType, String? value}) =>
      AppSetting(
        key: key ?? this.key,
        valueType: valueType ?? this.valueType,
        value: value ?? this.value,
      );
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      key: data.key.present ? data.key.value : this.key,
      valueType: data.valueType.present ? data.valueType.value : this.valueType,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
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
      (other is AppSetting &&
          other.key == this.key &&
          other.valueType == this.valueType &&
          other.value == this.value);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
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
  static Insertable<AppSetting> custom({
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

abstract class _$LegacyAppStateDatabase extends GeneratedDatabase {
  _$LegacyAppStateDatabase(QueryExecutor e) : super(e);
  $AppStateDatabaseManager get managers => $AppStateDatabaseManager(this);
  late final $AppProfilesTable appProfiles = $AppProfilesTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [appProfiles, appSettings];
}

typedef $$AppProfilesTableCreateCompanionBuilder = AppProfilesCompanion
    Function({
  required String name,
  required int sortOrder,
  Value<int> rowid,
});
typedef $$AppProfilesTableUpdateCompanionBuilder = AppProfilesCompanion
    Function({
  Value<String> name,
  Value<int> sortOrder,
  Value<int> rowid,
});

class $$AppProfilesTableFilterComposer
    extends Composer<_$LegacyAppStateDatabase, $AppProfilesTable> {
  $$AppProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnFilters(column));
}

class $$AppProfilesTableOrderingComposer
    extends Composer<_$LegacyAppStateDatabase, $AppProfilesTable> {
  $$AppProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnOrderings(column));
}

class $$AppProfilesTableAnnotationComposer
    extends Composer<_$LegacyAppStateDatabase, $AppProfilesTable> {
  $$AppProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$AppProfilesTableTableManager extends RootTableManager<
    _$LegacyAppStateDatabase,
    $AppProfilesTable,
    AppProfile,
    $$AppProfilesTableFilterComposer,
    $$AppProfilesTableOrderingComposer,
    $$AppProfilesTableAnnotationComposer,
    $$AppProfilesTableCreateCompanionBuilder,
    $$AppProfilesTableUpdateCompanionBuilder,
    (
      AppProfile,
      BaseReferences<_$LegacyAppStateDatabase, $AppProfilesTable, AppProfile>
    ),
    AppProfile,
    PrefetchHooks Function()> {
  $$AppProfilesTableTableManager(
      _$LegacyAppStateDatabase db, $AppProfilesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> name = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AppProfilesCompanion(
            name: name,
            sortOrder: sortOrder,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String name,
            required int sortOrder,
            Value<int> rowid = const Value.absent(),
          }) =>
              AppProfilesCompanion.insert(
            name: name,
            sortOrder: sortOrder,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AppProfilesTableProcessedTableManager = ProcessedTableManager<
    _$LegacyAppStateDatabase,
    $AppProfilesTable,
    AppProfile,
    $$AppProfilesTableFilterComposer,
    $$AppProfilesTableOrderingComposer,
    $$AppProfilesTableAnnotationComposer,
    $$AppProfilesTableCreateCompanionBuilder,
    $$AppProfilesTableUpdateCompanionBuilder,
    (
      AppProfile,
      BaseReferences<_$LegacyAppStateDatabase, $AppProfilesTable, AppProfile>
    ),
    AppProfile,
    PrefetchHooks Function()>;
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
    extends Composer<_$LegacyAppStateDatabase, $AppSettingsTable> {
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
    extends Composer<_$LegacyAppStateDatabase, $AppSettingsTable> {
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
    extends Composer<_$LegacyAppStateDatabase, $AppSettingsTable> {
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
    _$LegacyAppStateDatabase,
    $AppSettingsTable,
    AppSetting,
    $$AppSettingsTableFilterComposer,
    $$AppSettingsTableOrderingComposer,
    $$AppSettingsTableAnnotationComposer,
    $$AppSettingsTableCreateCompanionBuilder,
    $$AppSettingsTableUpdateCompanionBuilder,
    (
      AppSetting,
      BaseReferences<_$LegacyAppStateDatabase, $AppSettingsTable, AppSetting>
    ),
    AppSetting,
    PrefetchHooks Function()> {
  $$AppSettingsTableTableManager(
      _$LegacyAppStateDatabase db, $AppSettingsTable table)
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
    _$LegacyAppStateDatabase,
    $AppSettingsTable,
    AppSetting,
    $$AppSettingsTableFilterComposer,
    $$AppSettingsTableOrderingComposer,
    $$AppSettingsTableAnnotationComposer,
    $$AppSettingsTableCreateCompanionBuilder,
    $$AppSettingsTableUpdateCompanionBuilder,
    (
      AppSetting,
      BaseReferences<_$LegacyAppStateDatabase, $AppSettingsTable, AppSetting>
    ),
    AppSetting,
    PrefetchHooks Function()>;

class $AppStateDatabaseManager {
  final _$LegacyAppStateDatabase _db;
  $AppStateDatabaseManager(this._db);
  $$AppProfilesTableTableManager get appProfiles =>
      $$AppProfilesTableTableManager(_db, _db.appProfiles);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
}
