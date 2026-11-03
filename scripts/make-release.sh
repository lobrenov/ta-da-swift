#!/bin/bash
# Archives Ta Da and publishes build/release/ as a GitHub release: DMG, update zip, notes and the Sparkle feed.
# --dry-run builds the files and prints them, and creates no release.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO=lobrenov/ta-da-swift
DRY=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY=1 ;;
  *) echo "usage: $0 [--dry-run]" >&2; exit 1 ;;
esac

git fetch -q --tags origin main
if [ $DRY -eq 0 ]; then
  [ -z "$(git status --porcelain)" ] || { echo "Working tree isn't clean." >&2; exit 1; }
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "HEAD isn't origin/main." >&2; exit 1; }
fi

check_unreleased() {
  if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "$TAG already has a release." >&2
    exit 1
  fi
}

SETTINGS=$(xcodebuild -workspace TaDa.xcworkspace -scheme TaDa -configuration Release -destination 'generic/platform=macOS' -showBuildSettings 2>/dev/null) \
  || { echo "xcodebuild -showBuildSettings failed." >&2; exit 1; }
BUILD_DIR=$(awk '$1=="BUILD_DIR"{print $3}' <<<"$SETTINGS")
SPARKLE_BIN="${BUILD_DIR%/Build/Products}/SourcePackages/artifacts/sparkle/Sparkle/bin"
[ -x "$SPARKLE_BIN/generate_appcast" ] || { echo "Sparkle's generate_appcast isn't in $SPARKLE_BIN; resolve packages in Xcode first." >&2; exit 1; }
TAG="v$(awk '$1=="MARKETING_VERSION"{print $3}' <<<"$SETTINGS")-$(awk '$1=="CURRENT_PROJECT_VERSION"{print $3}' <<<"$SETTINGS")"
check_unreleased

ARCHIVE=build/TaDa.xcarchive
STAGING=build/dmg
OUT=build/release

xcodebuild -workspace TaDa.xcworkspace -scheme TaDa -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" archive

APP="$ARCHIVE/Products/Applications/TaDa.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
MINIMUM=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")
[ "$("$SPARKLE_BIN/generate_keys" -p)" = "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist")" ] \
  || { echo "The Keychain's Sparkle key doesn't match the archived app's SUPublicEDKey." >&2; exit 1; }
TAG="v$VERSION-$BUILD"
check_unreleased
NAME="TaDa-$VERSION-$BUILD"

rm -rf "$STAGING" "$OUT"
mkdir -p "$STAGING" "$OUT/feed"
ditto "$APP" "$STAGING/Ta Da.app"
codesign --verify --deep --strict "$STAGING/Ta Da.app"

ditto -c -k --keepParent "$STAGING/Ta Da.app" "$OUT/$NAME.zip"

ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/Read Me First.txt" <<README
Ta Da beta (requires macOS ${MINIMUM%.0} or later)

1. Drag Ta Da onto the Applications folder in this window.
2. Ta Da isn't notarised, so macOS blocks it the first time. Unblock it once, either way:
   - In Terminal, run:
       xattr -dr com.apple.quarantine "/Applications/Ta Da.app"
   - Or double-click Ta Da, click Done on the warning, then open
     System Settings > Privacy & Security and click Open Anyway.
3. Open Ta Da and choose your tasks folder.

Later builds arrive by themselves through Ta Da's update window (Check for Updates... in the Ta Da menu), and the folder is remembered.
README
hdiutil create -volname "Ta Da" -srcfolder "$STAGING" -format UDZO "$OUT/$NAME.dmg"

PREV=$(git tag --list 'v*-*' --merged HEAD --sort=-v:refname | head -1)
[ -n "$PREV" ] || PREV=$(git tag --list 'v*' --merged HEAD^ --sort=-v:refname | grep -v -- '-' | head -1 || true)
SUBJECTS=$(git log --format=%s ${PREV:+"$PREV..HEAD"})
{
  echo "<ul>"
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    s=${s//&/&amp;}; s=${s//</&lt;}; s=${s//>/&gt;}
    echo "<li>$s</li>"
  done <<<"$SUBJECTS"
  echo "</ul>"
} > "$OUT/$NAME.html"
NOTES=$(sed 's/^/- /' <<<"$SUBJECTS")

cp "$OUT/$NAME.zip" "$OUT/$NAME.html" "$OUT/feed/"
"$SPARKLE_BIN/generate_appcast" --maximum-deltas 0 --embed-release-notes \
  --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" "$OUT/feed"
mv "$OUT/feed/appcast.xml" "$OUT/appcast.xml"
rm -rf "$OUT/feed"

if [ $DRY -eq 1 ]; then
  echo "$PWD/$OUT/$NAME.zip"
  echo "$PWD/$OUT/$NAME.dmg"
  echo "$PWD/$OUT/appcast.xml"
  cat "$OUT/appcast.xml"
  exit 0
fi

gh release create "$TAG" --repo "$REPO" --target "$(git rev-parse HEAD)" --latest \
  --title "Ta Da $VERSION ($BUILD)" --notes "$NOTES" \
  "$OUT/$NAME.zip" "$OUT/$NAME.dmg" "$OUT/appcast.xml"
