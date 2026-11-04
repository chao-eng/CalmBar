#!/usr/bin/env bash
# 将 build/CalmBar.app 打包为可分发的 DMG。
#
# 读取 build/CalmBar.app/Contents/Info.plist 的 CFBundleShortVersionString，
# 把 .app 与 /Applications 快捷方式放进同一卷，用户拖拽即可安装。
#
# 用法：
#   ./scripts/make-dmg.sh              # build/CalmBar-<version>.dmg
#   ./scripts/make-dmg.sh arm          # build/CalmBar-<version>-arm.dmg（单架构本地验证）
#
# 注意：hdiutil 访问 /dev/rdisk*，在受限沙箱内会失败，需在普通终端执行。

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="CalmBar"
APP_PATH="build/${APP_NAME}.app"
SUFFIX="${1:-}"
DMG_DIR="build"

if [[ ! -d "${APP_PATH}" ]]; then
    echo "build/${APP_NAME}.app 不存在 — 请先运行 ./build_app.sh。" >&2
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "0.0.0")
if [[ -n "${SUFFIX}" ]]; then
    DMG_PATH="${DMG_DIR}/${APP_NAME}-${VERSION}-${SUFFIX}.dmg"
else
    DMG_PATH="${DMG_DIR}/${APP_NAME}-${VERSION}.dmg"
fi
VOL_NAME="${APP_NAME} ${VERSION}"

# 用干净的临时目录承载卷内容，确保只带上 .app 与 Applications 快捷方式
STAGE=$(mktemp -d -t calmbar-dmg)
trap 'rm -rf "${STAGE}"' EXIT

cp -R "${APP_PATH}" "${STAGE}/${APP_NAME}.app"
ln -s /Applications "${STAGE}/Applications"

# 拷贝后再签一次，保证 DMG 内的 App 签名完整
codesign --force --deep --sign - "${STAGE}/${APP_NAME}.app" 2>/dev/null || true

rm -f "${DMG_PATH}"
echo "Building ${DMG_PATH}…"
hdiutil create \
    -volname "${VOL_NAME}" \
    -srcfolder "${STAGE}" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "${DMG_PATH}" >/dev/null

# DMG 本身也做 ad-hoc 签名，避免创建后被篡改
codesign --force --sign - "${DMG_PATH}" 2>/dev/null || true

SIZE=$(du -h "${DMG_PATH}" | cut -f1)
echo "Wrote ${DMG_PATH} (${SIZE})"
