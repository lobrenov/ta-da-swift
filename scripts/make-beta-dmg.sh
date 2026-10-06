#!/bin/bash
# Builds a Release archive of Ta Da and packages it as build/TaDa-<version>-<build>.dmg for beta testers.
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHIVE=build/TaDa.xcarchive
STAGING=build/dmg

xcodebuild -workspace TaDa.xcworkspace -scheme TaDa -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" archive

APP="$ARCHIVE/Products/Applications/TaDa.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
DMG="build/TaDa-$VERSION-$BUILD.dmg"

rm -rf "$STAGING"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/Ta Da.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/Read Me First.txt" <<'README'
Ta Da beta (requires macOS 27 or later)

1. Drag Ta Da onto the Applications folder in this window.
2. Ta Da isn't notarised, so macOS blocks it the first time. Unblock it once, either way:
   - In Terminal, run:
       xattr -dr com.apple.quarantine "/Applications/Ta Da.app"
   - Or double-click Ta Da, click Done on the warning, then open
     System Settings > Privacy & Security and click Open Anyway.
3. Open Ta Da and choose your tasks folder.

For a new build, repeat steps 1 and 2 and choose Replace. Your folder is remembered.
README

codesign --verify --deep --strict "$STAGING/Ta Da.app"
rm -f "$DMG"
hdiutil create -volname "Ta Da" -srcfolder "$STAGING" -format UDZO "$DMG"

echo "$PWD/$DMG"
open -R "$DMG"
