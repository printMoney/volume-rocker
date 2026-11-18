#!/bin/bash
# Full local release: build → sign → DMG → notarize. Uses the same env vars as sign.sh and notarize.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
Scripts/build.sh
Scripts/sign.sh
DMG=$(Scripts/make-dmg.sh | tail -1)
Scripts/notarize.sh "$DMG"
shasum -a 256 "$DMG"
