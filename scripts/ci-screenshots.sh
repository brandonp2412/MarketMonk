#!/usr/bin/env bash

set -euo pipefail

: "${MARKET_MONK_DEVICE_TYPE:?MARKET_MONK_DEVICE_TYPE must be set}"
: "${EMULATOR_PORT:?EMULATOR_PORT must be set by android-emulator-runner}"

screenshot_dir="fastlane/metadata/android/en-US/images/$MARKET_MONK_DEVICE_TYPE"
rm -rf "$screenshot_dir"
mkdir -p "$screenshot_dir"

if [[ -n "${SCREENSHOT_SCREEN_SIZE:-}" ]]; then
  adb -s "emulator-$EMULATOR_PORT" shell wm size "$SCREENSHOT_SCREEN_SIZE"
  expected_dimensions="${SCREENSHOT_SCREEN_SIZE/x/ x }"
fi

run_screenshot_drive() {
  timeout --signal=INT --kill-after=30s 14m \
    flutter drive --profile \
      --driver=test_driver/integration_test.dart \
      --target=integration_test/screenshot_test.dart \
      -d "emulator-$EMULATOR_PORT"
}

if ! run_screenshot_drive; then
  echo "Screenshot drive failed or timed out; resetting the app and retrying once." >&2
  adb -s "emulator-$EMULATOR_PORT" shell am force-stop com.codesail.market_monk || true
  adb -s "emulator-$EMULATOR_PORT" shell pm clear com.codesail.market_monk || true
  adb -s "emulator-$EMULATOR_PORT" wait-for-device
  sleep 2
  run_screenshot_drive
fi

for number in 1 2 3 4 5 6; do
  screenshot="$screenshot_dir/${number}_en-US.png"
  if [[ ! -s "$screenshot" ]]; then
    echo "Missing generated screenshot: $screenshot" >&2
    exit 1
  fi
  if [[ -n "${SCREENSHOT_SCREEN_SIZE:-}" ]] && ! file "$screenshot" | grep -Fq " $expected_dimensions,"; then
    echo "Screenshot has unexpected dimensions: $(file "$screenshot")" >&2
    exit 1
  fi
done
