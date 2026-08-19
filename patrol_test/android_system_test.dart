import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/main.dart' as app;
import 'package:patrol/patrol.dart';

Future<void> openSettings(PatrolIntegrationTester $) async {
  app.main();
  await $.pumpAndSettle();
  await $(Icons.settings).tap();
  await $.pumpAndSettle();
}

void main() {
  patrolTest(
    'Android CSV import opens the system document picker',
    ($) async {
      if (!Platform.isAndroid) return;

      await openSettings($);
      await $('Import CSV').tap();
      await $('Continue').tap();

      // FilePicker hands control to Android DocumentsUI. The app must not
      // fake this interaction: verify that the real system picker appears.
      await $.platform.android.waitUntilVisible(
        const AndroidSelector(text: 'Recent'),
        timeout: const Duration(seconds: 10),
      );
      await $.platform.android.pressBack();
      await $.pumpAndSettle();
      expect($('Import CSV').exists, isTrue);
    },
  );

  patrolTest(
    'Android database export opens the system save picker',
    ($) async {
      if (!Platform.isAndroid) return;

      await openSettings($);
      await $('Export database').tap();

      // FilePicker.saveFile also launches DocumentsUI, this time in create
      // mode. Checking the native toolbar confirms the Android hand-off.
      await $.platform.android.waitUntilVisible(
        const AndroidSelector(text: 'Recent'),
        timeout: const Duration(seconds: 10),
      );
      await $.platform.android.pressBack();
      await $.pumpAndSettle();
      expect($(Icons.settings).exists, isTrue);
    },
  );
}
