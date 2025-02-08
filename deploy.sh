#!/bin/bash

set -ex
export PUB_SUMMARY_ONLY=true

###########################################
# Version Management 🔢
###########################################

IFS='+.' read -r major minor patch build_number <<<"$(yq -r .version pubspec.yaml)"
new_patch=$((patch + 1))
new_build_number=$((build_number + 1))
changelog_number=$((new_build_number * 10 + 3))
new_flutter_version="$major.$minor.$new_patch+$new_build_number"
new_version="$major.$minor.$new_patch"
apk=$PWD/build/app/outputs/flutter-apk

IFS='+.' read -r msix_major msix_minor msix_patch msix_zero <<<"$(yq -r .msix_config.msix_version pubspec.yaml)"
new_msix_patch=$((msix_patch + 1))
new_msix_version="$msix_major.$msix_minor.$new_msix_patch.$msix_zero"

###########################################
# Changelog Management ✍️
###########################################

changelog_file="fastlane/metadata/android/en-US/changelogs/$changelog_number.txt"

if ! [ -f $changelog_file ]; then
    git --no-pager log --pretty=format:'%s' "$(git describe --tags --abbrev=0)"..HEAD |
        awk '{print "- "$0}' >$changelog_file
fi

nvim "$changelog_file"
if ! [ -f "$changelog_file" ]; then
    echo "No changelog was specified."
    exit 0
fi

changelog=$(cat "$changelog_file")
echo "$changelog" >"$changelog_file"
echo "$changelog" >fastlane/metadata/en-US/release_notes.txt

###########################################
# Testing and Analysis 🧪
###########################################

if [[ $* == *-t* ]]; then
    echo "Skipping tests..."
else
    dart analyze lib
    dart format --set-exit-if-changed lib
    dart run build_runner build -d
    dart run drift_dev make-migrations
    #./scripts/screenshots.sh "phoneScreenshots"
    #./scripts/screenshots.sh "sevenInchScreenshots"
    #./scripts/screenshots.sh "tenInchScreenshots"
fi

###########################################
# Version Update and Commit 📦
###########################################

yq -yi ".version |= \"$new_flutter_version\"" pubspec.yaml
yq -yi ".msix_config.msix_version |= \"$new_msix_version\"" pubspec.yaml
git add pubspec.yaml fastlane/metadata
git commit -m "$new_version 🚀
$changelog"

###########################################
# Build and Package 🛠️
###########################################

flutter build apk --split-per-abi
adb -d install "$apk"/app-arm64-v8a-release.apk || true
flutter build apk
mv "$apk"/app-release.apk "$apk/market_monk.apk"
flutter build appbundle

mkdir -p build/native_assets/linux
flutter build linux
(cd "$apk/pipeline/linux/x64/release/bundle" && zip --quiet -r "market_monk-linux.zip" .)

###########################################
# Windows Build 🪟
###########################################

docker start windows
rsync -a --delete --exclude-from=.gitignore --exclude ./flutter ./* .gitignore \
    "$HOME/windows/market_monk-source"

while ! ssh windows exit; do sleep 1; done
ssh windows 'Powershell -ExecutionPolicy bypass -File //host.lan/Data/build-market-monk.ps1'

sudo chown -R "$USER" "$HOME/windows/market_monk"
mv "$HOME/windows/market_monk/market_monk.msix" "$HOME/windows/market_monk.msix"
(cd "$HOME/windows/market_monk" && zip --quiet -r "$HOME/windows/market_monk-windows.zip" .)
docker stop windows

###########################################
# Release and Distribution 🚀
###########################################

git push
gh release create "$new_version" --notes "$changelog" \
    "$apk"/app-*-release.apk \
    "$apk/pipeline/linux/x64/release/bundle/market_monk-linux.zip" \
    "$apk/market_monk.apk" \
    "$HOME/windows/market_monk-windows.zip"
git pull

if [[ $* == *-w* ]]; then
    echo "Skipping Windows store..."
else
  client_id=$(yq -r .clientId "$HOME/.config/msstore.yml")
  client_secret=$(yq -r .clientSecret "$HOME/.config/msstore.yml")
  tenant_id=$(yq -r .tenantId "$HOME/.config/msstore.yml")
  api="https://manage.devcenter.microsoft.com"

  access_token=$(curl -X POST "https://login.microsoftonline.com/$tenant_id/oauth2/token" \
    -H "Content-Type: application/x-www-form-urlencoded; charset=utf-8" \
    -d "grant_type=client_credentials" \
    -d "client_id=$client_id" \
    -d "client_secret=$client_secret" \
    -d "resource=$api" | jq -r .access_token)

  app_id=$(yq -r .msix_config.msstore_appId pubspec.yaml)

  submission_response=$(curl -X POST "$api/v1.0/my/applications/$app_id/submissions" \
    -H "Authorization: Bearer $access_token" \
    -H "Content-Type: application/json" \
    -H "Content-Length: 0")
  submission_id=$(echo "$submission_response" | jq -r .id)
  file_upload_url=$(echo "$submission_response" | jq -r .fileUploadUrl)

  if [ "$submission_id" = "null" ]; then
    echo "Submission failed to create"
    exit 1
  fi

  curl -X PUT "$file_upload_url" \
    -H "Content-Type: application/octet-stream" \
    -H "x-ms-blob-type: BlockBlob" \
    --data-binary "$HOME/windows/market_monk.msix"

  curl -X POST "$api/v1.0/my/applications/$app_id/submissions/$submission_id/commit" \
    -H "Authorization: Bearer $access_token" \
    -H "Content-Type: application/json" \
    -H "Content-Length: 0"
fi

if [[ $* == *-p* ]]; then
    echo "Skipping Google play..."
else
    bundle exec fastlane supply --aab \
        build/app/outputs/bundle/release/app-release.aab || true
fi

if [[ $* == *-m* ]]; then
    echo "Skipping MacOS..."
else
    set +x
    ip=$(arp | grep "$MACBOOK_MAC" | cut -d ' ' -f 1)
    # shellcheck disable=SC2029
    ssh "$ip" "security unlock-keychain -p '$(pass macbook)' && cd market_monk && git pull && ./scripts/macos.sh"
fi
