#!/bin/bash
# Build a distributable DMG from the packaged app bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

"$ROOT/Scripts/package-app.sh"

DMG="$ROOT/dist/MacPulse.dmg"
VOLNAME="MacPulse"

rm -f "$DMG"
hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$ROOT/dist/MacPulse.app" \
  -ov \
  -format UDZO \
  "$DMG"

printf 'DMG written to %s\n' "$DMG"
