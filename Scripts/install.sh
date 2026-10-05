#!/bin/bash
# Install the built app to ~/Applications and keep a Desktop shortcut
# (symlink) pointing at it, so rebuilds only need this script re-run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MacPulse"
INSTALL_DIR="$HOME/Applications"
DESKTOP_DIR="$HOME/Desktop"
DESKTOP_LINK="$DESKTOP_DIR/$APP_NAME"

if [[ -d "$DESKTOP_LINK" && ! -L "$DESKTOP_LINK" ]]; then
    echo "error: $DESKTOP_LINK exists as a real directory; move it aside first" >&2
    exit 1
fi
mkdir -p "$INSTALL_DIR" "$DESKTOP_DIR"

"$ROOT/Scripts/package-app.sh"

rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$ROOT/dist/$APP_NAME.app" "$INSTALL_DIR/$APP_NAME.app"

ln -sfn "$INSTALL_DIR/$APP_NAME.app" "$DESKTOP_LINK"

plutil -lint "$INSTALL_DIR/$APP_NAME.app/Contents/Info.plist"
printf 'Installed %s\nDesktop shortcut: %s\n' "$INSTALL_DIR/$APP_NAME.app" "$DESKTOP_LINK"
