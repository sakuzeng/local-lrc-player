#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/.build/test"
BIN_PATH="$BUILD_DIR/RunDatabaseTests"

mkdir -p "$BUILD_DIR"

SWIFT_FILES=()
while IFS= read -r file; do
  SWIFT_FILES+=("$file")
done < <(find "$ROOT_DIR/Sources/LocalLrcPlayer" -name '*.swift' ! -name 'main.swift' -print | sort)

echo "Compiling database tests..."
swiftc \
  -O \
  -framework AppKit \
  -framework AVFoundation \
  -framework QuartzCore \
  -lsqlite3 \
  "${SWIFT_FILES[@]}" \
  "$ROOT_DIR/Tests/RunDatabaseTests/main.swift" \
  -o "$BIN_PATH"

echo "Running database tests..."
"$BIN_PATH"

echo "Building app bundle..."
"$ROOT_DIR/build.sh"
