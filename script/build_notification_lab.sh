#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAB_NAME="Sched Notification Lab"
LAB_BUNDLE="$ROOT_DIR/Build/$LAB_NAME.app"
LAB_BINARY="$LAB_BUNDLE/Contents/MacOS/SchedLab"
INSTALL_BUNDLE="/Applications/$LAB_NAME.app"

cd "$ROOT_DIR"
./script/build_and_run.sh --build
mkdir -p "$LAB_BUNDLE/Contents/MacOS" "$LAB_BUNDLE/Contents/Resources"
cp "$ROOT_DIR/Build/Sched.app/Contents/MacOS/Sched" "$LAB_BINARY"
cp "$ROOT_DIR/Support/NotificationLab-Info.plist" "$LAB_BUNDLE/Contents/Info.plist"
if [[ -f "$ROOT_DIR/Build/Sched.app/Contents/Resources/AppIcon.icns" ]]; then
    cp "$ROOT_DIR/Build/Sched.app/Contents/Resources/AppIcon.icns" "$LAB_BUNDLE/Contents/Resources/AppIcon.icns"
fi
codesign --force --sign - --deep "$LAB_BUNDLE" >/dev/null

if [[ ! -e "$INSTALL_BUNDLE" ]]; then
    cp -R "$LAB_BUNDLE" "/Applications/"
else
    ditto "$LAB_BUNDLE" "$INSTALL_BUNDLE"
fi
/usr/bin/open -n "$INSTALL_BUNDLE"
