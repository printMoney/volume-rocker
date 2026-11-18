#!/bin/bash
# Signs dist/Volume Rocker.app with your Developer ID certificate (hardened runtime, secure timestamp).
# Usage: DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" Scripts/sign.sh
# Without DEVELOPER_ID the app is ad-hoc signed, which runs locally but triggers Gatekeeper on other Macs.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="dist/Volume Rocker.app"
[[ -d "$APP" ]] || { echo "Run Scripts/build.sh first."; exit 1; }

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  echo "Signing with: $DEVELOPER_ID"
  # Sign nested code first (Sparkle's helpers arrive in Phase 4), then the app itself.
  find "$APP/Contents" \( -name "*.framework" -o -name "*.xpc" -o -name "*.app" -o -name "*.dylib" \) -prune -print0 2>/dev/null \
    | while IFS= read -r -d '' item; do
        codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$item"
      done
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
else
  echo "DEVELOPER_ID not set: ad-hoc signing (fine for testing, not for distribution)."
  # An ad-hoc signature changes with every build, so macOS would forget the System Audio Recording
  # permission each time. Requiring only the bundle identifier keeps local test builds recognized as the
  # same app. Release builds are signed with Developer ID above and get Apple's normal requirement.
  BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist")
  codesign --force --deep --options runtime --sign - \
    --requirements "=designated => identifier \"$BUNDLE_ID\"" "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
