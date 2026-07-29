#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/WriteSense.app"
VERSION="${VERSION:-0.2.0}"
BUILD_NUMBER="${BUILD_NUMBER:-2}"
ENTITLEMENTS="$ROOT/Scripts/WriteSense.entitlements"

case "$VERSION" in
    ''|*[!0-9.]*) printf 'VERSION must contain only digits and periods.\n' >&2; exit 1 ;;
esac
case "$BUILD_NUMBER" in
    ''|*[!0-9]*) printf 'BUILD_NUMBER must be an integer.\n' >&2; exit 1 ;;
esac

swift build --package-path "$ROOT" -c release
BINARY="$ROOT/.build/release/WriteSense"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Documentation"
cp "$BINARY" "$APP/Contents/MacOS/WriteSense"
cp "$ROOT/docs/privacy-and-data.md" "$APP/Contents/Resources/Documentation/"
cp "$ROOT/docs/known-limitations.md" "$APP/Contents/Resources/Documentation/"
cp "$ROOT/docs/support.md" "$APP/Contents/Resources/Documentation/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>WriteSense</string>
    <key>CFBundleExecutable</key>
    <string>WriteSense</string>
    <key>CFBundleIdentifier</key>
    <string>io.andura.writesense</string>
    <key>CFBundleName</key>
    <string>WriteSense</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>WriteSense uses Accessibility access to read text only from applications you approve and provide personalized writing guidance.</string>
</dict>
</plist>
PLIST

# Keep a stable signing identity so macOS does not invalidate Accessibility
# approval after every local rebuild. Distribution builds should explicitly set
# CODESIGN_IDENTITY to a Developer ID Application certificate.
IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '\"' '/Developer ID Application/ { print $2; exit }')"
fi
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '\"' '/Apple Development/ { print $2; exit }')"
fi

if [ -n "$IDENTITY" ]; then
    case "$IDENTITY" in
        *"Developer ID Application"*)
            codesign --force --deep --options runtime --timestamp \
                --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP" >/dev/null
            ;;
        *)
            codesign --force --deep --options runtime \
                --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP" >/dev/null
            ;;
    esac
else
    codesign --force --deep --options runtime \
        --entitlements "$ENTITLEMENTS" --sign - "$APP" >/dev/null
fi

codesign --verify --deep --strict --verbose=2 "$APP" >/dev/null
printf 'Built %s (version %s, build %s)\n' "$APP" "$VERSION" "$BUILD_NUMBER"
