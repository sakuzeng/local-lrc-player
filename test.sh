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

# 测试目录下所有文件一起编译：main.swift 是 runner，其余按主题拆分（数据库 / LrcParser / UI 布局）。
TEST_FILES=()
while IFS= read -r file; do
  TEST_FILES+=("$file")
done < <(find "$ROOT_DIR/Tests/RunDatabaseTests" -name '*.swift' -print | sort)

echo "Compiling database tests..."
swiftc \
  -O \
  -framework AppKit \
  -framework AVFoundation \
  -framework QuartzCore \
  -framework MediaPlayer \
  -lsqlite3 \
  "${SWIFT_FILES[@]}" \
  "${TEST_FILES[@]}" \
  -o "$BIN_PATH"

echo "Running database tests..."
"$BIN_PATH"

echo "Building app bundle..."
"$ROOT_DIR/build.sh"
