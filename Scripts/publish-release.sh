#!/bin/zsh
# Builds the tagged version, signs it with Developer ID, has Apple notarize it, and publishes it as a GitHub release
# with a stapled zip and DMG, plus the Sparkle appcast.xml that installed copies check for updates. The appcast is
# signed with the EdDSA key stored in the login keychain under the account "Touchwire" (Sparkle's generate_keys
# created it). Never change that key together with the signing certificate: Sparkle accepts an update when either
# the EdDSA signature or the code signature matches the installed app.
#
# Notarization uses a notarytool keychain profile (made from an App Store Connect API key with the Developer role),
# named by NOTARY_PROFILE in the environment or in ~/.config/touchwire/release.env, outside the repo:
#   xcrun notarytool store-credentials <profile> --key <api-key>.p8 --key-id <key-id> --issuer <issuer-id>
#   mkdir -p ~/.config/touchwire && echo 'NOTARY_PROFILE=<profile>' > ~/.config/touchwire/release.env
# Usage: publish-release.sh [version]   (defaults to Info.plist's CFBundleShortVersionString)
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/signing-identity.sh

REPO="gilitos92/Touchwire"
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"
TAG="v${VERSION}"

fail() { echo "✗ $1" >&2; exit 1; }

RELEASE_ENV=~/.config/touchwire/release.env
if [[ -z "${NOTARY_PROFILE:-}" && -f "$RELEASE_ENV" ]]; then
    NOTARY_PROFILE="$(sed -n 's/^NOTARY_PROFILE=//p' "$RELEASE_ENV" | tail -1)"
fi
[[ -n "${NOTARY_PROFILE:-}" ]] || fail "Set NOTARY_PROFILE (a notarytool keychain profile) or add it to ${RELEASE_ENV}."
SIGN_IDENTITY="$(find_developer_id_identity)"
[[ -n "$SIGN_IDENTITY" ]] || fail "No Developer ID Application identity for team ${TEAM_ID} in the keychain."

COMMIT="$(git rev-parse -q --verify "${TAG}^{commit}")" || fail "No tag ${TAG}."
git ls-remote --exit-code --tags origin "refs/tags/${TAG}" > /dev/null || fail "Push ${TAG} first."
! gh release view "$TAG" --repo "$REPO" > /dev/null 2>&1 || fail "$TAG is already published."
# Checked before the build, so a missing or expired profile fails in seconds instead of after it.
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" > /dev/null 2>&1 \
    || fail "The notarytool profile \"${NOTARY_PROFILE}\" doesn't work. Run notarytool store-credentials again."
BUILD="$(git rev-list --count "$COMMIT")"

OUT="$(mktemp -d)"
SRC="$OUT/src"
cleanup() {
    git worktree remove --force "$SRC" 2> /dev/null || true
    rm -rf "$OUT"
}
trap cleanup EXIT
# Build from the tag, not the working tree.
git worktree add -q --detach "$SRC" "$COMMIT"

echo "▸ Building Touchwire ${VERSION} (${BUILD}) from ${TAG}"
SIGN_IDENTITY="$SIGN_IDENTITY" VERSION="$VERSION" BUILD="$BUILD" "$SRC/Scripts/build.sh" > /dev/null
APP="$SRC/build/Touchwire.app"
codesign --verify --strict --deep "$APP"
# Captured first: with pipefail, `grep -q` closing the pipe early would fail codesign.
SIGNATURE="$(codesign -dv --verbose=2 "$APP" 2>&1)"
[[ "$SIGNATURE" == *"Authority=Developer ID Application: "* ]] || fail "Not signed with a Developer ID."
[[ "$SIGNATURE" == *"TeamIdentifier=${TEAM_ID}"* ]] || fail "Not signed by team ${TEAM_ID}."
[[ "$SIGNATURE" == *"flags=0x10000(runtime)"* ]] || fail "The hardened runtime is off."
[[ "$SIGNATURE" == *"Timestamp="* ]] || fail "The signature has no secure timestamp."

