import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:market_monk/legacy_app_state_database.steps.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'legacy_app_state_database.g.dart';

class AppProfiles extends Table {
  TextColumn get name => text()();
  IntColumn get sortOrder => integer()();

  @override
  Set<Column<Object>> get primaryKey => {name};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get valueType => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(tables: [AppProfiles, AppSettings])
class LegacyAppStateDatabase extends _$LegacyAppStateDatabase {
  static const activeProfileSettingKey = 'activeProfile';

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: stepByStep(from1To2: (migrator, schema) async {}),
      );

  LegacyAppStateDatabase() : super(_openConnection());

  LegacyAppStateDatabase.connect(super.executor);

  static QueryExecutor _openConnection() => driftDatabase(
        name: 'market-monk.settings',
        native: const DriftNativeOptions(
          databaseDirectory: getApplicationSupportDirectory,
        ),
      );

  Future<List<String>> readProfiles() async {
    final rows = await (select(appProfiles)
          ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]))
        .get();
    return rows.map((row) => row.name).toList(growable: false);
  }

  Future<void> replaceProfiles(List<String> profiles) async {
    await transaction(() async {
      await delete(appProfiles).go();
      await batch((batch) {
        batch.insertAll(
          appProfiles,
          [
            for (var index = 0; index < profiles.length; index++)
              AppProfilesCompanion.insert(
                name: profiles[index],
                sortOrder: index,
              ),
          ],
        );
      });
    });
  }

  Future<void> seedProfilesIfEmpty(List<String> profiles) async {
    final count = await appProfiles.count().getSingle();
    if (count == 0) {
      await replaceProfiles(profiles);
    }
  }

  Future<String?> readActiveProfile() async {
    final value = await readSetting(activeProfileSettingKey);
    return value is String ? value : null;
  }

  Future<void> setActiveProfile(String profile) =>
      writeSetting(activeProfileSettingKey, profile);

  Future<Object?> readSetting(String key) async {
    final row = await (select(appSettings)..where((row) => row.key.equals(key)))
        .getSingleOrNull();
    if (row == null) return null;
    return _decodeSetting(row.valueType, row.value);
  }

  Future<Map<String, Object?>> readSettings() async {
    final rows = await select(appSettings).get();
    return {
      for (final row in rows) row.key: _decodeSetting(row.valueType, row.value),
    };
  }

  Future<void> writeSetting(String key, Object? value) async {
    if (value == null) {
      await (delete(appSettings)..where((row) => row.key.equals(key))).go();
      return;
    }
    final encoded = _encodeSetting(value);
    await into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(
        key: key,
        valueType: encoded.$1,
        value: encoded.$2,
      ),
    );
  }

  Future<void> seedSettingIfMissing(String key, Object? value) async {
    if (value == null) return;
    final existing = await (select(appSettings)
          ..where((row) => row.key.equals(key)))
        .getSingleOrNull();
    if (existing == null) {
      await writeSetting(key, value);
    }
  }

  (String, String) _encodeSetting(Object value) => switch (value) {
        bool value => ('bool', value ? '1' : '0'),
        int value => ('int', value.toString()),
        double value => ('double', value.toString()),
        String value => ('string', value),
        List<String> value => ('stringList', jsonEncode(value)),
        List value when value.every((item) => item is String) => (
            'stringList',
            jsonEncode(value)
          ),
        _ => throw ArgumentError.value(value, 'value', 'Unsupported setting'),
      };

  Object _decodeSetting(String type, String value) => switch (type) {
        'bool' => value == '1',
        'int' => int.parse(value),
        'double' => double.parse(value),
        'string' => value,
        'stringList' =>
          (jsonDecode(value) as List<dynamic>).cast<String>().toList(),
        _ => throw StateError('Unsupported app setting type: $type'),
      };
}
