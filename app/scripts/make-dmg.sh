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

# 代码签名身份：与 build_app.sh 保持一致，优先固定自签名证书，缺失时回退 ad-hoc
SIGN_IDENTITY="CalmBar Dev Signing"
CODE_SIGN_IDENTITY="-"
if security find-identity -p codesigning 2>/dev/null | grep -q "\"${SIGN_IDENTITY}\""; then
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY"
else
    echo "⚠️  未找到签名证书「${SIGN_IDENTITY}」，回退 ad-hoc 签名；重打包后钥匙串会再次要求授权" >&2
fi
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
codesign --force --deep --sign "${CODE_SIGN_IDENTITY}" "${STAGE}/${APP_NAME}.app"

rm -f "${DMG_PATH}"
echo "Building ${DMG_PATH}…"
hdiutil create \
    -volname "${VOL_NAME}" \
    -srcfolder "${STAGE}" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "${DMG_PATH}" >/dev/null

# DMG 本身也做签名，避免创建后被篡改
codesign --force --sign "${CODE_SIGN_IDENTITY}" "${DMG_PATH}"

SIZE=$(du -h "${DMG_PATH}" | cut -f1)
echo "Wrote ${DMG_PATH} (${SIZE})"
