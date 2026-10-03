# Persistence

SQLite is the authoritative store for all application state:

- `market-monk.settings.sqlite`: ordered profiles, active profile, typed settings,
  favorites, chart period, exchange rates, symbol metadata and IBKR history flags.
- `market-monk.sqlite` and `market-monk-<profile>.sqlite`: trades, candles,
  IBKR connection settings, portfolio snapshots and performance caches.

The settings filename cannot collide with a named profile's database. JSON
payloads inside SQLite cache rows are serialization, not separate storage files.

Startup awaits `SqliteSettings.getInstance()` before constructing state owners.
On the first upgrade it imports legacy SharedPreferences into SQLite. The
`sqliteMigrationCompleteV1` setting is written only after all profiles succeed.
An interrupted import can retry without overwriting committed SQLite values.
After completion, startup never initializes or reads SharedPreferences again,
so deleted settings and profiles cannot return from stale legacy data. The only
production import of that package is `legacy_preferences_reader.dart`, a
read-only upgrade adapter. Legacy preferences remain intact as a recovery
source; no runtime owner writes to them.

Invalid cache JSON is discarded because it can be fetched again. Invalid
connection JSON fails the import without marking it complete or deleting the
source. Database errors likewise leave the import retryable.

Full backups use archive version 2. They contain consistent SQLite snapshots of
each profile (including committed WAL data) and a portable settings snapshot in
the JSON manifest. The global database is restored logically through a SQLite
transaction, not deleted with profile files. Version 1 archives remain readable;
their preference manifest is imported directly into SQLite. Restore errors roll
back profile files and global settings. A single-profile SQLite import reloads
that profile's credentials and caches as well as its trades.

SharedPreferences remains a dependency solely for upgrading existing installs.
It cannot yet be removed safely because released Android, Linux and Windows
builds use platform-specific legacy preference backends; replacing the plugin
with bespoke readers would risk silently missing upgrade data. Once upgrades
from pre-SQLite releases are no longer supported, remove the dependency and
`legacy_preferences_reader.dart` together.

The obsolete `market-monk-app-state.sqlite` is deleted only after both the old
app-state import and SharedPreferences import have committed. Cleanup has its
own completion marker, removes SQLite sidecars, and retries on a later startup
if deletion fails. A failed import never deletes the source database.

The SQLite migration, restart, profile lifecycle, backup compatibility, WAL and
rollback regression tests are in `test/sqlite_cutover_test.dart`.
