import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/logging.dart';
import 'package:talker_flutter/talker_flutter.dart';

/// Silences Talker's console sink in a test isolate while preserving history.
void silenceTalkerForTest() {
  talker.configure(
    logger: TalkerLogger(
      settings: TalkerLoggerSettings(enable: false),
      formatter: const TerminalResponsiveLoggerFormatter(),
    ),
  );
}

/// Allows tests that intentionally keep multiple Drift clients open at once.
void allowMultipleDriftDatabasesForTest() {
  final previous = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  addTearDown(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = previous;
  });
}
