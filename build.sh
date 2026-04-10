#!/bin/bash
# build.sh — packages everything with munkipkg.
# The pre-built DriveMapping.app is committed to the repo at src/DriveMapping.app.
# To rebuild the app from source: ./build.sh --rebuild-app [--sign "Developer ID Application: ..."]

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="DriveMapping"
APP_SOURCE="$REPO_DIR/src/$APP_NAME.app"
APP_BUNDLE="$REPO_DIR/pkg/payload/Applications/$APP_NAME.app"
REBUILD=false
DEVELOPER_ID=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --rebuild-app) REBUILD=true; shift ;;
        --sign) DEVELOPER_ID="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if [[ "$REBUILD" == true ]]; then
    SPM_DIR="$REPO_DIR/src/menubar"
    BINARY="$SPM_DIR/.build/release/$APP_NAME"

    echo "→ Building Swift menu bar app..."
    cd "$SPM_DIR"
    swift build -c release

    echo "→ Assembling .app bundle..."
    rm -rf "$APP_SOURCE"
    mkdir -p "$APP_SOURCE/Contents/MacOS"
    mkdir -p "$APP_SOURCE/Contents/Resources"
    cp "$BINARY"                        "$APP_SOURCE/Contents/MacOS/$APP_NAME"
    cp "$SPM_DIR/Resources/Info.plist"  "$APP_SOURCE/Contents/Info.plist"

    if [[ -n "$DEVELOPER_ID" ]]; then
        echo "→ Signing with: $DEVELOPER_ID"
        codesign --force --options runtime --sign "$DEVELOPER_ID" "$APP_SOURCE"
    fi

    echo "→ App rebuilt at src/$APP_NAME.app — commit it to the repo to update the baseline."
fi

echo "→ Copying .app into payload..."
mkdir -p "$(dirname "$APP_BUNDLE")"
rm -rf "$APP_BUNDLE"
cp -R "$APP_SOURCE" "$APP_BUNDLE"

echo "→ Building package with munkipkg..."
munkipkg "$REPO_DIR/pkg/"

PKG=$(ls "$REPO_DIR/pkg/build/"*.pkg 2>/dev/null | head -1)
echo "✓ Done — package at pkg/build/$(basename "$PKG")"
