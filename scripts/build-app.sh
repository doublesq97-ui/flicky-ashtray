#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_NAME="Flicky Ashtray"
EXECUTABLE="FlickyAshtray"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Packaging/Info.plist")"
ARCH="${FLICKY_MAC_ARCH:-arm64}"
SIGN_IDENTITY="${FLICKY_SIGN_IDENTITY:--}"
NOTARY_PROFILE="${FLICKY_NOTARY_PROFILE:-}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/Flicky-Ashtray-$VERSION-$ARCH.dmg"
STAGE_DIR="$ROOT_DIR/tmp/dmg-stage"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"
"$ROOT_DIR/scripts/build-app-icon.sh"
swift build -c release --arch "$ARCH"
BIN_DIR="$(swift build -c release --arch "$ARCH" --show-bin-path)"

rm -rf "$APP_DIR" "$STAGE_DIR" "$DIST_DIR/dmg-stage"
rm -f "$DIST_DIR/.DS_Store"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_DIR/$EXECUTABLE" "$MACOS_DIR/$EXECUTABLE"
cp "$ROOT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/assets/ashtray.png" "$RESOURCES_DIR/ashtray.png"
cp "$ROOT_DIR/assets/ash-sprinkle.png" "$RESOURCES_DIR/ash-sprinkle.png"
cp "$ROOT_DIR/assets/ash-full.png" "$RESOURCES_DIR/ash-full.png"
cp "$ROOT_DIR/assets/ash-over.png" "$RESOURCES_DIR/ash-over.png"
cp "$ROOT_DIR/assets/ash-filthy.png" "$RESOURCES_DIR/ash-filthy.png"
cp "$ROOT_DIR/assets/cigarette.png" "$RESOURCES_DIR/cigarette.png"
cp "$ROOT_DIR/Packaging/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
cp "$ROOT_DIR/LICENSE" "$RESOURCES_DIR/LICENSE.txt"
cp "$ROOT_DIR/assets/LICENSE.md" "$RESOURCES_DIR/ASSET-LICENSE.md"
chmod +x "$MACOS_DIR/$EXECUTABLE"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --deep --options runtime --sign - "$APP_DIR"
else
    codesign --force --deep --timestamp --options runtime --sign "$SIGN_IDENTITY" "$APP_DIR"
fi
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

# `(N)` makes an unmatched glob expand to nothing in zsh, so the very first
# clean build works just as reliably as a rebuild with an older DMG present.
rm -f "$DIST_DIR"/Flicky-Ashtray-*.dmg(N)
mkdir -p "$STAGE_DIR"
ditto "$APP_DIR" "$STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$STAGE_DIR/Applications"
mkdir -p "$STAGE_DIR/Licenses"
cp "$ROOT_DIR/LICENSE" "$STAGE_DIR/Licenses/POLYFORM-NONCOMMERCIAL-1.0.0.txt"
cp "$ROOT_DIR/assets/LICENSE.md" "$STAGE_DIR/Licenses/AI-ASSETS-CC-BY-NC-4.0.md"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH"
rm -rf "$STAGE_DIR"
hdiutil verify "$DMG_PATH"

if [[ -n "$NOTARY_PROFILE" ]]; then
    if [[ "$SIGN_IDENTITY" == "-" ]]; then
        print -u2 "Apple 公证要求 Developer ID 签名；请同时设置 FLICKY_SIGN_IDENTITY。"
        exit 1
    fi
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
    hdiutil verify "$DMG_PATH"
fi

print "Built $APP_DIR"
print "Built $DMG_PATH"
