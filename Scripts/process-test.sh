#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT/.build/audit/process-tests"
mkdir -p "$OUTPUT_DIR"

swiftc -O -target arm64-apple-macos13.0 \
  -module-cache-path "$OUTPUT_DIR/module-cache" \
  "$ROOT/Sources/MacPulseCore/ProcessTable.swift" \
  "$ROOT/Sources/MacPulseApp/Monitoring/ProcessSampler.swift" \
  "$ROOT/Tests/MacPulseCoreTests/TestMain.swift" \
  "$ROOT/Tests/MacPulseCoreTests/ProcessTableTests.swift" \
  "$ROOT/Tests/MacPulseProcessTests/Main.swift" \
  -o "$OUTPUT_DIR/macpulse-process-tests"
"$OUTPUT_DIR/macpulse-process-tests" --core
"$OUTPUT_DIR/macpulse-process-tests"
