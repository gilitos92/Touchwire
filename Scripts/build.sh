#!/bin/zsh
# Builds build/Touchwire.app and signs it with the stable self-signed identity.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/Touchwire.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/Touchwire" "$APP/Contents/MacOS/Touchwire"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --options runtime --sign "GGV" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
