#!/bin/zsh
# Builds build/Touchwire.app with Sparkle embedded, and signs it with the Developer ID Application identity of team
# GC28C3K5G9. VERSION and BUILD override Info.plist. SIGN_IDENTITY overrides the identity (a SHA-1 or a certificate
# name), for a Mac without the Developer ID; "-" signs ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/signing-identity.sh
SIGN_IDENTITY="${SIGN_IDENTITY:-$(find_developer_id_identity)}"
[[ -n "$SIGN_IDENTITY" ]] || {
    echo "✗ No Developer ID Application identity for team ${TEAM_ID} in the keychain. Set SIGN_IDENTITY to sign with another one." >&2
    exit 1
}
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

# Sign inside-out, Sparkle's helpers first, always with the hardened runtime. A Developer ID signature gets the secure
# timestamp that notarization needs (so it needs the network) and no entitlements, because Sparkle carries the same
# Team ID. Any other identity has no Team ID, so it needs the entitlement for the hardened runtime to load Sparkle.
SIGN=(--force --options runtime --sign "$SIGN_IDENTITY")
if is_developer_id_identity "$SIGN_IDENTITY"; then
    SIGN+=(--timestamp)
else
    SIGN+=(--entitlements Resources/Touchwire.entitlements)
fi
B="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for xpc in "$B/XPCServices/"*.xpc; do codesign "${SIGN[@]}" "$xpc"; done
codesign "${SIGN[@]}" "$B/Autoupdate" "$B/Updater.app" "$APP/Contents/Frameworks/Sparkle.framework"
codesign "${SIGN[@]}" "$APP"
codesign --verify --strict --deep "$APP"
echo "Built $APP (identity: $SIGN_IDENTITY)"
