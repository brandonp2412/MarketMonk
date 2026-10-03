import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// File name used for full Market Monk backup archives.
const marketMonkBackupFileName = 'market-monk-backup.zip';
const _manifestName = 'manifest.json';
const _backupFormat = 'market-monk-backup';
const _backupVersion = 3;

enum MarketMonkBackupStorageLayout {
  profileDatabases('profile-databases'),
  unifiedDatabase('unified-database');

  const MarketMonkBackupStorageLayout(this.wireName);

  final String wireName;

  static MarketMonkBackupStorageLayout fromWireName(String value) =>
      values.firstWhere(
        (layout) => layout.wireName == value,
        orElse: () => throw const FormatException(
          'Unsupported Market Monk backup storage layout',
        ),
      );
}

/// Returns the SQLite file name used by an account on disk.
String databaseFileNameForAccount(String account) =>
    account == 'Default' ? 'market-monk.sqlite' : 'market-monk-$account.sqlite';

/// Portable application state, intentionally independent of database layout.
class MarketMonkLogicalBackup {
  const MarketMonkLogicalBackup({
    required this.profiles,
    required this.activeProfile,
    required this.settings,
  });

  final List<String> profiles;
  final String activeProfile;
  final Map<String, Object?> settings;
}

/// Physical SQLite payload carried by an archive.
///
/// The current app writes one database per profile. The unified-database shape is
/// already understood by the archive layer so the eventual database cutover can
/// replace only the storage adapter instead of changing the backup format again.
class MarketMonkBackupStorage {
  const MarketMonkBackupStorage._({
    required this.layout,
    required this.profileDatabases,
    required this.unifiedDatabase,
  });

  factory MarketMonkBackupStorage.profileDatabases(
    Map<String, File> databases,
  ) =>
      MarketMonkBackupStorage._(
        layout: MarketMonkBackupStorageLayout.profileDatabases,
        profileDatabases: Map.unmodifiable(databases),
        unifiedDatabase: null,
      );

  factory MarketMonkBackupStorage.unifiedDatabase(File database) =>
      MarketMonkBackupStorage._(
        layout: MarketMonkBackupStorageLayout.unifiedDatabase,
        profileDatabases: const {},
        unifiedDatabase: database,
      );

  final MarketMonkBackupStorageLayout layout;
  final Map<String, File> profileDatabases;
  final File? unifiedDatabase;
}

/// Validated logical content and storage payload extracted from a backup.
class MarketMonkBackupContents {
  const MarketMonkBackupContents({
    required this.logical,
    required this.storage,
  });

  final MarketMonkLogicalBackup logical;
  final MarketMonkBackupStorage storage;
}

/// Builds a layout-independent Market Monk backup archive.
Future<File> buildMarketMonkBackupArchive({
  required Directory workingDirectory,
  required MarketMonkLogicalBackup logical,
  required MarketMonkBackupStorage storage,
}) async {
  _validateLogicalBackup(logical);
  await _validateStorageForExport(logical, storage);

  final archiveFile = File(
    p.join(workingDirectory.path, marketMonkBackupFileName),
  );
  final encoder = ZipFileEncoder()..create(archiveFile.path);

  try {
    final storageManifest = switch (storage.layout) {
      MarketMonkBackupStorageLayout.profileDatabases =>
        await _addProfileDatabases(encoder, logical, storage),
      MarketMonkBackupStorageLayout.unifiedDatabase =>
        await _addUnifiedDatabase(encoder, storage),
    };

    final manifest = utf8.encode(
      json.encode({
        'format': _backupFormat,
        'version': _backupVersion,
        'logical': {
          'profiles': logical.profiles,
          'activeProfile': logical.activeProfile,
          'settings': logical.settings,
        },
        'storage': storageManifest,
      }),
    );
    final manifestFile = File(p.join(workingDirectory.path, _manifestName));
    await manifestFile.writeAsBytes(manifest, flush: true);
    await encoder.addFile(manifestFile, _manifestName);
  } finally {
    await encoder.close();
  }

  return archiveFile;
}

Future<Map<String, Object?>> _addProfileDatabases(
  ZipFileEncoder encoder,
  MarketMonkLogicalBackup logical,
  MarketMonkBackupStorage storage,
) async {
  final profiles = <Map<String, Object?>>[];
  for (var index = 0; index < logical.profiles.length; index++) {
    final profile = logical.profiles[index];
    final archivePath = p.posix.join('payload', 'profiles', '$index.sqlite');
    await encoder.addFile(storage.profileDatabases[profile]!, archivePath);
    profiles.add({'name': profile, 'database': archivePath});
  }
  return {
    'layout': MarketMonkBackupStorageLayout.profileDatabases.wireName,
    'profiles': profiles,
  };
}

Future<Map<String, Object?>> _addUnifiedDatabase(
  ZipFileEncoder encoder,
  MarketMonkBackupStorage storage,
) async {
  const archivePath = 'payload/market-monk.sqlite';
  await encoder.addFile(storage.unifiedDatabase!, archivePath);
  return {
    'layout': MarketMonkBackupStorageLayout.unifiedDatabase.wireName,
    'database': archivePath,
  };
}

