#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT_DIRECTORY="$ROOT/build"
APP="$OUTPUT_DIRECTORY/QuotaBar.app"

case "$CONFIGURATION" in
  debug|release) ;;
  *) echo "CONFIGURATION must be debug or release" >&2; exit 2 ;;
esac

swift build --package-path "$ROOT" --configuration "$CONFIGURATION" --product QuotaBar >&2
BIN_DIRECTORY="$(swift build --package-path "$ROOT" --configuration "$CONFIGURATION" --show-bin-path)"
BINARY="$BIN_DIRECTORY/QuotaBar"

test -x "$BINARY"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/QuotaBar"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

plutil -lint "$APP/Contents/Info.plist" >/dev/null
codesign --force --sign - --timestamp=none "$APP" >/dev/null
codesign --verify --deep --strict "$APP"

echo "$APP"
