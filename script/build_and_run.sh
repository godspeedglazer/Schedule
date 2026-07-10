#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Sched"
BUNDLE_ID="com.erichspringer.sched"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -x "Keen" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
swift build
BUILD_DIR="$(swift build --show-bin-path)"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_DIR/Keen" "$APP_BINARY"
cp "$ROOT_DIR/Support/Info.plist" "$APP_CONTENTS/Info.plist"
chmod +x "$APP_BINARY"

ICON_SOURCE="$ROOT_DIR/Sources/Keen/Resources/AppIcon.svg"
ICON_THUMBNAILS="$DIST_DIR/icon-render"
ICONSET="$DIST_DIR/AppIcon.iconset"
rm -rf "$ICON_THUMBNAILS" "$ICONSET"
mkdir -p "$ICON_THUMBNAILS" "$ICONSET"
qlmanage -t -s 1024 -o "$ICON_THUMBNAILS" "$ICON_SOURCE" >/dev/null
ICON_MASTER="$ICON_THUMBNAILS/AppIcon.svg.png"
make_icon() {
    local pixels="$1"
    local name="$2"
    sips -z "$pixels" "$pixels" "$ICON_MASTER" --out "$ICONSET/$name" >/dev/null
}
make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
cp "$ICON_MASTER" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$APP_RESOURCES/AppIcon.icns"

RESOURCE_BUNDLE="$(find "$BUILD_DIR" -maxdepth 1 -type d -name 'Keen_Keen.bundle' -print -quit)"
if [[ -n "$RESOURCE_BUNDLE" ]]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCES/"
fi

codesign --force --sign - --deep "$APP_BUNDLE" >/dev/null

open_app() {
    /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
    run)
        open_app
        ;;
    --debug|debug)
        lldb -- "$APP_BINARY"
        ;;
    --logs|logs)
        open_app
        /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
        ;;
    --telemetry|telemetry)
        open_app
        /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
        ;;
    --verify|verify)
        open_app
        sleep 1
        pgrep -x "$APP_NAME" >/dev/null
        ;;
    --build|build)
        ;;
    *)
        echo "usage: $0 [run|--build|--debug|--logs|--telemetry|--verify]" >&2
        exit 2
        ;;
esac
