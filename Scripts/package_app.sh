#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/TypeRecorder.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"

swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/.build/release/TypeRecorder" "$MACOS_DIR/TypeRecorder"
cp "$ROOT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Resources/TypeRecorderIcon.icns" "$RESOURCES_DIR/TypeRecorderIcon.icns"
chmod +x "$MACOS_DIR/TypeRecorder"

"$ROOT_DIR/Scripts/sign_app.sh" "$APP_DIR"

echo "已生成：$APP_DIR"
