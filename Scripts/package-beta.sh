#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
RELEASE_VERSION="${RELEASE_VERSION:-0.2.0-beta.1}"
APP_VERSION="${APP_VERSION:-0.2.0}"
BUILD_NUMBER="${BUILD_NUMBER:-2}"
RELEASE_DIR="$ROOT/build/releases"
APP="$ROOT/build/WriteSense.app"
ARCHIVE="$RELEASE_DIR/WriteSense-$RELEASE_VERSION.zip"
NOTARY_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"
REQUIRE_NOTARIZATION="${REQUIRE_NOTARIZATION:-0}"

case "$RELEASE_VERSION" in
    ''|*[!A-Za-z0-9._-]*) printf 'RELEASE_VERSION contains unsupported characters.\n' >&2; exit 1 ;;
esac

mkdir -p "$RELEASE_DIR"

swift test --package-path "$ROOT"
VERSION="$APP_VERSION" BUILD_NUMBER="$BUILD_NUMBER" "$ROOT/Scripts/build-app.sh"

SIGNING_INFO="$(codesign -dv --verbose=4 "$APP" 2>&1 || true)"
if ! printf '%s' "$SIGNING_INFO" | grep -q 'Authority=Developer ID Application'; then
    if [ "$REQUIRE_NOTARIZATION" = "1" ]; then
        printf '%s\n' 'A Developer ID Application signature is required.' >&2
        exit 1
    fi
    printf '%s\n' 'Warning: beta archive is not Developer ID signed.' >&2
fi

rm -f "$ARCHIVE" "$ARCHIVE.sha256"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"

if [ -n "$NOTARY_PROFILE" ]; then
    xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    spctl --assess --type execute --verbose=4 "$APP"
    rm -f "$ARCHIVE"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
elif [ "$REQUIRE_NOTARIZATION" = "1" ]; then
    printf '%s\n' 'Set NOTARY_KEYCHAIN_PROFILE to notarize the beta archive.' >&2
    exit 1
else
    printf '%s\n' 'Warning: beta archive was not submitted for notarization.' >&2
fi

shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"
printf 'Beta archive: %s\nChecksum: %s\n' "$ARCHIVE" "$ARCHIVE.sha256"
