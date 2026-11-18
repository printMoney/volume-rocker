#!/bin/bash
# Signs dist/Volume Rocker.app, inside out: Sparkle's helpers, frameworks and the Control Center extension
# first, then the app. Uses the hardened runtime and keeps each piece's entitlements.
#
# Usage: DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" Scripts/sign.sh
# Without DEVELOPER_ID the app is ad-hoc signed, which runs locally but triggers Gatekeeper on other Macs.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="dist/Volume Rocker.app"
[[ -d "$APP" ]] || { echo "Run Scripts/build.sh first."; exit 1; }

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  echo "Signing with: $DEVELOPER_ID"
  IDENTITY="$DEVELOPER_ID"
  # Hardened runtime + secure timestamp: required for notarization.
  EXTRA=(--options runtime --timestamp)
else
  echo "DEVELOPER_ID not set: ad-hoc signing (fine for testing, not for distribution)."
  IDENTITY="-"
  # No hardened runtime for ad-hoc builds: it enforces that every framework comes from the same developer
  # team, and ad-hoc signatures have no team, so the app could not load Sparkle.
  EXTRA=()
fi

# Nested code: bundles (.app, .xpc, .appex, .framework) and loose executables inside frameworks
# (Sparkle's Autoupdate), deepest first, so each container is signed after what it contains.
nested=$(
  {
    find "$APP/Contents" -mindepth 1 -type d \( -name "*.app" -o -name "*.xpc" -o -name "*.appex" -o -name "*.framework" \)
    find "$APP/Contents/Frameworks" -type f -perm -u+x 2>/dev/null | while IFS= read -r file; do
      if file "$file" | grep -q "Mach-O" && [[ "$file" != *.app/* && "$file" != *.xpc/* ]]; then
        # Skip a framework's main binary; it is signed with its bundle.
        [[ "$file" == */Versions/*/Sparkle ]] || echo "$file"
      fi
    done
  } | awk -F/ '{ print NF "\t" $0 }' | sort -rn | cut -f2-
)
while IFS= read -r item; do
  [[ -n "$item" ]] || continue
  codesign --force ${EXTRA[@]+"${EXTRA[@]}"} --preserve-metadata=entitlements --sign "$IDENTITY" "$item"
done <<< "$nested"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  codesign --force --options runtime --timestamp --preserve-metadata=entitlements --sign "$IDENTITY" "$APP"
else
  # An ad-hoc signature changes with every build, so macOS would forget the System Audio Recording
  # permission each time. Requiring only the bundle identifier keeps local test builds recognized as the
  # same app. Release builds are signed with Developer ID above and get Apple's normal requirement.
  BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist")
  codesign --force --preserve-metadata=entitlements --sign - \
    --requirements "=designated => identifier \"$BUNDLE_ID\"" "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
