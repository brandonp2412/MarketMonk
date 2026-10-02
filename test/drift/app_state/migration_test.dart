import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/app_state_database.dart';
import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;

void main() {
  test('app-state v1 upgrade preserves profile order and typed settings',
      () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final verifier = SchemaVerifier(GeneratedHelper());
    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: AppStateDatabase.connect,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.appProfiles, [
          const v1.AppProfilesData(name: 'Default', sortOrder: 0),
          const v1.AppProfilesData(name: 'Brokerage', sortOrder: 1),
        ]);
        batch.insertAll(oldDb.appSettings, [
          const v1.AppSettingsData(
            key: 'pureBlack',
            valueType: 'bool',
            value: '1',
          ),
        ]);
      },
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.appProfiles).get(), [
          const v2.AppProfilesData(name: 'Default', sortOrder: 0),
          const v2.AppProfilesData(name: 'Brokerage', sortOrder: 1),
        ]);
        expect(await newDb.select(newDb.appSettings).get(), [
          const v2.AppSettingsData(
            key: 'pureBlack',
            valueType: 'bool',
            value: '1',
          ),
        ]);
      },
    );
  });
}
