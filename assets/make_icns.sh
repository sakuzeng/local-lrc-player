#!/usr/bin/env bash
# 从 1024px PNG 生成 AppIcon.icns。改了 render_app_icon.swift 后重新跑:
#   swift assets/render_app_icon.swift assets/AppIcon-1024.png && ./assets/make_icns.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_PNG="$ROOT_DIR/assets/AppIcon-1024.png"
ICONSET_DIR="$ROOT_DIR/build/AppIcon.iconset"

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

sizes=(16 32 64 128 256 512)
for size in "${sizes[@]}"; do
  sips -z "$size" "$size" "$SRC_PNG" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
done
cp "$ICONSET_DIR/icon_32x32.png" "$ICONSET_DIR/icon_16x16@2x.png"
cp "$ICONSET_DIR/icon_64x64.png" "$ICONSET_DIR/icon_32x32@2x.png"
rm "$ICONSET_DIR/icon_64x64.png"
cp "$ICONSET_DIR/icon_256x256.png" "$ICONSET_DIR/icon_128x128@2x.png"
cp "$ICONSET_DIR/icon_512x512.png" "$ICONSET_DIR/icon_256x256@2x.png"
cp "$SRC_PNG" "$ICONSET_DIR/icon_512x512@2x.png"

iconutil -c icns "$ICONSET_DIR" -o "$ROOT_DIR/assets/AppIcon.icns"
echo "written: assets/AppIcon.icns"
