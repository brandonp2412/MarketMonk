import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (name, image, [args]) async {
      final deviceType = Platform.environment['MARKET_MONK_DEVICE_TYPE'];
      if (deviceType == null || deviceType.isEmpty) {
        throw 'MARKET_MONK_DEVICE_TYPE must be set so screenshots have a destination.';
      }

      final file = File(
        'fastlane/metadata/android/en-US/images/$deviceType/$name.png',
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(image);
      return true;
    },
    writeResponseOnFailure: true,
  );
}
