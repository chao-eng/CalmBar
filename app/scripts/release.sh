#!/usr/bin/env bash
# 一键发版：递增版本号 → 构建通用 App → 生成 DMG → EdDSA 签名 → 写入 appcast.xml
#
# 用法：
#   ./scripts/release.sh             # 修订号 +1：2.4.0 → 2.4.1（build 号同时 +1）
#   ./scripts/release.sh minor       # 次版本 +1：2.4.0 → 2.5.0
#   ./scripts/release.sh major       # 主版本 +1：2.4.0 → 3.0.0
#   ./scripts/release.sh --dry-run   # 只打印将要执行的内容，不修改任何文件
#
# 环境变量：
#   REPO=chao-eng/CalmBar   决定 appcast 中的下载地址，默认 chao-eng/CalmBar
#
# 注意：hdiutil 与 sign_update（读钥匙串私钥）在受限沙箱内会失败，需在普通终端执行。

set -euo pipefail
cd "$(dirname "$0")/.."

REPO="${REPO:-chao-eng/CalmBar}"
INFO="Resources/Info.plist"
APPCAST="../appcast.xml"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"

DRY_RUN=0
LEVEL="patch"
for arg in "$@"; do
    case "$arg" in
        --dry-run)        DRY_RUN=1 ;;
        patch|minor|major) LEVEL="$arg" ;;
        *) echo "未知参数：$arg（可用：patch / minor / major / --dry-run）" >&2; exit 2 ;;
    esac
done

if [[ ! -x "${SPARKLE_BIN}/sign_update" ]]; then
    echo "找不到 Sparkle 签名工具，请先运行 swift build --disable-sandbox 下载依赖。" >&2
    exit 1
fi

CUR_SHORT=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$INFO")
CUR_BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$INFO")
MIN_SYS=$(/usr/libexec/PlistBuddy -c "Print LSMinimumSystemVersion" "$INFO")

IFS=. read -r MAJOR MINOR PATCH <<< "$CUR_SHORT"
case "$LEVEL" in
    patch) PATCH=$((PATCH + 1)) ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
esac
NEW_SHORT="${MAJOR}.${MINOR}.${PATCH}"
NEW_BUILD=$((CUR_BUILD + 1))
DMG="build/CalmBar-${NEW_SHORT}.dmg"
DMG_NAME=$(basename "$DMG")
PUBDATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")

say() { printf '→ %s\n' "$*"; }

say "版本：${CUR_SHORT} (${CUR_BUILD}) → ${NEW_SHORT} (${NEW_BUILD})"

if [[ $DRY_RUN -eq 1 ]]; then
    cat <<EOF
将执行：
  1. 更新 ${INFO} 的 CFBundleShortVersionString=${NEW_SHORT} / CFBundleVersion=${NEW_BUILD}
  2. ./build_app.sh && ./scripts/make-dmg.sh  →  ${DMG}
  3. 用 EdDSA 私钥签名 ${DMG}
  4. 在 ${APPCAST} 顶部插入新 <item>（${NEW_SHORT} / build ${NEW_BUILD} / ${PUBDATE}）
  5. 下载地址：https://github.com/${REPO}/releases/download/v${NEW_SHORT}/${DMG_NAME}
（--dry-run：未修改任何文件）
EOF
    exit 0
fi

# 任一步失败都回滚版本号，避免留下「版本号改了但没发出去」的半成品状态。
cp "$INFO" "${INFO}.bak"
rollback() {
    mv "${INFO}.bak" "$INFO"
    echo "✗ 发版中止，已回滚 Info.plist 版本号" >&2
}
trap rollback ERR

say "写入新版本号…"
/usr/libexec/PlistBuddy \
    -c "Set :CFBundleShortVersionString ${NEW_SHORT}" \
    -c "Set :CFBundleVersion ${NEW_BUILD}" \
    "$INFO"

say "构建通用 App…"
./build_app.sh

say "生成 DMG…"
./scripts/make-dmg.sh

if [[ ! -f "$DMG" ]]; then
    echo "未生成 ${DMG}" >&2
    exit 1
fi

say "签名 DMG…"
SIGN_OUT=$("${SPARKLE_BIN}/sign_update" "$DMG")
SIG=$(printf '%s\n' "$SIGN_OUT" | sed -n 's/.*edSignature="\([^"]*\)".*/\1/p' | head -1)
LEN=$(stat -f%z "$DMG")
if [[ -z "$SIG" ]]; then
    echo "无法从 sign_update 取得签名：${SIGN_OUT}" >&2
    exit 1
fi

say "更新 ${APPCAST}…"
ITEM_FILE=$(mktemp -t calmbar-release-item)
cat > "$ITEM_FILE" <<EOF
    <item>
      <title>CalmBar ${NEW_SHORT}</title>
      <sparkle:version>${NEW_BUILD}</sparkle:version>
      <sparkle:shortVersionString>${NEW_SHORT}</sparkle:shortVersionString>
      <pubDate>${PUBDATE}</pubDate>
      <sparkle:minimumSystemVersion>${MIN_SYS}</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/${REPO}/releases/tag/v${NEW_SHORT}</sparkle:releaseNotesLink>
      <enclosure
        url="https://github.com/${REPO}/releases/download/v${NEW_SHORT}/${DMG_NAME}"
        sparkle:edSignature="${SIG}"
        length="${LEN}"
        type="application/octet-stream" />
    </item>
EOF

cp "$APPCAST" "${APPCAST}.bak"
# 新条目插到 </language> 之后、旧 <item> 之前，历史版本继续保留给老用户。
sed "/<\/language>/r ${ITEM_FILE}" "${APPCAST}.bak" > "${APPCAST}.new"
mv "${APPCAST}.new" "$APPCAST"
rm -f "$ITEM_FILE"

if ! xmllint --noout "$APPCAST"; then
    mv "${APPCAST}.bak" "$APPCAST"
    echo "✗ appcast.xml 校验失败，已回滚" >&2
    exit 1
fi
rm -f "${APPCAST}.bak"

trap - ERR
rm -f "${INFO}.bak"

say "完成：${NEW_SHORT} (${NEW_BUILD})"
echo
echo "产物：${DMG}"
echo "签名：sparkle:edSignature=\"${SIG}\" length=\"${LEN}\""
echo
echo "接下来："
echo "  1. 创建 release 并上传 DMG（签名只对这份 DMG 的字节有效，不要重新打包）："
echo "     gh release create v${NEW_SHORT} \"${DMG}\" --title \"CalmBar ${NEW_SHORT}\" --notes \"发版说明\""
echo "  2. 提交版本号与 appcast，并推送到 main（检查更新从 main 分支的 appcast.xml 拉取）："
echo "     git add app/${INFO} appcast.xml && git commit -m \"release: v${NEW_SHORT}\" && git push"
