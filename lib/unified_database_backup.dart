import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:market_monk/database.dart';

/// Creates a consistent snapshot of the unified database.
Future<File> snapshotUnifiedDatabase(
  Database database,
  File destination,
) async {
  if (await destination.exists()) await destination.delete();
  await database.customStatement('VACUUM INTO ?', [destination.path]);
  return destination;
}

/// Restores all unified tables within a single transaction while keeping the
/// live Drift executor open. A failed restore cannot partially replace data.
Future<void> restoreUnifiedDatabase(
  Database destination,
  File sourceFile, {
  required List<String> expectedProfiles,
  required String expectedActiveProfile,
}) async {
  final source = Database.connect(NativeDatabase(sourceFile));
  try {
    final quickCheck = await source.customSelect('PRAGMA quick_check').get();
    if (quickCheck.length != 1 ||
        quickCheck.single.read<String>('quick_check') != 'ok') {
      throw const FormatException('Backup SQLite integrity check failed');
    }
    await source.validateSchema();
    final profiles = await source.readProfiles();
    if (profiles.map((profile) => profile.name).join('\u0000') !=
            expectedProfiles.join('\u0000') ||
        await source.readActiveProfile() != expectedActiveProfile) {
      throw const FormatException(
        'Backup manifest does not match SQLite profiles',
      );
    }

    await destination.transaction(() async {
      await destination.delete(destination.trades).go();
      await destination.delete(destination.ibkrCacheEntries).go();
      await destination.delete(destination.ibkrSettings).go();
      await destination.delete(destination.appState).go();
      await destination.delete(destination.profiles).go();
      await destination.delete(destination.appSettings).go();
      await destination.delete(destination.candles).go();
      await destination.delete(destination.symbolMetadata).go();

      final settings = await source.select(source.appSettings).get();
      final state = await source.select(source.appState).get();
      final trades = await source.select(source.trades).get();
      final ibkrSettings = await source.select(source.ibkrSettings).get();
      final ibkrCaches = await source.select(source.ibkrCacheEntries).get();
      final metadata = await source.select(source.symbolMetadata).get();
      await destination.batch((batch) {
        batch.insertAll(
          destination.profiles,
          profiles.map((row) => row.toCompanion(true)).toList(),
        );
        batch.insertAll(
          destination.appSettings,
          settings.map((row) => row.toCompanion(true)).toList(),
        );
        batch.insertAll(
          destination.appState,
          state.map((row) => row.toCompanion(true)).toList(),
        );
        batch.insertAll(
          destination.trades,
          trades.map((row) => row.toCompanion(true)).toList(),
        );
        batch.insertAll(
          destination.ibkrSettings,
          ibkrSettings.map((row) => row.toCompanion(true)).toList(),
        );
        batch.insertAll(
          destination.ibkrCacheEntries,
          ibkrCaches.map((row) => row.toCompanion(true)).toList(),
        );
        batch.insertAll(
          destination.symbolMetadata,
          metadata.map((row) => row.toCompanion(true)).toList(),
        );
      });

      // Limit candle allocations on users with years of historical prices.
      const pageSize = 1000;
      for (var offset = 0;; offset += pageSize) {
        final rows = await (source.select(source.candles)
              ..orderBy([
                (row) => OrderingTerm.asc(row.symbol),
                (row) => OrderingTerm.asc(row.date),
              ])
              ..limit(pageSize, offset: offset))
            .get();
        if (rows.isEmpty) break;
        await destination.batch((batch) {
          batch.insertAll(
            destination.candles,
            rows.map((row) => row.toCompanion(true)).toList(),
          );
        });
      }
      await destination.writeSetting(Database.legacyMigrationCompleteKey, true);
      await destination.writeSetting('sqliteMigrationCompleteV1', true);
      await destination.writeSetting('legacyAppStateMigrationCompleteV1', true);
    });
  } finally {
    await source.close();
  }
}
