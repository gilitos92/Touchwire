#!/bin/zsh
# Builds build/Touchwire.app with Sparkle embedded, and signs it with the stable self-signed identity.
# VERSION and BUILD override Info.plist.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/Touchwire.app
EXECUTABLE="$APP/Contents/MacOS/Touchwire"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Touchwire" "$EXECUTABLE"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Release builds stamp the version and build number; development builds keep Info.plist's values.
[[ -n "${VERSION:-}" ]] && /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
[[ -n "${BUILD:-}" ]] && /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"

# Compiles the Icon Composer icon (actool needs absolute paths): Assets.car for macOS 26's Liquid Glass rendering, and Touchwire.icns as a fallback.
xcrun actool "$PWD/Resources/Touchwire.icon" --compile "$PWD/$APP/Contents/Resources" --app-icon Touchwire --platform macosx \
    --minimum-deployment-target 26.0 --output-partial-info-plist "$PWD/build/icon-info.plist" > /dev/null

# SwiftPM links Sparkle through @rpath but doesn't bundle it.
SPARKLE=$(find .build/artifacts/sparkle -type d -name Sparkle.framework -path '*macos*' | head -1)
[[ -n "$SPARKLE" ]] || { echo "✗ Sparkle.framework not found in .build/artifacts" >&2; exit 1; }
cp -R "$SPARKLE" "$APP/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$EXECUTABLE" 2>/dev/null || true

# Sign inside-out, Sparkle's helpers first. The entitlement lets the hardened runtime load Sparkle without a Team ID.
SIGN=(--force --options runtime --sign "GGV" --entitlements Resources/Touchwire.entitlements)
B="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for xpc in "$B/XPCServices/"*.xpc; do codesign "${SIGN[@]}" "$xpc"; done
codesign "${SIGN[@]}" "$B/Autoupdate" "$B/Updater.app" "$APP/Contents/Frameworks/Sparkle.framework"
codesign "${SIGN[@]}" "$APP"
codesign --verify --strict --deep "$APP"
echo "Built $APP"
