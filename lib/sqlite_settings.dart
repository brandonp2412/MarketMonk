import 'package:market_monk/app_state_database.dart';
import 'package:market_monk/legacy_app_state_reader_stub.dart'
    if (dart.library.io) 'package:market_monk/legacy_app_state_reader_io.dart';
import 'package:market_monk/logging.dart';
import 'package:market_monk/legacy_preferences_migration.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cached application settings whose only writable persistence is SQLite.
class SqliteSettings {
  SqliteSettings._(this.database, this._values);

  /// SQLite store shared by application settings and the profile registry.
  final AppStateDatabase database;
  final Map<String, Object?> _values;
  static Future<SqliteSettings>? _instance;
  static SqliteSettings? _loaded;
  Future<void> _pendingWrites = Future.value();

  /// Opens SQLite and completes the legacy import before exposing any state.
  static Future<SqliteSettings> getInstance() async {
    if (_loaded != null) return _loaded!;
    return _instance ??= _open();
  }

  static Future<SqliteSettings> _open() async {
    final database = AppStateDatabase();
    try {
      return _loaded = await initialize(database);
    } catch (_) {
      await database.close();
      _instance = null;
      rethrow;
    }
  }

  /// Runs the upgrade once, marking completion only after every profile commits.
  /// A failed import can be retried without overwriting already copied rows.
  static Future<SqliteSettings> initialize(
    AppStateDatabase database, {
    Future<Map<String, Object?>> Function()? readLegacyValues,
    Future<Map<String, Object?>?> Function()? readLegacyAppStateValues,
    ProfileDatabaseFactory? profileDatabaseFactory,
  }) async {
    if (await database.readSetting(legacyAppStateMigrationCompleteKey) !=
        true) {
      try {
        final values =
            await (readLegacyAppStateValues ?? readLegacyAppStateFile)();
        if (values != null) {
          await seedAppStateFromLegacyValues(
            values: values,
            appState: database,
          );
        }
        await database.writeSetting(legacyAppStateMigrationCompleteKey, true);
      } catch (error, stack) {
        talker.handle(
          error,
          stack,
          'Could not import legacy SQLite app state; will retry next startup',
        );
      }
    }

    if (await database.readSetting(sqliteMigrationCompleteKey) != true) {
      final values = await (readLegacyValues ?? _readLegacyValues)();
      await seedSqliteFromLegacyValues(
        values: values,
        appState: database,
        profileDatabaseFactory: profileDatabaseFactory,
      );
      await database.writeSetting(sqliteMigrationCompleteKey, true);
    }
    return load(database);
  }

  static Future<Map<String, Object?>> _readLegacyValues() async {
    final preferences = await SharedPreferences.getInstance();
    return {for (final key in preferences.getKeys()) key: preferences.get(key)};
  }

  /// Loads a supplied SQLite store, including its profile registry.
  static Future<SqliteSettings> load(AppStateDatabase database) async {
    final result = SqliteSettings._(database, {});
    await result.reload();
    return result;
  }

  /// Supplies an isolated store for tests or an embedded application host.
  static Future<SqliteSettings> useInstance(Future<SqliteSettings> instance) {
    _loaded = null;
    return _instance = instance.then((value) => _loaded = value);
  }

  /// Refreshes the in-memory view after a transactional restore.
  Future<void> reload() async {
    final values = await database.readSettings();
    values['accounts'] = await database.readProfiles();
    values['activeAccount'] = await database.readActiveProfile() ?? 'Default';
    _values
      ..clear()
      ..addAll(values);
  }

  /// Returns an independent snapshot suitable for a portable backup manifest.
  Map<String, Object?> snapshot() => {
        for (final entry in _values.entries)
          if (entry.key != 'accounts' &&
              entry.key != 'activeAccount' &&
              entry.key != AppStateDatabase.activeProfileSettingKey &&
              entry.key != sqliteMigrationCompleteKey &&
              entry.key != legacyAppStateMigrationCompleteKey)
            entry.key: entry.value is List
                ? List<String>.from(entry.value as List)
                : entry.value,
      };

  /// Reads a string setting from the loaded SQLite snapshot.
  String? getString(String key) => _values[key] as String?;

  /// Reads a boolean setting from the loaded SQLite snapshot.
  bool? getBool(String key) => _values[key] as bool?;

  /// Reads an integer setting from the loaded SQLite snapshot.
  int? getInt(String key) => _values[key] as int?;

  /// Reads a floating-point setting from the loaded SQLite snapshot.
  double? getDouble(String key) => (_values[key] as num?)?.toDouble();

  /// Returns a copy so callers cannot mutate the persisted snapshot.
  List<String>? getStringList(String key) =>
      (_values[key] as List?)?.cast<String>().toList();

  /// Commits a string value, then updates the cached snapshot.
  Future<void> setString(String key, String value) => _write(key, value);

  /// Commits a boolean value, then updates the cached snapshot.
  Future<void> setBool(String key, bool value) => _write(key, value);

  /// Commits an integer value, then updates the cached snapshot.
  Future<void> setInt(String key, int value) => _write(key, value);

  /// Commits a floating-point value, then updates the cached snapshot.
  Future<void> setDouble(String key, double value) => _write(key, value);

  /// Commits a copied list, then updates the cached snapshot.
  Future<void> setStringList(String key, List<String> value) =>
      _write(key, List<String>.of(value));

  /// Deletes a setting without consulting the retired preference store.
  Future<void> remove(String key) => _write(key, null);

  /// Waits until all previously requested mutations have committed.
  Future<void> flush() => _pendingWrites;

  Future<void> _serialize(Future<void> Function() operation) {
    final result = _pendingWrites.then((_) => operation());
    _pendingWrites =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _write(String key, Object? value) => _serialize(() async {
        if (key == 'accounts') {
          await database.replaceProfiles((value as List<String>));
        } else if (key == 'activeAccount') {
          await database.setActiveProfile(value as String);
        } else {
          await database.writeSetting(key, value);
        }
        if (value == null) {
          _values.remove(key);
        } else {
          _values[key] = value;
        }
      });

  /// Commits profile membership and active selection together.
  Future<void> setProfiles(List<String> profiles, String activeProfile) =>
      _serialize(() async {
        if (!profiles.contains(activeProfile) ||
            !profiles.contains('Default')) {
          throw ArgumentError(
            'Profile registry must include Default and the active profile',
          );
        }
        await database.transaction(() async {
          await database.replaceProfiles(profiles);
          await database.setActiveProfile(activeProfile);
        });
        _values['accounts'] = List<String>.of(profiles);
        _values['activeAccount'] = activeProfile;
      });

  /// Replaces global state atomically, leaving the legacy import disabled.
  Future<void> restore(
    Map<String, Object?> values,
    List<String> profiles,
    String activeProfile,
  ) =>
      _serialize(() async {
        await database.transaction(() async {
          await database.delete(database.appSettings).go();
          await database.replaceProfiles(profiles);
          for (final entry in values.entries) {
            if (!legacyProfilePreferenceKeys.contains(entry.key)) {
              await database.writeSetting(entry.key, entry.value);
            }
          }
          await database.setActiveProfile(activeProfile);
          await database.writeSetting(sqliteMigrationCompleteKey, true);
          await database.writeSetting(
            legacyAppStateMigrationCompleteKey,
            true,
          );
        });
        await reload();
      });
}
