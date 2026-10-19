#!/bin/zsh
# Builds the tagged version and publishes it as a GitHub release with a signed zip and DMG.
# Usage: publish-release.sh [version]   (defaults to Info.plist's CFBundleShortVersionString)
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="gilitos92/Touchwire"
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"
TAG="v${VERSION}"

fail() { echo "✗ $1" >&2; exit 1; }

COMMIT="$(git rev-parse -q --verify "${TAG}^{commit}")" || fail "No tag ${TAG}."
git ls-remote --exit-code --tags origin "refs/tags/${TAG}" > /dev/null || fail "Push ${TAG} first."
! gh release view "$TAG" --repo "$REPO" > /dev/null 2>&1 || fail "$TAG is already published."
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
VERSION="$VERSION" BUILD="$BUILD" "$SRC/Scripts/build.sh" > /dev/null
APP="$SRC/build/Touchwire.app"
codesign --verify --strict --deep "$APP"
# Captured first: with pipefail, `grep -q` closing the pipe early would fail codesign. Only --verbose=2 lists the signer.
SIGNATURE="$(codesign -dv --verbose=2 "$APP" 2>&1)"
[[ "$SIGNATURE" == *"Authority=GGV"* ]] || fail "Not signed with GGV."

ZIP="$OUT/Touchwire-${VERSION}.zip"
DMG="$OUT/Touchwire-${VERSION}.dmg"
echo "▸ Packaging"
# ditto keeps the signature intact, unlike zip.
ditto -c -k --keepParent --sequesterRsrc "$APP" "$ZIP"
mkdir "$OUT/stage"
cp -R "$APP" "$OUT/stage/"
ln -s /Applications "$OUT/stage/Applications"
diskutil image create from "$OUT/stage" --format UDZO --volumeName "Touchwire" "$DMG" > /dev/null 2>&1

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
The app is self-signed, not notarized by Apple, so macOS blocks the first launch; the
[README](https://github.com/${REPO}#install) shows how to open it. Then turn on **Start at login and keep running**
in Settings.
NOTES

echo "▸ Publishing ${TAG}"
gh release create "$TAG" --repo "$REPO" --target "$COMMIT" \
    --title "Touchwire ${VERSION}" --notes-file "$NOTES" "$ZIP" "$DMG"
echo "✓ https://github.com/${REPO}/releases/tag/${TAG}"
