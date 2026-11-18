#!/bin/bash
# Builds Volume Rocker in Release mode into dist/Volume Rocker.app.
# Usage: Scripts/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null || { echo "XcodeGen is missing. Install it with: brew install xcodegen"; exit 1; }
xcodegen generate --quiet

rm -rf dist build/Release
mkdir -p dist
xcodebuild \
  -project VolumeRocker.xcodeproj \
  -scheme VolumeRocker \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData \
  ARCHS=arm64 \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  build | tee build/xcodebuild.log | grep -E "error:|warning:|\*\* BUILD" || true

APP="build/DerivedData/Build/Products/Release/Volume Rocker.app"
[[ -d "$APP" ]] || { echo "Build failed; see build/xcodebuild.log"; exit 1; }
ditto "$APP" "dist/Volume Rocker.app"
echo "Built dist/Volume Rocker.app"
