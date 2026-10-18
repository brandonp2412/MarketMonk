const updateNoticeIntervalMs = 14 * 24 * 60 * 60 * 1000;

bool shouldShowUpdateNotice({
  required int? previousBuild,
  required int currentBuild,
  required int? lastShownAtMs,
  required int nowMs,
}) =>
    previousBuild != null &&
    currentBuild > previousBuild &&
    (lastShownAtMs == null ||
        (nowMs - lastShownAtMs >= updateNoticeIntervalMs));
