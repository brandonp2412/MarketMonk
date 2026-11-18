import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/temporal_currency_returns.dart';
import 'sqlite_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cached trade rates appear before a missing historical rate completes',
      () async {
    await seedTestSqlite({});
    final settings = await SqliteSettings.getInstance();
    final cachedDate = DateTime.utc(2026, 4, 13);
    final missingDate = DateTime.utc(2026, 5, 14);
    await settings.setDouble('historicalUsdRate_NZD_2026-04-13', 1.7);
    final updates = <Map<DateTime, double>>[];
    var fetches = 0;
    final rates = await loadTemporalRatesForDates(
      [cachedDate, missingDate],
      'NZD',
      onBatch: (rateBatch) => updates.add(rateBatch),
      rateLoader: (currency, date) async {
        fetches++;
        expect(currency, 'NZD');
        expect(date, missingDate);
        return 1.8;
      },
    );
    expect(fetches, 1);
    expect(updates.length, 2);
    expect(updates.first, {cachedDate: 1.7});
    expect(updates.last, {cachedDate: 1.7, missingDate: 1.8});
    expect(rates, updates.last);
  });

  test('cached dates remain usable when a remote rate fails', () async {
    await seedTestSqlite({});
    final settings = await SqliteSettings.getInstance();
    final cachedDate = DateTime.utc(2026, 4, 13);
    final missingDate = DateTime.utc(2026, 5, 14);
    await settings.setDouble('historicalUsdRate_NZD_2026-04-13', 1.7);
    final updates = <Map<DateTime, double>>[];
    final rates = await loadTemporalRatesForDates(
      [cachedDate, missingDate],
      'NZD',
      onBatch: (batch) => updates.add(batch),
      rateLoader: (_, __) async => throw StateError('offline'),
    );
    expect(rates, {cachedDate: 1.7});
    expect(updates.first, {cachedDate: 1.7});
  });
}
