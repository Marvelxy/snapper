#!/usr/bin/env bash
#
# Packages an already-built build/Snapper.app into a DMG with a real install
# screen: a branded background, the app icon and an Applications drop target,
# laid out exactly like a Mac app installer window.
#
# Usage:
#   Scripts/build-dmg.sh [output.dmg]
#
# The app bundle must exist first (`make app`, or Scripts/build-app.sh).
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Snapper"
VOLUME_NAME="Snapper"
# Unique name for the writable work image: Finder resolves "disk <name>", so a
# second mounted Snapper image (e.g. the one the user installed from) must not
# be able to shadow it. Renamed to $VOLUME_NAME before the image is finalized.
WORK_VOLUME_NAME="Snapper Install"
APP_BUNDLE="$ROOT_DIR/build/$APP_NAME.app"

if [[ $# -ge 1 ]]; then
    OUTPUT="$1"
    case "$OUTPUT" in
        /*) ;;
        *) OUTPUT="$PWD/$OUTPUT" ;;
    esac
else
    OUTPUT="$ROOT_DIR/build/$APP_NAME-macOS.dmg"
fi

# Window layout constants (points). Keep in sync with
# Scripts/make-dmg-background.swift.
WINDOW_WIDTH=660
WINDOW_HEIGHT=420
WINDOW_LEFT=200
WINDOW_TOP=120
APP_ICON_X=165
APP_ICON_Y=200
APPS_ICON_X=495
APPS_ICON_Y=200

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "error: $APP_BUNDLE not found — run 'make app' first" >&2
    exit 1
fi

STAGING_DIR="$ROOT_DIR/build/dmg-staging"
BACKGROUND_DIR="$STAGING_DIR/.background"
TEMP_DMG="$ROOT_DIR/build/$APP_NAME-rw.dmg"
MOUNT_POINT="/Volumes/$WORK_VOLUME_NAME"

if [[ -d "$MOUNT_POINT" ]]; then
    echo "error: $MOUNT_POINT is already mounted — eject it and retry" >&2
    exit 1
fi

cleanup() {
    hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> Staging $APP_NAME.app with an Applications drop target"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$BACKGROUND_DIR"
# ditto keeps the code signature and extended attributes intact.
ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Rendering install window background"
swift "$ROOT_DIR/Scripts/make-dmg-background.swift" "$BACKGROUND_DIR/background.png" 1
swift "$ROOT_DIR/Scripts/make-dmg-background.swift" "$BACKGROUND_DIR/background@2x.png" 2
# Finder picks up the @2x variant when the file carries a 144 dpi hint.
sips -s dpiWidth 144 -s dpiHeight 144 "$BACKGROUND_DIR/background@2x.png" >/dev/null

echo "==> Creating writable image"
rm -f "$TEMP_DMG" "$OUTPUT"
hdiutil create \
    -volname "$WORK_VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -fs HFS+ \
    -format UDRW \
    -ov "$TEMP_DMG" >/dev/null

echo "==> Mounting"
hdiutil attach -readwrite -noverify -noautoopen "$TEMP_DMG" >/dev/null
sleep 1

echo "==> Laying out the install screen"
# Finder stores icon positions, background and window size in the volume's
# .DS_Store, so the window opens like this for everyone who mounts the DMG.
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$WORK_VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {$WINDOW_LEFT, $WINDOW_TOP, $((WINDOW_LEFT + WINDOW_WIDTH)), $((WINDOW_TOP + WINDOW_HEIGHT))}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 12
        set background picture of viewOptions to file ".background:background.png"
        set position of item "$APP_NAME.app" to {$APP_ICON_X, $APP_ICON_Y}
        set position of item "Applications" to {$APPS_ICON_X, $APPS_ICON_Y}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

echo "==> Finalizing"
# Finder wrote the layout into the work volume's .DS_Store. Carry it back into
# the staging folder, then build the final image under the real volume name.
cp "$MOUNT_POINT/.DS_Store" "$STAGING_DIR/.DS_Store"
sync
sleep 1

# Finder can hold the volume briefly after the window closes.
for attempt in 1 2 3 4 5; do
    if hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1; then
        break
    fi
    echo "    waiting for $MOUNT_POINT to unmount (attempt $attempt)"
    sync
    sleep 2
done
if [[ -d "$MOUNT_POINT" ]]; then
    echo "error: could not unmount $MOUNT_POINT" >&2
    exit 1
fi
trap - EXIT

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov "$OUTPUT" >/dev/null
rm -f "$TEMP_DMG"
rm -rf "$STAGING_DIR"

echo "==> Done: $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
