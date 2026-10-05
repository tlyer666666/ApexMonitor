#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p .build/integration
COMMON=(Sources/MacPulseCore/*.swift Sources/MacPulseApp/Monitoring/*.swift Sources/MacPulseApp/Views/MetricCategory.swift)
for suite in LifecycleTests SamplingTests HistoryRepositoryTests HistoryRecorderTests; do
    printf '\n--- %s ---\n' "$suite"
    swiftc -warnings-as-errors -O -target "$(uname -m)-apple-macos13.0" \
      -framework AppKit -framework SwiftUI -framework IOKit \
      "${COMMON[@]}" "Tests/MacPulseIntegrationTests/$suite.swift" \
      -o ".build/integration/$suite"
    ".build/integration/$suite"
done
python3 Tests/Scripts/install_test.py
