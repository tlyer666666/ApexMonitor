#!/bin/bash
# Swift 6 language mode with complete concurrency checking. This is a
# separate gate from the release build, which still compiles in the
# compiler's default language mode.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -typecheck \
  -target arm64-apple-macos13.0 \
  -framework AppKit -framework SwiftUI -framework IOKit \
  Sources/MacPulseCore/*.swift \
  Sources/MacPulseApp/Monitoring/*.swift \
  Sources/MacPulseApp/LaunchAtLogin.swift \
  Sources/MacPulseApp/AppSettings.swift \
  Sources/MacPulseApp/Views/*.swift \
  Sources/MacPulseApp/AppDelegate.swift

printf 'Swift 6 strict concurrency typecheck OK\n'
