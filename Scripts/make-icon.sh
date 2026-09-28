#!/bin/bash
# Render the MacPulse app icon and bundle it as .icns for packaging.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICONSET="$ROOT/.build/icon/MacPulse.iconset"
ICNS="$ROOT/.build/icon/MacPulse.icns"

swift "$ROOT/Scripts/make-icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$ICNS"
printf 'icns written to %s\n' "$ICNS"
