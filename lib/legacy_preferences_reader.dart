import 'package:shared_preferences/shared_preferences.dart';

/// Reads the pre-SQLite preferences store for one-time upgrade only.
///
/// This is the only production module allowed to touch SharedPreferences. It is
/// deliberately read-only and is invoked only while the SQLite migration
/// completion marker is absent. Remove this module and the dependency once upgrades from
/// pre-SQLite MarketMonk releases are no longer supported.
Future<Map<String, Object?>> readLegacyPreferences() async {
  final preferences = await SharedPreferences.getInstance();
  return {for (final key in preferences.getKeys()) key: preferences.get(key)};
}
