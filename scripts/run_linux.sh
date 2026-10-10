#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
exec ./flutter/bin/flutter run -d linux "$@"
