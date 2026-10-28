#!/usr/bin/env bash
set -euox pipefail
cd "$(dirname "$0")/.."
export MARKET_MONK_WATCH_ROOT="$PWD"
find lib -type f -name '*.dart' | entr -s '
  for pid in $(pgrep -f "[f]lutter_tools.snapshot run" || true); do
    if [ "$(readlink "/proc/$pid/cwd")" = "$MARKET_MONK_WATCH_ROOT" ]; then
      kill -SIGUSR1 "$pid"
    fi
  done
' &
watcher_pid=$!
trap 'kill "$watcher_pid" 2>/dev/null || true' EXIT
${TERMINAL:?Set TERMINAL to your terminal command} -c noswallow ./flutter/bin/flutter run "$@"
