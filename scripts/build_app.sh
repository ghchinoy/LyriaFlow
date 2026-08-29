#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

BUILD_CONFIG="debug"
if [ "$1" == "--release" ] || [ "$1" == "-c release" ]; then
    BUILD_CONFIG="release"
fi

if [ "$BUILD_CONFIG" == "release" ]; then
    echo "🔨 Building LyriaFlow (release)..."
    swift build -c release --product LyriaFlow
    BIN_DIR="$DIR/.build/release"
else
    echo "⚡️ Building LyriaFlow (fast incremental debug)..."
    swift build --product LyriaFlow
    BIN_DIR="$DIR/.build/debug"
fi

APP_NAME="LyriaFlow.app"
APP_DIR="$DIR/$APP_NAME"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

cp "$BIN_DIR/LyriaFlow" "$MACOS_DIR/LyriaFlow"
chmod +x "$MACOS_DIR/LyriaFlow"

cat <<EOF > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>LyriaFlow</string>
    <key>CFBundleIdentifier</key>
    <string>com.lyriaflow.app</string>
    <key>CFBundleName</key>
    <string>LyriaFlow</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

touch "$APP_DIR"
echo "✅ Ready: $APP_NAME"
