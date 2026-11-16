#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CONFIGURATION="${1:-debug}"
case "$CONFIGURATION" in debug|release) ;; *) echo "Usage: $0 [debug|release]" >&2; exit 2 ;; esac
swift build --configuration "$CONFIGURATION" --product TiebaPureMac
BIN_DIR="$(swift build --configuration "$CONFIGURATION" --show-bin-path)"
APP="$ROOT/build/TiebaPure-Mac.app"
# Only replace this generated output, never installed applications.
if [[ -d "$APP" ]]; then rm -rf "$APP"; fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/TiebaPureMac" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/PrivacyInfo.xcprivacy LICENSE LICENSES/SwiftProtobuf-Apache-2.0.txt NOTICE.md "$APP/Contents/Resources/"
for resource in "$BIN_DIR"/*.bundle; do
    [[ -d "$resource" ]] || continue
    cp -R "$resource" "$APP/Contents/Resources/"
done
plutil -lint "$APP/Contents/Info.plist" "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
# Ad-hoc signing is local validation, not Developer ID signing or notarization.
codesign --force --sign "${CODE_SIGN_IDENTITY:--}" "$APP"
codesign --verify --strict "$APP"
echo "$APP"