# Submits a file to Apple's notary service and waits (usually a few minutes). Prints Apple's log when it's rejected.
notarize() {
    local result status id
    result="$(xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)" || true
    status="$(plutil -extract status raw -o - - <<< "$result" 2> /dev/null || true)"
    id="$(plutil -extract id raw -o - - <<< "$result" 2> /dev/null || true)"
    if [[ "$status" != "Accepted" ]]; then
        [[ -n "$id" ]] && xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || true
        fail "Notarization of $(basename "$1") ended with status \"${status:-unknown}\" (submission ${id:-unknown})."
    fi
}

ZIP="$OUT/Touchwire-${VERSION}.zip"
DMG="$OUT/Touchwire-${VERSION}.dmg"
echo "▸ Notarizing the app"
# ditto keeps the signature intact, unlike zip. This first zip only goes to the notary service.
ditto -c -k --keepParent --sequesterRsrc "$APP" "$OUT/notarize.zip"
notarize "$OUT/notarize.zip"
xcrun stapler staple -q "$APP"

echo "▸ Packaging"
# The zip is the release asset and the Sparkle update, so it holds the stapled app and the appcast signs that.
ditto -c -k --keepParent --sequesterRsrc "$APP" "$ZIP"
mkdir "$OUT/stage"
cp -R "$APP" "$OUT/stage/"
ln -s /Applications "$OUT/stage/Applications"
diskutil image create from "$OUT/stage" --format UDZO --volumeName "Touchwire" "$DMG" > /dev/null 2>&1
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
echo "▸ Notarizing the DMG"
notarize "$DMG"
xcrun stapler staple -q "$DMG"

echo "▸ Verifying"
# Checks the copy a user gets from the zip, not the build folder.
mkdir "$OUT/verify"
ditto -x -k "$ZIP" "$OUT/verify"
VERIFY_APP="$OUT/verify/Touchwire.app"
codesign --verify --strict --deep "$VERIFY_APP"
xcrun stapler validate -q "$VERIFY_APP" || fail "The zipped app has no notarization ticket."
GATEKEEPER="$(spctl --assess --type execute --verbose=2 "$VERIFY_APP" 2>&1)" || true
[[ "$GATEKEEPER" == *"source=Notarized Developer ID"* ]] || fail "Gatekeeper rejects the zipped app: ${GATEKEEPER}"
xcrun stapler validate -q "$DMG" || fail "The DMG has no notarization ticket."
GATEKEEPER="$(spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG" 2>&1)" || true
[[ "$GATEKEEPER" == *"source=Notarized Developer ID"* ]] || fail "Gatekeeper rejects the DMG: ${GATEKEEPER}"

echo "▸ Signing the appcast"
GENERATE_APPCAST=$(find "$SRC/.build/artifacts/sparkle" -name generate_appcast -type f | head -1)
[[ -n "$GENERATE_APPCAST" ]] || fail "generate_appcast not found."
mkdir "$OUT/appcast"
cp "$ZIP" "$OUT/appcast/"
"$GENERATE_APPCAST" --account Touchwire --download-url-prefix "https://github.com/${REPO}/releases/download/${TAG}/" \
    --maximum-versions 1 "$OUT/appcast" > /dev/null
APPCAST="$OUT/appcast/appcast.xml"
grep -q 'sparkle:edSignature' "$APPCAST" || fail "The appcast has no EdDSA signature."

NOTES="$OUT/notes.md"
awk -v head="## [${VERSION}]" '
    index($0, head) == 1 { found = 1; next }
    found && /^## \[/ { exit }
    found { print }
' "$SRC/CHANGELOG.md" > "$NOTES"
grep -q '[^[:space:]]' "$NOTES" || fail "CHANGELOG.md has no [${VERSION}] section."
cat >> "$NOTES" << NOTES

## Install

Download \`Touchwire-${VERSION}.dmg\` and drag Touchwire into Applications. It needs macOS 26 or later.
The app is signed with a Developer ID and notarized by Apple, so it opens without a Gatekeeper warning. Then turn on
**Start at login and keep running** in Settings; the [README](https://github.com/${REPO}#install) lists the other
steps. Later versions install themselves through **Check for Updates…**.
NOTES

echo "▸ Publishing ${TAG}"
gh release create "$TAG" --repo "$REPO" --target "$COMMIT" \
    --title "Touchwire ${VERSION}" --notes-file "$NOTES" "$ZIP" "$DMG" "$APPCAST"
echo "✓ https://github.com/${REPO}/releases/tag/${TAG}"
