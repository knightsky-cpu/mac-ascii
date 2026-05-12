#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MacAscii"
BUILD_CONFIG="${BUILD_CONFIG:-release}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-MacAscii Local Code Signing}"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
INSTALL_APP_DIR="/Applications/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$ROOT_DIR/build/$APP_NAME.iconset"
ICON_SOURCE="$ROOT_DIR/Assets/AppIconSource.png"
ICNS_PATH="$RESOURCES_DIR/AppIcon.icns"

if [[ ! -f "$ICON_SOURCE" ]]; then
    echo "Missing icon source: $ICON_SOURCE" >&2
    exit 1
fi

cd "$ROOT_DIR"
swift build -c "$BUILD_CONFIG"

rm -rf "$APP_DIR" "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR"

EXECUTABLE_PATH="$(swift build -c "$BUILD_CONFIG" --show-bin-path)/$APP_NAME"
cp "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$ICON_SOURCE" "$ICONSET_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>local.mac-ascii.MacAscii</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSScreenCaptureUsageDescription</key>
  <string>MacAscii captures the display to render a live ASCII overlay.</string>
</dict>
</plist>
PLIST

if security find-identity -v -p codesigning | grep -Fq "$CODESIGN_IDENTITY"; then
    codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_DIR" >/dev/null
else
    echo "warning: code-signing identity '$CODESIGN_IDENTITY' not found; using ad-hoc signing" >&2
    codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi
echo "$APP_DIR"

if [[ "${INSTALL_TO_APPLICATIONS:-0}" == "1" ]]; then
    rm -rf "$INSTALL_APP_DIR"
    cp -a "$APP_DIR" "$INSTALL_APP_DIR"
    echo "$INSTALL_APP_DIR"
fi
