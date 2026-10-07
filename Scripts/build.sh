#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIGURATION="${1:-release}"
OUTPUT_DIR=".build/$CONFIGURATION"
BINARY="$OUTPUT_DIR/MacPulse"

mkdir -p "$OUTPUT_DIR"

if [[ "$CONFIGURATION" == "release" ]]; then
  OPTIMIZATION=(-O)
else
  OPTIMIZATION=(-Onone -g)
fi

swiftc "${OPTIMIZATION[@]}" \
  -target arm64-apple-macos13.0 \
  -framework AppKit \
  -framework SwiftUI \
  -framework IOKit \
  Sources/MacPulseCore/*.swift \
  Sources/MacPulseApp/Monitoring/*.swift \
  Sources/MacPulseApp/LaunchAtLogin.swift \
  Sources/MacPulseApp/Views/*.swift \
  Sources/MacPulseApp/AppDelegate.swift \
  -o "$BINARY"

printf 'Built %s\n' "$ROOT/$BINARY"
