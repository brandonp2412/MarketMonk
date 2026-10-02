import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// File name used for full Market Monk backup archives.
const marketMonkBackupFileName = 'market-monk-backup.zip';
const _manifestName = 'manifest.json';
const _backupFormat = 'market-monk-backup';
const _backupVersion = 2;

/// Returns the SQLite file name used by an account on disk.
String databaseFileNameForAccount(String account) =>
    account == 'Default' ? 'market-monk.sqlite' : 'market-monk-$account.sqlite';

/// Validated contents extracted from a full Market Monk backup.
class MarketMonkBackupContents {
  const MarketMonkBackupContents({
    required this.accounts,
    required this.activeAccount,
    required this.settings,
    required this.databases,
  });

  /// Profile names present in the backup.
  final List<String> accounts;

  /// Profile that should be active after restore.
  final String activeAccount;

  /// Application settings read from SQLite, encoded for portable restore.
  final Map<String, Object?> settings;

  /// Extracted profile databases keyed by profile name.
  final Map<String, File> databases;
}

/// Builds a ZIP containing all profile databases and a portable snapshot of SQLite settings.
Future<File> buildMarketMonkBackupArchive({
  required Directory databaseDirectory,
  required Directory workingDirectory,
  required List<String> accounts,
  required String activeAccount,
  required Map<String, Object?> settings,
}) async {
  final profiles = <Map<String, Object?>>[];
  final archiveFile =
      File(p.join(workingDirectory.path, marketMonkBackupFileName));
  final encoder = ZipFileEncoder()..create(archiveFile.path);

  try {
    for (var index = 0; index < accounts.length; index++) {
      final account = accounts[index];
      final databaseFile = File(
        p.join(databaseDirectory.path, databaseFileNameForAccount(account)),
      );
      String? archivePath;
      if (await databaseFile.exists()) {
        archivePath = p.posix.join('databases', '$index.sqlite');
        await encoder.addFile(databaseFile, archivePath);
      }
      profiles.add({'name': account, 'database': archivePath});
    }

    final manifest = utf8.encode(
      json.encode({
        'format': _backupFormat,
        'version': _backupVersion,
        'activeAccount': activeAccount,
        'profiles': profiles,
        'settings': settings,
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

/// Extracts and validates a full Market Monk backup into [workingDirectory].
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
        ![1, _backupVersion].contains(decoded['version'])) {
      throw const FormatException('Unsupported Market Monk backup');
    }

    final rawProfiles = decoded['profiles'];
    final rawPreferences =
        decoded[decoded['version'] == 1 ? 'preferences' : 'settings'];
    final activeAccount = decoded['activeAccount'];
    if (rawProfiles is! List ||
        rawPreferences is! Map<String, dynamic> ||
        activeAccount is! String) {
      throw const FormatException('Invalid Market Monk backup manifest');
    }

    final accounts = <String>[];
    final databases = <String, File>{};
    for (var index = 0; index < rawProfiles.length; index++) {
      final rawProfile = rawProfiles[index];
      if (rawProfile is! Map<String, dynamic>) {
        throw const FormatException('Invalid profile metadata in backup');
      }
      final name = rawProfile['name'];
      final databasePath = rawProfile['database'];
      if (name is! String ||
          name.isEmpty ||
          name.contains('/') ||
          name.contains(r'\') ||
          accounts.contains(name)) {
        throw const FormatException('Invalid profile name in backup');
      }
      accounts.add(name);

      if (databasePath == null) continue;
      if (databasePath is! String ||
          databasePath != p.posix.join('databases', '$index.sqlite')) {
        throw const FormatException('Invalid profile database path in backup');
      }
      final entry = archive.find(databasePath);
      if (entry == null || !entry.isFile) {
        throw FormatException('Backup is missing database for $name');
      }

      final output = File(p.join(workingDirectory.path, '$index.sqlite'));
      await output.writeAsBytes(entry.content, flush: true);
      await _validateSqliteFile(output);
      databases[name] = output;
    }

    if (!accounts.contains('Default') || !accounts.contains(activeAccount)) {
      throw const FormatException('Backup has invalid active profile metadata');
    }

    return MarketMonkBackupContents(
      accounts: accounts,
      activeAccount: activeAccount,
      settings: Map<String, Object?>.from(rawPreferences),
      databases: databases,
    );
  } finally {
    for (final entry in archive) {
      await entry.close();
    }
    await input.close();
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
