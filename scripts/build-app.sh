#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CONFIGURATION="${1:-debug}"
if (( $# > 1 )); then
    echo "Usage: $0 [debug|release]" >&2
    exit 2
fi
case "$CONFIGURATION" in
    debug|release) ;;
    *) echo "Usage: $0 [debug|release]" >&2; exit 2 ;;
esac
swift build --configuration "$CONFIGURATION" --product TiebaPureMac --arch arm64
BIN_DIR="$(swift build --configuration "$CONFIGURATION" --arch arm64 --show-bin-path)"

OUTPUT="$ROOT/artifacts/macos"
mkdir -p "$OUTPUT"
STAGE="$(mktemp -d "$OUTPUT/.package.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/TiebaPure-Mac.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/TiebaPureMac" "$APP/Contents/MacOS/"

ICONSET="$STAGE/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
icon_revision="$(shasum -a 256 Resources/AppIcon.png | cut -c1-12)"
icon_file="AppIcon-$icon_revision.icns"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/$icon_file"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -insert CFBundleIconFile -string "$icon_file" "$APP/Contents/Info.plist"
cp -R Resources/zh-Hans.lproj Resources/PrivacyInfo.xcprivacy LICENSE LICENSES/*.txt NOTICE.md "$APP/Contents/Resources/"
for resource in "$BIN_DIR"/*.bundle; do
    [[ -d "$resource" ]] || continue
    cp -R "$resource" "$APP/Contents/Resources/"
done
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework \
    "$APP/Contents/Frameworks/Sparkle.framework"

PUBLIC_KEY=""
if [[ "$CONFIGURATION" == release ]]; then
    PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-}"
    if [[ -z "$PUBLIC_KEY" && -f "Resources/SparklePublicKey.txt" ]]; then
        PUBLIC_KEY="$(tr -d ' \n\r\t' < Resources/SparklePublicKey.txt)"
    fi
fi

if [[ -n "$PUBLIC_KEY" ]]; then
    python3 - "$APP/Contents/Info.plist" "$PUBLIC_KEY" <<'PY'
import base64
import plistlib
import sys
from pathlib import Path

key = sys.argv[2]
try:
    if len(base64.b64decode(key, validate=True)) != 32:
        raise ValueError
except ValueError:
    raise SystemExit("Sparkle public key must be a base64 Ed25519 public key")

path = Path(sys.argv[1])
info = plistlib.loads(path.read_bytes())
info.update(
    SUFeedURL="https://github.com/yamakze/TiebaPure-Mac/releases/latest/download/appcast.xml",
    SUPublicEDKey=key,
    SUEnableAutomaticChecks=True,
    SUAutomaticallyUpdate=False,
    SUVerifyUpdateBeforeExtraction=True,
    SURequireSignedFeed=True,
)
path.write_bytes(plistlib.dumps(info))
PY
fi

plutil -lint "$APP/Contents/Info.plist" "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
IDENTITY="${CODE_SIGN_IDENTITY:--}"
SIGN_OPTIONS=(--timestamp=none)
if [[ "$IDENTITY" != - ]]; then
    SIGN_OPTIONS=(--options runtime --timestamp)
fi
framework="$APP/Contents/Frameworks/Sparkle.framework"
version="$framework/Versions/Current"
for component in "$version/XPCServices/Installer.xpc" "$version/XPCServices/Downloader.xpc" \
                 "$version/Autoupdate" "$version/Updater.app" "$framework"; do
    codesign --force --sign "$IDENTITY" "${SIGN_OPTIONS[@]}" --preserve-metadata=entitlements "$component"
done
ENTITLEMENTS="Resources/TiebaPureMac.entitlements"
APP_SIGN_OPTIONS=("${SIGN_OPTIONS[@]}")
if [[ -f "$ENTITLEMENTS" ]]; then
    APP_SIGN_OPTIONS+=(--entitlements "$ENTITLEMENTS")
fi
codesign --force --sign "$IDENTITY" "${APP_SIGN_OPTIONS[@]}" "$APP"
codesign --verify --deep --strict "$APP"

TARGET="$OUTPUT/TiebaPure-Mac.app"
if [[ -d "$TARGET" ]]; then mv "$TARGET" "$STAGE/previous.app"; fi
if ! mv "$APP" "$TARGET"; then
    if [[ -d "$STAGE/previous.app" ]]; then mv "$STAGE/previous.app" "$TARGET"; fi
    exit 1
fi
echo "$TARGET"
