#!/bin/bash
# Packs dist/Volume Rocker.app into dist/VolumeRocker-<version>.dmg with an Applications shortcut.
# Uses only built-in macOS tools (hdiutil). Usage: Scripts/make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."
APP="dist/Volume Rocker.app"
[[ -d "$APP" ]] || { echo "Run Scripts/build.sh first."; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="dist/VolumeRocker-$VERSION.dmg"
STAGE=$(mktemp -d)
ditto "$APP" "$STAGE/Volume Rocker.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Volume Rocker" -srcfolder "$STAGE" -fs HFS+ -format ULFO -ov "$DMG" >/dev/null
rm -rf "$STAGE"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"
fi
echo "$DMG"
