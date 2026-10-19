#!/bin/zsh
# Builds build/Touchwire.app and signs it with the stable self-signed identity. VERSION and BUILD override Info.plist.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/Touchwire.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/Touchwire" "$APP/Contents/MacOS/Touchwire"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Release builds stamp the version and build number; development builds keep Info.plist's values.
[[ -n "${VERSION:-}" ]] && /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
[[ -n "${BUILD:-}" ]] && /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
codesign --force --options runtime --sign "GGV" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
