#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "==> Building CalmBar & CalmBarHelper for arm64 (Apple Silicon)..."
swift build -c release --triple arm64-apple-macosx

echo "==> Building CalmBar & CalmBarHelper for x86_64 (Intel)..."
swift build -c release --triple x86_64-apple-macosx

APP_NAME="CalmBar"
HELPER_NAME="CalmBarHelper"
APP_BUNDLE="$DIR/build/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "==> Creating macOS App Bundle at $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

echo "==> Creating Universal Binaries (arm64 + x86_64)..."
lipo -create \
    "$DIR/.build/arm64-apple-macosx/release/$APP_NAME" \
    "$DIR/.build/x86_64-apple-macosx/release/$APP_NAME" \
    -output "$MACOS/$APP_NAME"

lipo -create \
    "$DIR/.build/arm64-apple-macosx/release/$HELPER_NAME" \
    "$DIR/.build/x86_64-apple-macosx/release/$HELPER_NAME" \
    -output "$MACOS/$HELPER_NAME"

chmod +x "$MACOS/$APP_NAME"
chmod +x "$MACOS/$HELPER_NAME"

# Copy all resources if available
if [ -d "$DIR/Resources" ]; then
    cp -R "$DIR/Resources/"* "$RESOURCES/"
fi

cat <<EOF > "$CONTENTS/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>CalmBar</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.chaoeng.CalmBar</string>
    <key>CFBundleName</key>
    <string>CalmBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1.0</string>
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

echo "==> Signing app bundle with designated requirement identifier com.chaoeng.CalmBar..."
codesign --force --deep -s - --requirements '=designated => identifier "com.chaoeng.CalmBar"' "$APP_BUNDLE"

echo "==> Successfully built $APP_BUNDLE"
