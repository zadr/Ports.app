#!/bin/bash
# Assemble Ports.app from the SwiftPM build product.
# Usage: ./bundle.sh [debug|release] [--skip-build]
# release: hardened runtime signature (CODESIGN_IDENTITY, ad hoc when unset) and Ports.zip.
set -euo pipefail

CONFIG="${1:-debug}"
SKIP_BUILD="${2:-}"
ROOT="$(cd "$(dirname "$0")" && pwd)"

if [[ "$SKIP_BUILD" != "--skip-build" ]]; then
    swift build --package-path "$ROOT" --configuration "$CONFIG"
fi
BIN="$(swift build --package-path "$ROOT" --configuration "$CONFIG" --show-bin-path)/Ports"

APP="$ROOT/Ports.app"
ZIP="$ROOT/Ports.zip"
rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Ports"
cp "$ROOT/Sources/Ports/Info.plist" "$APP/Contents/Info.plist"
for resource in "$ROOT"/Sources/Ports/Resources/*; do
    [[ -e "$resource" ]] && cp -R "$resource" "$APP/Contents/Resources/"
done
for bundle in "$(dirname "$BIN")"/*.bundle; do
    [[ -d "$bundle" ]] && cp -R "$bundle" "$APP/Contents/Resources/"
done

if [[ "$CONFIG" != "release" ]]; then
    codesign --force --sign - "$APP"
    echo "Built $APP"
    exit 0
fi

codesign --force --options runtime --timestamp \
    --entitlements "$ROOT/Ports.entitlements" \
    --sign "${CODESIGN_IDENTITY:--}" "$APP"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
fi

echo "Built $APP and $ZIP"
