#!/bin/bash
# Requires a logged-in macOS GUI session, not Screen Recording or Accessibility grants.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
if [[ $# -gt 1 || ($# -eq 1 && "$1" != --manual) ]]; then
  echo "Usage: $0 [--manual]" >&2; exit 2
fi
mkdir -p "$ROOT/build"
LAB="$(mktemp -d "$ROOT/build/native-label.XXXXXX")"
APP="$LAB/QuotaBarNativeTest.app"
mkdir -p "$APP/Contents/MacOS"
swift build --package-path "$ROOT" --scratch-path "$ROOT/build/native-test-package" \
  --product QuotaBar -Xswiftc -DQUOTABAR_NATIVE_TEST >&2
BIN="$(swift build --package-path "$ROOT" --scratch-path "$ROOT/build/native-test-package" --show-bin-path)"
cp "$BIN/QuotaBar" "$APP/Contents/MacOS/QuotaBar"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier local.QuotaBar.NativeTest.$(uuidgen)" "$APP/Contents/Info.plist"
cp "$ROOT/Tests/QuotaBarCoreTests/Fixtures/quota-v3.json" "$LAB/fixture.json"
printf '#!/bin/bash\nsleep 3\n/bin/cat "%s/fixture.json"\n' "$LAB" > "$LAB/collector"
chmod +x "$LAB/collector"
codesign --force --sign - --timestamp=none "$APP" >&2
codesign --verify --deep --strict "$APP"
if [[ "${1:-}" == --manual ]]; then
  open -n "$APP" --args "$LAB" --manual
  echo "Manual synthetic app: $APP"
  echo "Quit this probe from its popover when finished. Installed app is untouched."
  exit 0
fi
# -W waits only for this isolated, self-terminating app. External watchdog bounds launch too.
open -n -W "$APP" --args "$LAB" &
LAUNCH=$!
for ((i=0; i<20; i++)); do
  if ! kill -0 "$LAUNCH" 2>/dev/null; then break; fi
  sleep 1
done
if kill -0 "$LAUNCH" 2>/dev/null; then
  kill "$LAUNCH" # Only our open waiter, never another QuotaBar process.
  echo "FAIL launch deadline; evidence: $LAB" >&2
  exit 1
fi
wait "$LAUNCH"
if [[ -f "$LAB/result.log" ]]; then /bin/cat "$LAB/result.log"; fi
echo "Native evidence (synthetic bundle/cache): $LAB"
grep -q '^PASS native label regression' "$LAB/result.log"
