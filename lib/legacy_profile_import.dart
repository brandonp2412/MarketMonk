import 'package:market_monk/database.dart';
import 'package:market_monk/legacy_profile_database.dart' as legacy;

/// Imports a standalone pre-unification profile into the live unified store.
/// Other profiles, global settings and unrelated candle symbols are preserved.
Future<void> importLegacyProfile(
  Database destination,
  legacy.LegacyProfileDatabase source,
  String profileId,
) async {
  final integrity = await source.customSelect('PRAGMA quick_check').get();
  if (integrity.length != 1 ||
      integrity.single.read<String>('quick_check') != 'ok') {
    throw const FormatException('Profile SQLite integrity check failed');
  }
  final trades = await source.select(source.trades).get();
  final settings = await source.readIbkrProfileSettings();
  final caches = await source.select(source.ibkrCacheEntries).get();
  final candles = await source.select(source.candles).get();
  await destination.transaction(() async {
    await destination.clearTrades(profileId);
    await destination.deleteIbkrCache(profileId);
    await destination.deleteIbkrSettings(profileId);
    for (final trade in trades) {
      await destination.addTrade(
        profileId: profileId,
        symbol: trade.symbol,
        name: trade.name,
        quantity: trade.quantity,
        price: trade.price,
        tradeType: trade.tradeType,
        tradeDate: trade.tradeDate,
        realizedPL: trade.realizedPL,
        commission: trade.commission,
      );
    }
    if (settings != null) {
      await destination.writeIbkrSettings(
        profileId: profileId,
        enabled: settings.enabled,
        baseUrl: settings.baseUrl,
        token: settings.token,
      );
    }
    for (final cache in caches) {
      await destination.writeIbkrCache(
        profileId: profileId,
        kind: cache.kind,
        cacheKey: cache.cacheKey,
        payloadJson: cache.payloadJson,
        cachedAt: cache.cachedAt,
      );
    }
    for (final candle in candles) {
      final utc = candle.date.toUtc();
      await destination.upsertCandle(
        symbol: candle.symbol.trim().toUpperCase(),
        date: DateTime.utc(utc.year, utc.month, utc.day),
        open: candle.open,
        high: candle.high,
        low: candle.low,
        close: candle.close,
        volume: candle.volume,
        adjClose: candle.adjClose,
      );
    }
  });
}
