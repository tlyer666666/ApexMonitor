#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

"$ROOT/Scripts/build.sh" release
APP="$ROOT/dist/MacPulse.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"

rm -rf "$APP"
mkdir -p "$MACOS"
cp "$ROOT/.build/release/MacPulse" "$MACOS/MacPulse"
chmod 755 "$MACOS/MacPulse"

"$ROOT/Scripts/make-icon.sh"
RES="$CONTENTS/Resources"
mkdir -p "$RES"
cp "$ROOT/.build/icon/MacPulse.icns" "$RES/MacPulse.icns"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIconFile</key>
    <string>MacPulse</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>MacPulse</string>
    <key>CFBundleIdentifier</key>
    <string>com.macpulse.monitor</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MacPulse</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Version defaults come from git so local bundles are traceable; CI passes
# MACPULSE_VERSION explicitly (see the release workflow).
if [[ -z "${MACPULSE_VERSION:-}" ]]; then
    MACPULSE_VERSION="$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null || true)"
    MACPULSE_VERSION="${MACPULSE_VERSION#v}"
fi
if [[ -z "${MACPULSE_BUILD:-}" ]]; then
    MACPULSE_BUILD="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || true)"
fi
VERSION="${MACPULSE_VERSION:-1.0.0}"
BUILD="${MACPULSE_BUILD:-1}"
if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){0,3}$ ]] || [[ ! "$BUILD" =~ ^[0-9]+$ ]]; then
    printf 'error: invalid version %s / build %s\n' "$VERSION" "$BUILD" >&2
    exit 1
fi
/usr/libexec/PlistBuddy \
    -c "Set :CFBundleShortVersionString $VERSION" \
    -c "Set :CFBundleVersion $BUILD" \
    "$CONTENTS/Info.plist"

plutil -lint "$CONTENTS/Info.plist"
printf 'Packaged %s (%s build %s)\n' "$APP" "$VERSION" "$BUILD"
