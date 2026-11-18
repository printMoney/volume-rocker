#!/bin/bash
# Turns one 1024×1024 PNG into every size the macOS app icon needs.
# Usage: Scripts/make-icon-set.sh path/to/icon_1024.png   (no argument: regenerate the placeholder)
set -euo pipefail
cd "$(dirname "$0")/.."
SET="VolumeRocker/Resources/Assets.xcassets/AppIcon.appiconset"
SRC="${1:-}"
if [[ -z "$SRC" ]]; then
  SRC="$(mktemp -d)/icon_1024.png"
  swift Scripts/make-placeholder-icon.swift "$SRC"
fi
for px in 16 32 64 128 256 512 1024; do
  sips -s format png -z "$px" "$px" "$SRC" --out "$SET/icon_${px}.png" >/dev/null
done
cat > "$SET/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "icon_16.png",   "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_32.png",   "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32.png",   "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_64.png",   "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128.png",  "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_256.png",  "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256.png",  "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_512.png",  "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512.png",  "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_1024.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
echo "App icon updated in $SET"
