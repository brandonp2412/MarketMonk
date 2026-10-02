import 'dart:io';

import 'package:flutter/services.dart';

const _deviceRegionChannel = MethodChannel('market_monk/device_region');

Future<String?> detectDeviceRegionCurrency() async {
  if (!Platform.isAndroid) return null;
  return _deviceRegionChannel.invokeMethod<String>('getLocalCurrencyCode');
}
