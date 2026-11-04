#!/bin/bash
# 构建 CalmBar.app：编译（默认 arm64 + x86_64 通用二进制）→ 组装 Bundle → ad-hoc 签名。
#
# 用法：
#   ./build_app.sh          # 编译并组装通用 (Universal) App（供 DMG 打包）
#   ./build_app.sh arm      # 仅编译 Apple Silicon 版本
#   ./build_app.sh intel    # 仅编译 Intel 版本
#
# 版本号唯一来源是 Resources/Info.plist，发版时由 scripts/release.sh 递增。

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

APP_NAME="CalmBar"
HELPER_NAME="CalmBarHelper"
INFO_PLIST="$DIR/Resources/Info.plist"
BUILD_ROOT="$DIR/build"
SPARKLE_RPATH="@executable_path/../Frameworks"

TARGET_ARCH="${1:-all}"

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "缺少 $INFO_PLIST" >&2
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$INFO_PLIST")

build_arch() {
    local ARCH="$1"        # arm64 / x86_64
    local TRIPLE="$2"
    local ARCH_DIR="$BUILD_ROOT/$ARCH"
    local APP_BUNDLE="$ARCH_DIR/$APP_NAME.app"
    local CONTENTS="$APP_BUNDLE/Contents"
    local MACOS="$CONTENTS/MacOS"
    local RESOURCES="$CONTENTS/Resources"

    echo ""
    echo "=========================================================="
    echo "==> Building $APP_NAME $VERSION for $ARCH..."
    echo "=========================================================="

    swift build -c release --triple "$TRIPLE" --disable-sandbox

    echo "==> Packaging App Bundle at $APP_BUNDLE..."
    rm -rf "$ARCH_DIR"
    mkdir -p "$MACOS" "$RESOURCES" "$CONTENTS/Frameworks"

    cp "$DIR/.build/$TRIPLE/release/$APP_NAME" "$MACOS/$APP_NAME"
    cp "$DIR/.build/$TRIPLE/release/$HELPER_NAME" "$MACOS/$HELPER_NAME"
    chmod +x "$MACOS/$APP_NAME" "$MACOS/$HELPER_NAME"

    # 剥离调试与本地符号，显著减小 release 二进制体积
    strip -x "$MACOS/$APP_NAME" "$MACOS/$HELPER_NAME" 2>/dev/null || true

    cp "$INFO_PLIST" "$CONTENTS/Info.plist"

    # Sparkle：SPM 以 @rpath/Sparkle.framework 链接，需内嵌框架并补 rpath
    local SPARKLE_FRAMEWORK=".build/$TRIPLE/release/Sparkle.framework"
    if [[ -d "$SPARKLE_FRAMEWORK" ]]; then
        cp -R "$SPARKLE_FRAMEWORK" "$CONTENTS/Frameworks/"
        install_name_tool -add_rpath "$SPARKLE_RPATH" "$MACOS/$APP_NAME" 2>/dev/null || true
    fi

    # 复制运行时资源（AppIcon.icns 已含全部尺寸，iconset 与 png 仅供生成 icns）
    for item in "$DIR"/Resources/*; do
        [[ -e "$item" ]] || continue
        case "$(basename "$item")" in
            Info.plist|AppIcon.iconset|AppIcon.png) continue ;;
        esac
        cp -R "$item" "$RESOURCES/"
    done

    echo "==> Signing app bundle ($ARCH)..."
    codesign --force --deep --sign - "$APP_BUNDLE"
}

mkdir -p "$BUILD_ROOT"

case "$TARGET_ARCH" in
    arm|arm64)
        build_arch "arm64" "arm64-apple-macosx"
        rm -rf "$BUILD_ROOT/$APP_NAME.app"
        cp -R "$BUILD_ROOT/arm64/$APP_NAME.app" "$BUILD_ROOT/$APP_NAME.app"
        ;;
    intel|x86_64)
        build_arch "x86_64" "x86_64-apple-macosx"
        rm -rf "$BUILD_ROOT/$APP_NAME.app"
        cp -R "$BUILD_ROOT/x86_64/$APP_NAME.app" "$BUILD_ROOT/$APP_NAME.app"
        ;;
    all|universal)
        build_arch "arm64" "arm64-apple-macosx"
        build_arch "x86_64" "x86_64-apple-macosx"

        echo ""
        echo "==> Merging arm64 + x86_64 into universal bundle..."
        rm -rf "$BUILD_ROOT/$APP_NAME.app"
        cp -R "$BUILD_ROOT/arm64/$APP_NAME.app" "$BUILD_ROOT/$APP_NAME.app"

        lipo -create \
            "$BUILD_ROOT/arm64/$APP_NAME.app/Contents/MacOS/$APP_NAME" \
            "$BUILD_ROOT/x86_64/$APP_NAME.app/Contents/MacOS/$APP_NAME" \
            -output "$BUILD_ROOT/$APP_NAME.app/Contents/MacOS/$APP_NAME"
        lipo -create \
            "$BUILD_ROOT/arm64/$APP_NAME.app/Contents/MacOS/$HELPER_NAME" \
            "$BUILD_ROOT/x86_64/$APP_NAME.app/Contents/MacOS/$HELPER_NAME" \
            -output "$BUILD_ROOT/$APP_NAME.app/Contents/MacOS/$HELPER_NAME"
        chmod +x "$BUILD_ROOT/$APP_NAME.app/Contents/MacOS/$APP_NAME" \
                 "$BUILD_ROOT/$APP_NAME.app/Contents/MacOS/$HELPER_NAME"

        echo "==> Re-signing universal bundle..."
        codesign --force --deep --sign - "$BUILD_ROOT/$APP_NAME.app"
        ;;
    *)
        echo "未知参数：$TARGET_ARCH（可用：all / arm / intel）" >&2
        exit 2
        ;;
esac

echo ""
echo "=========================================================="
echo "🎉 App Bundle Ready: $BUILD_ROOT/$APP_NAME.app"
lipo -info "$BUILD_ROOT/$APP_NAME.app/Contents/MacOS/$APP_NAME"
echo "Version: $VERSION"
echo "下一步打包 DMG: ./scripts/make-dmg.sh"
echo "=========================================================="
