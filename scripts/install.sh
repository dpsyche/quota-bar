#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
INSTALL_DIRECTORY="${QUOTABAR_INSTALL_DIR:-$HOME/Applications}"
LAUNCH=1

if [[ "${1:-}" == "--no-launch" ]]; then
  LAUNCH=0
elif [[ $# -gt 0 ]]; then
  echo "usage: $0 [--no-launch]" >&2
  exit 2
fi

APP="$("$ROOT/scripts/build-app.sh")"
DESTINATION="$INSTALL_DIRECTORY/QuotaBar.app"
mkdir -p "$INSTALL_DIRECTORY"
rm -rf "$DESTINATION"
ditto "$APP" "$DESTINATION"

if [[ $LAUNCH -eq 1 ]]; then
  open "$DESTINATION"
fi

echo "Installed Quota Bar at $DESTINATION"
