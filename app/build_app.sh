#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

VERSION="2.0.2"
APP_NAME="CalmBar"
HELPER_NAME="CalmBarHelper"
BUNDLE_ID="com.chao.CalmBar"
BUILD_ROOT="$DIR/build"

# Usage:
#   ./build_app.sh          # 编译并打包 ARM (Apple Silicon) 与 Intel 双版本 Zip
#   ./build_app.sh arm      # 仅编译并打包 ARM (Apple Silicon) 版本
#   ./build_app.sh intel    # 仅编译并打包 Intel (x86_64) 版本
TARGET_ARCH="${1:-all}"

build_arch() {
    local ARCH="$1"        # "arm64" 或 "x86_64"
    local TRIPLE="$2"      # "arm64-apple-macosx" 或 "x86_64-apple-macosx"
    local SUFFIX="$3"      # "arm" 或 "intel"
    local ARCH_DIR="$BUILD_ROOT/$ARCH"
    local APP_BUNDLE="$ARCH_DIR/$APP_NAME.app"
    local CONTENTS="$APP_BUNDLE/Contents"
    local MACOS="$CONTENTS/MacOS"
    local RESOURCES="$CONTENTS/Resources"
    local ZIP_NAME="${APP_NAME}-v${VERSION}-${SUFFIX}.zip"
    local ZIP_PATH="$BUILD_ROOT/$ZIP_NAME"

    echo ""
    echo "=========================================================="
    echo "==> Building $APP_NAME for $ARCH ($SUFFIX)..."
    echo "=========================================================="
    
    swift build -c release --triple "$TRIPLE"

    echo "==> Packaging App Bundle at $APP_BUNDLE..."
    rm -rf "$ARCH_DIR"
    mkdir -p "$MACOS"
    mkdir -p "$RESOURCES"

    cp "$DIR/.build/$TRIPLE/release/$APP_NAME" "$MACOS/$APP_NAME"
    cp "$DIR/.build/$TRIPLE/release/$HELPER_NAME" "$MACOS/$HELPER_NAME"
    chmod +x "$MACOS/$APP_NAME"
    chmod +x "$MACOS/$HELPER_NAME"

    if [ -d "$DIR/Resources" ]; then
        cp -R "$DIR/Resources/"* "$RESOURCES/"
    fi

    cat <<EOF > "$CONTENTS/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.chaoeng.CalmBar</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

    echo "==> Signing app bundle ($ARCH)..."
    codesign --force --deep -s - --requirements '=designated => identifier "com.chaoeng.CalmBar"' "$APP_BUNDLE"

    echo "==> Creating Zip Archive at $ZIP_PATH..."
    rm -f "$ZIP_PATH"
    ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

    echo "✅ Successfully generated: $ZIP_PATH"
}

mkdir -p "$BUILD_ROOT"

if [ "$TARGET_ARCH" = "arm" ] || [ "$TARGET_ARCH" = "arm64" ]; then
    build_arch "arm64" "arm64-apple-macosx" "arm"
    rm -rf "$BUILD_ROOT/$APP_NAME.app"
    cp -R "$BUILD_ROOT/arm64/$APP_NAME.app" "$BUILD_ROOT/$APP_NAME.app"
elif [ "$TARGET_ARCH" = "intel" ] || [ "$TARGET_ARCH" = "x86_64" ]; then
    build_arch "x86_64" "x86_64-apple-macosx" "intel"
    rm -rf "$BUILD_ROOT/$APP_NAME.app"
    cp -R "$BUILD_ROOT/x86_64/$APP_NAME.app" "$BUILD_ROOT/$APP_NAME.app"
else
    build_arch "arm64" "arm64-apple-macosx" "arm"
    build_arch "x86_64" "x86_64-apple-macosx" "intel"

    # 默认将当前主机架构的 App 镜像拷贝到 build/ 根目录供本地调试/部署
    HOST_ARCH="$(uname -m)"
    rm -rf "$BUILD_ROOT/$APP_NAME.app"
    if [ "$HOST_ARCH" = "arm64" ]; then
        cp -R "$BUILD_ROOT/arm64/$APP_NAME.app" "$BUILD_ROOT/$APP_NAME.app"
    else
        cp -R "$BUILD_ROOT/x86_64/$APP_NAME.app" "$BUILD_ROOT/$APP_NAME.app"
    fi
fi

echo ""
echo "=========================================================="
echo "🎉 Build & Packaging Completed! Generated Release Files:"
ls -lh "$BUILD_ROOT"/*.zip
echo "=========================================================="
