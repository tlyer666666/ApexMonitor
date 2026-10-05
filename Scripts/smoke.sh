#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUTPUT=".build/smoke/macpulse-sensor-smoke"
mkdir -p "$(dirname "$OUTPUT")"

swiftc -O -target arm64-apple-macos13.0 -framework IOKit \
  Sources/MacPulseCore/*.swift \
  Sources/MacPulseApp/Monitoring/SystemMetricsReader.swift \
  Tests/MacPulseAppSmoke/main.swift \
  -o "$OUTPUT"
"$OUTPUT"
