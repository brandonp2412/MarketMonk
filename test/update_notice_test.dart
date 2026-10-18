import 'package:market_monk/update_notice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only upgrades can trigger an update snackbar', () {
    expect(
      shouldShowUpdateNotice(
        previousBuild: null,
        currentBuild: 2,
        lastShownAtMs: null,
        nowMs: 100,
      ),
      isFalse,
    );
    expect(
      shouldShowUpdateNotice(
        previousBuild: 2,
        currentBuild: 2,
        lastShownAtMs: null,
        nowMs: 100,
      ),
      isFalse,
    );
    expect(
      shouldShowUpdateNotice(
        previousBuild: 3,
        currentBuild: 2,
        lastShownAtMs: null,
        nowMs: 100,
      ),
      isFalse,
    );
    expect(
      shouldShowUpdateNotice(
        previousBuild: 1,
        currentBuild: 2,
        lastShownAtMs: null,
        nowMs: 100,
      ),
      isTrue,
    );
  });

  test('update notices are limited to one per 14 days, even across versions',
      () {
    const start = 1000000000000;
    expect(
      shouldShowUpdateNotice(
        previousBuild: 1,
        currentBuild: 2,
        lastShownAtMs: start,
        nowMs: start + updateNoticeIntervalMs - 1,
      ),
      isFalse,
    );
    expect(
      shouldShowUpdateNotice(
        previousBuild: 2,
        currentBuild: 3,
        lastShownAtMs: start,
        nowMs: start + updateNoticeIntervalMs,
      ),
      isTrue,
    );
    expect(
      shouldShowUpdateNotice(
        previousBuild: 2,
        currentBuild: 3,
        lastShownAtMs: start,
        nowMs: start - 1,
      ),
      isFalse,
    );
  });
}
