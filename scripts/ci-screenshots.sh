#!/usr/bin/env bash

set -euo pipefail

: "${MARKET_MONK_DEVICE_TYPE:?MARKET_MONK_DEVICE_TYPE must be set}"
: "${EMULATOR_PORT:?EMULATOR_PORT must be set by android-emulator-runner}"

screenshot_dir="fastlane/metadata/android/en-US/images/$MARKET_MONK_DEVICE_TYPE"
rm -rf "$screenshot_dir"
mkdir -p "$screenshot_dir"

flutter drive --profile \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/screenshot_test.dart \
  -d "emulator-$EMULATOR_PORT"

for number in 1 2 3 4 5 6; do
  screenshot="$screenshot_dir/${number}_en-US.png"
  if [[ ! -s "$screenshot" ]]; then
    echo "Missing generated screenshot: $screenshot" >&2
    exit 1
  fi
done