/// Extracts and validates current and legacy Market Monk backup archives.
Future<MarketMonkBackupContents> extractMarketMonkBackupArchive({
  required File archiveFile,
  required Directory workingDirectory,
}) async {
  final input = InputFileStream(archiveFile.path);
  final archive = ZipDecoder().decodeStream(input, verify: true);

  try {
    final manifestEntry = archive.find(_manifestName);
    if (manifestEntry == null || !manifestEntry.isFile) {
      throw const FormatException('Backup does not contain a manifest');
    }

    final decoded = json.decode(utf8.decode(manifestEntry.content));
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != _backupFormat ||
        decoded['version'] is! int) {
      throw const FormatException('Unsupported Market Monk backup');
    }

    final version = decoded['version'] as int;
    return await switch (version) {
      1 ||
      2 =>
        _extractLegacyBackup(decoded, archive, workingDirectory, version),
      _backupVersion => _extractCurrentBackup(
          decoded,
          archive,
          workingDirectory,
        ),
      _ => throw const FormatException('Unsupported Market Monk backup'),
    };
  } finally {
    for (final entry in archive) {
      await entry.close();
    }
    await input.close();
  }
}

Future<MarketMonkBackupContents> _extractCurrentBackup(
  Map<String, dynamic> decoded,
  Archive archive,
  Directory workingDirectory,
) async {
  final rawLogical = decoded['logical'];
  final rawStorage = decoded['storage'];
  if (rawLogical is! Map<String, dynamic> ||
      rawStorage is! Map<String, dynamic>) {
    throw const FormatException('Invalid Market Monk backup manifest');
  }

  final logical = _decodeLogicalBackup(rawLogical);
  final rawLayout = rawStorage['layout'];
  if (rawLayout is! String) {
    throw const FormatException('Invalid Market Monk backup storage metadata');
  }

  final layout = MarketMonkBackupStorageLayout.fromWireName(rawLayout);
  final storage = switch (layout) {
    MarketMonkBackupStorageLayout.profileDatabases =>
      await _extractProfileStorage(
        rawStorage,
        logical,
        archive,
        workingDirectory,
      ),
    MarketMonkBackupStorageLayout.unifiedDatabase =>
      await _extractUnifiedStorage(rawStorage, archive, workingDirectory),
  };

  return MarketMonkBackupContents(logical: logical, storage: storage);
}

Future<MarketMonkBackupContents> _extractLegacyBackup(
  Map<String, dynamic> decoded,
  Archive archive,
  Directory workingDirectory,
  int version,
) async {
  final rawProfiles = decoded['profiles'];
  final rawSettings = decoded[version == 1 ? 'preferences' : 'settings'];
  final activeProfile = decoded['activeAccount'];
  if (rawProfiles is! List ||
      rawSettings is! Map<String, dynamic> ||
      activeProfile is! String) {
    throw const FormatException('Invalid Market Monk backup manifest');
  }

  final profiles = <String>[];
  final databases = <String, File>{};
  for (var index = 0; index < rawProfiles.length; index++) {
    final rawProfile = rawProfiles[index];
    if (rawProfile is! Map<String, dynamic>) {
      throw const FormatException('Invalid profile metadata in backup');
    }
    final name = rawProfile['name'];
    final databasePath = rawProfile['database'];
    if (name is! String) {
      throw const FormatException('Invalid profile name in backup');
    }
    profiles.add(name);

    if (databasePath == null) continue;
    if (databasePath is! String ||
        databasePath != p.posix.join('databases', '$index.sqlite')) {
      throw const FormatException('Invalid profile database path in backup');
    }
    databases[name] = await _extractSqliteEntry(
      archive,
      databasePath,
      File(p.join(workingDirectory.path, 'legacy-$index.sqlite')),
      missingMessage: 'Backup is missing database for $name',
    );
  }

  final logical = MarketMonkLogicalBackup(
    profiles: profiles,
    activeProfile: activeProfile,
    settings: Map<String, Object?>.from(rawSettings),
  );
  _validateLogicalBackup(logical);

  return MarketMonkBackupContents(
    logical: logical,
    storage: MarketMonkBackupStorage.profileDatabases(databases),
  );
}

MarketMonkLogicalBackup _decodeLogicalBackup(Map<String, dynamic> raw) {
  final rawProfiles = raw['profiles'];
  final activeProfile = raw['activeProfile'];
  final rawSettings = raw['settings'];
  if (rawProfiles is! List ||
      activeProfile is! String ||
      rawSettings is! Map<String, dynamic>) {
    throw const FormatException('Invalid logical backup metadata');
  }
  final profiles = rawProfiles.whereType<String>().toList(growable: false);
  if (profiles.length != rawProfiles.length) {
    throw const FormatException('Invalid profile metadata in backup');
  }
  final logical = MarketMonkLogicalBackup(
    profiles: profiles,
    activeProfile: activeProfile,
    settings: Map<String, Object?>.from(rawSettings),
  );
  _validateLogicalBackup(logical);
  return logical;
}

