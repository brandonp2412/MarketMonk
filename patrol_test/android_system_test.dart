import 'dart:io';

import 'package:flutter/material.dart';
import 'package:market_monk/main.dart' as app;
import 'package:patrol/patrol.dart';

const _uiTimeout = Duration(seconds: 15);
const _nativeTimeout = Duration(seconds: 15);

Future<void> openSettings(PatrolIntegrationTester $) async {
  app.main();
  await $(Icons.settings).waitUntilVisible(timeout: _uiTimeout).tap();
  await $('Settings').waitUntilVisible(timeout: _uiTimeout);
}

void main() {
  patrolTest('Android CSV import opens the system document picker', ($) async {
    if (!Platform.isAndroid) return;

    await openSettings($);
    await $('Import CSV').waitUntilVisible(timeout: _uiTimeout).tap();
    await $('Continue').waitUntilVisible(timeout: _uiTimeout).tap();

    await $.platform.android.waitUntilVisible(
      const AndroidSelector(text: 'Recent'),
      timeout: _nativeTimeout,
    );
    await $.platform.android.pressBack();
    await $('Import CSV').waitUntilVisible(timeout: _uiTimeout);
  });

  patrolTest('Android database export opens the system save picker', ($) async {
    if (!Platform.isAndroid) return;

    await openSettings($);
    await $('Export database').waitUntilVisible(timeout: _uiTimeout).tap();

    await $.platform.android.waitUntilVisible(
      const AndroidSelector(text: 'Recent'),
      timeout: _nativeTimeout,
    );
    await $.platform.android.pressBack();
    await $('Settings').waitUntilVisible(timeout: _uiTimeout);
  });
}
