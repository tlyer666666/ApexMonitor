#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUTPUT=".build/tests/macpulse-core-tests"
mkdir -p "$(dirname "$OUTPUT")"

swiftc \
  Sources/MacPulseCore/MetricTypes.swift \
  Sources/MacPulseCore/MetricsCalculator.swift \
  Sources/MacPulseCore/MetricsFormatter.swift \
  Sources/MacPulseCore/MetricCounter.swift \
  Sources/MacPulseCore/NetworkCounterAccumulator.swift \
  Sources/MacPulseCore/MemoryTrendGeometry.swift \
  Sources/MacPulseCore/MetricsHistory.swift \
  Sources/MacPulseCore/HistoryPersistence.swift \
  Tests/MacPulseCoreTests/TestMain.swift \
  Tests/MacPulseCoreTests/MetricsCalculatorTests.swift \
  Tests/MacPulseCoreTests/MetricsFormatterTests.swift \
  Tests/MacPulseCoreTests/MetricBoundaryTests.swift \
  Tests/MacPulseCoreTests/MetricsHistoryTests.swift \
  Tests/MacPulseCoreTests/main.swift \
  -o "$OUTPUT"
"$OUTPUT"
