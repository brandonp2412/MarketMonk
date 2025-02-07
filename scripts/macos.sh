#!/bin/sh

source $HOME/.zprofile

set -ex

flutter build macos --release
APP_NAME="build/macos/Build/Products/Release/market_monk.app"
PACKAGE_NAME=build/macos/MarketMonk.pkg
xcrun productbuild --component "$APP_NAME" /Applications/ build/macos/unsigned.pkg
INSTALLER_CERT_NAME=$(keychain list-certificates |
  jq '[.[]
            | select(.common_name
            | contains("Mac Developer Installer"))
            | .common_name][0]' |
  xargs)
xcrun productsign --sign "$INSTALLER_CERT_NAME" build/macos/unsigned.pkg "$PACKAGE_NAME"
rm -f build/macos/unsigned.pkg

fastlane deliver --pkg $PACKAGE_NAME || true
flutter build ipa
fastlane deliver --ipa "build/ios/ipa/Market Monk - By CodeSail.ipa"
