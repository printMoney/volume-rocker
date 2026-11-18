#!/bin/bash
# Fills the String Catalogs (Localizable.xcstrings) with every user-facing string in the code.
# Xcode does this automatically when you build in the Xcode app; this script does it from the command line.
# Run it after adding or changing UI text, then commit the updated .xcstrings files.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild -project VolumeRocker.xcodeproj -scheme VolumeRocker -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData build > build/strings.log 2>&1 \
  || { echo "Build failed; see build/strings.log"; exit 1; }
INTERMEDIATES=build/DerivedData/Build/Intermediates.noindex/VolumeRocker.build/Debug
sync() {
  local catalog=$1 target=$2
  find "$INTERMEDIATES/$target.build" -name "*.stringsdata" -print0 | xargs -0 xcrun xcstringstool sync "$catalog" --stringsdata
  echo "$catalog: $(xcrun xcstringstool print "$catalog" | grep -c '^') strings"
}
sync VolumeRocker/Resources/Localizable.xcstrings VolumeRocker
sync VolumeRockerControls/Localizable.xcstrings VolumeRockerControls
