#!/bin/bash
# Regenerates docs/images/hero-*.png and equalizer-*.png from the real SwiftUI views with example apps.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
TEST_RUNNER_RENDER_README_IMAGES=1 xcodebuild -project VolumeRocker.xcodeproj -scheme VolumeRocker \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData \
  test -only-testing:VolumeRockerTests/ReadmeImages > build/readme-images.log 2>&1 \
  || { echo "Rendering failed; see build/readme-images.log"; exit 1; }
ls -1 docs/images/*.png
