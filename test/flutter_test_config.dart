import 'dart:async';

import 'test_log_support.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  silenceTalkerForTest();
  await testMain();
}
