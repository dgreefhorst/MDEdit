#!/bin/bash
# Bouwt "MDEdit.app" (universal: Apple Silicon + Intel). Vereist Xcode of de Command Line Tools:
#   xcode-select --install
set -euo pipefail
cd "$(dirname "$0")"
APP="build/MDEdit.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/web"

for ARCH in arm64 x86_64; do
  swiftc -O -parse-as-library -swift-version 5 -target "$ARCH-apple-macos13.0" Sources/*.swift -o "build/me-$ARCH"
done
lipo -create build/me-arm64 build/me-x86_64 -output "$APP/Contents/MacOS/MDEdit"
rm build/me-arm64 build/me-x86_64

cp -R Web/. "$APP/Contents/Resources/web/"
cp Info.plist "$APP/Contents/Info.plist"

# Icoon (.icns) uit Resources/icon.png
ICONSET="build/AppIcon.iconset"; mkdir -p "$ICONSET"
for S in 16 32 128 256 512; do
  sips -z $S $S Resources/icon.png --out "$ICONSET/icon_${S}x${S}.png" >/dev/null
  sips -z $((S*2)) $((S*2)) Resources/icon.png --out "$ICONSET/icon_${S}x${S}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

codesign --force --deep --sign - "$APP"
echo "Klaar: $APP"
echo "Installeren:  cp -R \"$APP\" /Applications/   (of sleep de app naar Programma's)"
