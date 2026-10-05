#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MacPulse"
INSTALL_DIR="$HOME/Applications"
DESKTOP_DIR="$HOME/Desktop"
DESKTOP_LINK="$DESKTOP_DIR/$APP_NAME"
DESTINATION="$INSTALL_DIR/$APP_NAME.app"
SOURCE="$ROOT/dist/$APP_NAME.app"
IDENTIFIER="com.macpulse.monitor"

if [[ -e "$DESKTOP_LINK" && ! -L "$DESKTOP_LINK" ]]; then
    printf 'error: refusing to replace existing Desktop item: %s\n' "$DESKTOP_LINK" >&2
    exit 1
fi
if [[ -L "$DESKTOP_LINK" && "$(readlink "$DESKTOP_LINK")" != "$DESTINATION" ]]; then
    printf 'error: Desktop shortcut points elsewhere: %s\n' "$DESKTOP_LINK" >&2
    exit 1
fi
if [[ -e "$DESTINATION" || -L "$DESTINATION" ]]; then
    if [[ -L "$DESTINATION" ]] || [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DESTINATION/Contents/Info.plist" 2>/dev/null || true)" != "$IDENTIFIER" ]]; then
        printf 'error: refusing to replace unrelated install destination: %s\n' "$DESTINATION" >&2
        exit 1
    fi
fi

"$ROOT/Scripts/package-app.sh"
plutil -lint "$SOURCE/Contents/Info.plist"
[[ -x "$SOURCE/Contents/MacOS/$APP_NAME" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE/Contents/Info.plist")" == "$IDENTIFIER" ]]
mkdir -p "$INSTALL_DIR" "$DESKTOP_DIR"
STAGING="$(mktemp -d "$INSTALL_DIR/.macpulse-install.XXXXXX")"
BACKUP="$STAGING/previous.app"
cleanup() {
    local status=$?
    if [[ ! -e "$DESTINATION" && -d "$BACKUP" ]]; then
        mv "$BACKUP" "$DESTINATION"
    fi
    rm -rf "$STAGING"
    exit "$status"
}
trap cleanup EXIT
cp -R "$SOURCE" "$STAGING/$APP_NAME.app"
plutil -lint "$STAGING/$APP_NAME.app/Contents/Info.plist"
if [[ -d "$DESTINATION" ]]; then
    mv "$DESTINATION" "$BACKUP"
fi
mv "$STAGING/$APP_NAME.app" "$DESTINATION"
if [[ ! -L "$DESKTOP_LINK" ]]; then
    ln -s "$DESTINATION" "$DESKTOP_LINK"
fi
printf 'Installed %s\nDesktop shortcut: %s\n' "$DESTINATION" "$DESKTOP_LINK"
