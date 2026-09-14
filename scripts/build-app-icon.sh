#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
SOURCE="$ROOT_DIR/Packaging/AppIcon-1024.png"
ICONSET="$ROOT_DIR/tmp/AppIcon.iconset"
OUTPUT="$ROOT_DIR/Packaging/AppIcon.icns"

cd "$ROOT_DIR"
swift "$ROOT_DIR/scripts/render-app-icon.swift"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$OUTPUT"
rm -rf "$ICONSET"
print "Built $OUTPUT"
