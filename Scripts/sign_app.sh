#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${1:?用法：Scripts/sign_app.sh /path/to/TypeRecorder.app}"

if [[ ! -d "$APP_DIR" ]]; then
  echo "签名失败：找不到 App：$APP_DIR" >&2
  exit 1
fi

# macOS 的辅助功能/输入监控授权会绑定 App 的代码签名身份。
# 如果每次发版都使用 ad-hoc 签名，二进制变化后签名要求也会变化，
# 系统设置里的旧授权就可能无法继续匹配新版 App。
#
# 优先级：
# 1. TYPE_RECORDER_CODESIGN_IDENTITY 指定的稳定证书。
# 2. 本机钥匙串里第一个可用的代码签名证书。
# 3. 没有证书时退回 ad-hoc 签名，并明确提示它不适合需要保留 TCC 授权的升级包。
SIGN_IDENTITY="${TYPE_RECORDER_CODESIGN_IDENTITY:-}"

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*"\(.*\)".*/\1/p' \
      | head -n 1
  )"
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="-"
  echo "警告：未找到稳定代码签名证书，本次将使用 ad-hoc 签名。"
  echo "警告：ad-hoc 签名的升级包可能需要重新授权辅助功能/输入监控。"
  echo "提示：设置 TYPE_RECORDER_CODESIGN_IDENTITY 后重新打包，可让升级版复用已有授权。"
else
  echo "使用代码签名身份：$SIGN_IDENTITY"
fi

codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
