#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/WriteSense.app"

swift build --package-path "$ROOT" -c release
BINARY="$ROOT/.build/release/WriteSense"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/WriteSense"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>WriteSense</string>
    <key>CFBundleExecutable</key>
    <string>WriteSense</string>
    <key>CFBundleIdentifier</key>
    <string>com.writesense.app</string>
    <key>CFBundleName</key>
    <string>WriteSense</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>WriteSense uses Accessibility access to read text only from applications you approve and provide personalized writing guidance.</string>
</dict>
</plist>
PLIST

# Keep a stable signing identity so macOS does not invalidate Accessibility
# approval after every local rebuild.
IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '\"' '/Apple Development|Developer ID Application/ { print $2; exit }')"
fi
if [ -n "$IDENTITY" ]; then
    codesign --force --deep --sign "$IDENTITY" "$APP" >/dev/null
else
    codesign --force --deep --sign - "$APP" >/dev/null
fi

printf 'Built %s\n' "$APP"
