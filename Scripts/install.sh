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
SWAPPED=0
COMMITTED=0
# The install commits when the desktop shortcut exists. Any earlier failure
# rolls the destination back to the backup, so a failed run never leaves a
# half-updated install nor destroys the previous version.
cleanup() {
    local status=$?
    if (( status != 0 && COMMITTED == 0 )) && [[ -d "$BACKUP" ]]; then
        if [[ -e "$DESTINATION" || -L "$DESTINATION" ]]; then
            rm -rf "$DESTINATION"
        fi
        if mv "$BACKUP" "$DESTINATION"; then
            printf 'error: install failed; previous version restored\n' >&2
        else
            printf 'error: install failed; could not restore; previous version kept at %s\n' "$BACKUP" >&2
            exit "$status"
        fi
    elif (( status != 0 && COMMITTED == 0 && SWAPPED == 1 )); then
        # No previous install to restore: remove the partial new app.
        rm -rf "$DESTINATION"
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
if mv "$STAGING/$APP_NAME.app" "$DESTINATION"; then
    SWAPPED=1
fi
if (( SWAPPED == 1 )); then
    if [[ ! -L "$DESKTOP_LINK" ]]; then
        ln -s "$DESTINATION" "$DESKTOP_LINK"
    fi
    COMMITTED=1
fi
printf 'Installed %s\nDesktop shortcut: %s\n' "$DESTINATION" "$DESKTOP_LINK"
