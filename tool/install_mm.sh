#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
install_dir="${MM_INSTALL_DIR:-$HOME/.local/bin}"
prefix="$(dirname -- "$install_dir")"
bundle_dir="$prefix/lib/market-monk-cli"
target="$install_dir/mm"
build_root="$(mktemp -d "${TMPDIR:-/tmp}/market-monk-cli.XXXXXX")"
package_root="$build_root/package"
trap 'rm -rf "$build_root"' EXIT INT TERM

if ! command -v dart >/dev/null 2>&1; then
  echo "Dart is required to build mm. Install Dart or Flutter first." >&2
  exit 1
fi

mkdir -p "$package_root/bin" "$package_root/lib" "$install_dir" "$prefix/lib"

cp "$repo_root/tool/src/market_monk_cli.dart" "$package_root/lib/market_monk_cli.dart"
cat > "$package_root/pubspec.yaml" <<'EOF'
name: market_monk_cli_build
publish_to: none
environment:
  sdk: ^3.5.4
dependencies:
  path: 1.9.1
  sqlite3: 3.5.0
EOF
cat > "$package_root/bin/mm.dart" <<'EOF'
import 'dart:io';

import '../lib/market_monk_cli.dart';

void main(List<String> arguments) {
  exitCode = MarketMonkCli().run(arguments);
}
EOF

(
  cd "$package_root"
  dart pub get
  dart build cli --target bin/mm.dart --output "$build_root/build"
)

rm -rf "$bundle_dir.new"
cp -R "$build_root/build/bundle" "$bundle_dir.new"
rm -rf "$bundle_dir"
mv "$bundle_dir.new" "$bundle_dir"

ln -sfn "../lib/market-monk-cli/bin/mm" "$target"

case ":${PATH:-}:" in
  *":$install_dir:"*) ;;
  *)
    echo
    echo "Installed mm to $target, but $install_dir is not currently in PATH."
    echo "Add it to your shell startup file, for example:"
    echo "  export PATH=\"$install_dir:\$PATH\""
    exit 2
    ;;
esac

echo
echo "Installed mm to $target"
"$target" --help >/dev/null
echo "Verified: mm is executable, its SQLite runtime is bundled, and it is on PATH."
