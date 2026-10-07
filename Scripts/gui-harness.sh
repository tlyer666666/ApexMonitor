#!/bin/bash
# Build and run the MacPulse UI acceptance harness against an isolated
# history directory, so GUI verification never touches real user data.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
HISTORY_DIR="${1:-$ROOT/.build/audit/gui-history}"
OUTPUT="$ROOT/.build/audit/MacPulseUITest"
mkdir -p "$HISTORY_DIR" "$(dirname "$OUTPUT")"

swiftc -D MACPULSE_INTEGRATION -warnings-as-errors -O -target arm64-apple-macos13.0 \
  -framework AppKit -framework SwiftUI -framework IOKit \
  Sources/MacPulseCore/*.swift \
  Sources/MacPulseApp/Monitoring/*.swift \
  Sources/MacPulseApp/LaunchAtLogin.swift \
  Sources/MacPulseApp/AppSettings.swift \
  Sources/MacPulseApp/Views/*.swift \
  Sources/MacPulseApp/AppDelegate.swift \
  Tests/MacPulseIntegrationTests/GUIHarness.swift \
  -o "$OUTPUT"

printf 'Built %s\nLaunching with history dir %s\n' "$OUTPUT" "$HISTORY_DIR"
"$OUTPUT" "$HISTORY_DIR"
