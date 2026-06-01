#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/TypeRecorder.app"
DMG_STAGING_DIR="$DIST_DIR/dmg-staging"
DMG_PATH="$DIST_DIR/TypeRecorder.dmg"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"

swift build -c release

rm -rf "$APP_DIR" "$DMG_STAGING_DIR" "$DMG_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$DMG_STAGING_DIR"

cp "$ROOT_DIR/.build/release/TypeRecorder" "$MACOS_DIR/TypeRecorder"
cp "$ROOT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Resources/TypeRecorderIcon.icns" "$RESOURCES_DIR/TypeRecorderIcon.icns"
cp -R "$ROOT_DIR/Resources/AchievementBadges" "$RESOURCES_DIR/AchievementBadges"
cp -R "$ROOT_DIR/Sources/TypeRecorder/Resources/TimePersonaBadges" "$RESOURCES_DIR/TimePersonaBadges"
cp "$ROOT_DIR/Resources/mm_reward_qrcode.png" "$RESOURCES_DIR/mm_reward_qrcode.png"
chmod +x "$MACOS_DIR/TypeRecorder"

"$ROOT_DIR/Scripts/sign_app.sh" "$APP_DIR"

# 清掉本机可能遗留的隔离属性，避免把本机调试痕迹一起放进 DMG。
xattr -cr "$APP_DIR" || true

cp -R "$APP_DIR" "$DMG_STAGING_DIR/"
ln -s /Applications "$DMG_STAGING_DIR/Applications"

hdiutil create \
  -volname "TypeRecorder" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$DMG_STAGING_DIR"

echo "已生成：$APP_DIR"
echo "已生成：$DMG_PATH"
