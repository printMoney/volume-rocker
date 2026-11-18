#!/bin/bash
# Sends a DMG to Apple for notarization, waits, then staples the ticket so it opens offline.
# Usage: Scripts/notarize.sh dist/VolumeRocker-x.y.z.dmg
#
# Authenticate with ONE of:
#   App Store Connect API key (recommended): NOTARY_KEY_PATH (.p8 file), NOTARY_KEY_ID, NOTARY_ISSUER_ID
#   Apple ID: APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD (app-specific password from appleid.apple.com)
set -euo pipefail
DMG="${1:?Usage: Scripts/notarize.sh path/to.dmg}"

if [[ -n "${NOTARY_KEY_PATH:-}" ]]; then
  AUTH=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
elif [[ -n "${APPLE_ID:-}" ]]; then
  AUTH=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
else
  echo "No notarization credentials set; skipping notarization."
  exit 0
fi

xcrun notarytool submit "$DMG" "${AUTH[@]}" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "Notarized and stapled: $DMG"
