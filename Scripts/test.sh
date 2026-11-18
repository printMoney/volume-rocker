#!/bin/bash
# Lints, builds and runs the unit tests, failing on any warning. Same checks as CI.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
swiftformat --lint .
swiftlint lint --strict --quiet
xcodebuild \
  -project VolumeRocker.xcodeproj \
  -scheme VolumeRocker \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  test
