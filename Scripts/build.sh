#!/bin/bash
# Builds Volume Rocker in Release mode into dist/Volume Rocker.app.
# Usage: Scripts/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null || { echo "XcodeGen is missing. Install it with: brew install xcodegen"; exit 1; }
xcodegen generate --quiet

rm -rf dist build/Release build/DerivedData/Build/Products/Release
mkdir -p dist build
set +e
xcodebuild \
  -project VolumeRocker.xcodeproj \
  -scheme VolumeRocker \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData \
  ARCHS=arm64 \
  build > build/xcodebuild.log 2>&1
STATUS=$?
set -e
grep -E "error:|warning:|\*\* BUILD" build/xcodebuild.log | grep -v appintentsmetadataprocessor || true
[[ $STATUS -eq 0 ]] || { echo "Build failed; see build/xcodebuild.log"; exit 1; }

APP="build/DerivedData/Build/Products/Release/Volume Rocker.app"
[[ -d "$APP" ]] || { echo "Build failed; see build/xcodebuild.log"; exit 1; }
ditto "$APP" "dist/Volume Rocker.app"
echo "Built dist/Volume Rocker.app"