Future<MarketMonkBackupStorage> _extractProfileStorage(
  Map<String, dynamic> rawStorage,
  MarketMonkLogicalBackup logical,
  Archive archive,
  Directory workingDirectory,
) async {
  final rawProfiles = rawStorage['profiles'];
  if (rawProfiles is! List || rawProfiles.length != logical.profiles.length) {
    throw const FormatException('Invalid profile storage metadata');
  }

  final databases = <String, File>{};
  for (var index = 0; index < rawProfiles.length; index++) {
    final rawProfile = rawProfiles[index];
    if (rawProfile is! Map<String, dynamic> ||
        rawProfile['name'] != logical.profiles[index]) {
      throw const FormatException('Invalid profile storage metadata');
    }
    final databasePath = rawProfile['database'];
    final expectedPath = p.posix.join('payload', 'profiles', '$index.sqlite');
    if (databasePath != expectedPath) {
      throw const FormatException('Invalid profile database path in backup');
    }
    final profile = logical.profiles[index];
    databases[profile] = await _extractSqliteEntry(
      archive,
      expectedPath,
      File(p.join(workingDirectory.path, 'profile-$index.sqlite')),
      missingMessage: 'Backup is missing database for $profile',
    );
  }
  return MarketMonkBackupStorage.profileDatabases(databases);
}

Future<MarketMonkBackupStorage> _extractUnifiedStorage(
  Map<String, dynamic> rawStorage,
  Archive archive,
  Directory workingDirectory,
) async {
  const expectedPath = 'payload/market-monk.sqlite';
  if (rawStorage['database'] != expectedPath) {
    throw const FormatException('Invalid unified database path in backup');
  }
  final database = await _extractSqliteEntry(
    archive,
    expectedPath,
    File(p.join(workingDirectory.path, 'unified.sqlite')),
    missingMessage: 'Backup is missing unified database',
  );
  return MarketMonkBackupStorage.unifiedDatabase(database);
}

Future<File> _extractSqliteEntry(
  Archive archive,
  String archivePath,
  File output, {
  required String missingMessage,
}) async {
  final entry = archive.find(archivePath);
  if (entry == null || !entry.isFile) {
    throw FormatException(missingMessage);
  }
  await output.writeAsBytes(entry.content, flush: true);
  await _validateSqliteFile(output);
  return output;
}

void _validateLogicalBackup(MarketMonkLogicalBackup logical) {
  if (logical.profiles.isEmpty ||
      !logical.profiles.contains('Default') ||
      !logical.profiles.contains(logical.activeProfile)) {
    throw const FormatException('Backup has invalid active profile metadata');
  }

  final seen = <String>{};
  for (final profile in logical.profiles) {
    if (profile.isEmpty ||
        profile.contains('/') ||
        profile.contains(r'\') ||
        !seen.add(profile)) {
      throw const FormatException('Invalid profile name in backup');
    }
  }
}

Future<void> _validateStorageForExport(
  MarketMonkLogicalBackup logical,
  MarketMonkBackupStorage storage,
) async {
  switch (storage.layout) {
    case MarketMonkBackupStorageLayout.profileDatabases:
      if (storage.profileDatabases.length != logical.profiles.length ||
          storage.profileDatabases.keys.any(
            (profile) => !logical.profiles.contains(profile),
          )) {
        throw const FormatException(
          'Profile database payload does not match logical profiles',
        );
      }
      for (final profile in logical.profiles) {
        final file = storage.profileDatabases[profile];
        if (file == null || !await file.exists()) {
          throw FormatException('Missing profile database for $profile');
        }
        await _validateSqliteFile(file);
      }
    case MarketMonkBackupStorageLayout.unifiedDatabase:
      final file = storage.unifiedDatabase;
      if (file == null || !await file.exists()) {
        throw const FormatException('Missing unified database');
      }
      await _validateSqliteFile(file);
  }
}

/// Validates the SQLite header used by legacy single-profile imports.
Future<void> validateMarketMonkSqliteFile(File file) =>
    _validateSqliteFile(file);

Future<void> _validateSqliteFile(File file) async {
  if (!await file.exists()) {
    throw const FormatException('Database file does not exist');
  }
  final handle = await file.open();
  try {
    final header = await handle.read(16);
    const sqliteMagic = <int>[
      0x53,
      0x51,
      0x4c,
      0x69,
      0x74,
      0x65,
      0x20,
      0x66,
      0x6f,
      0x72,
      0x6d,
      0x61,
      0x74,
      0x20,
      0x33,
      0x00,
    ];
    if (header.length != sqliteMagic.length) {
      throw const FormatException(
        'Selected file is not a valid SQLite database',
      );
    }
    for (var index = 0; index < sqliteMagic.length; index++) {
      if (header[index] != sqliteMagic[index]) {
        throw const FormatException(
          'Selected file is not a valid SQLite database',
        );
      }
    }
  } finally {
    await handle.close();
  }
}
