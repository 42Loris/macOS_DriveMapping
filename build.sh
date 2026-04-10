#!/bin/bash
# build.sh — packages everything with munkipkg.
# The pre-built DriveMapping.app is committed to the repo at src/DriveMapping.app.
# Run with no arguments — the script will prompt for all options interactively.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="DriveMapping"
APP_SOURCE="$REPO_DIR/src/$APP_NAME.app"
APP_BUNDLE="$REPO_DIR/pkg/payload/Applications/$APP_NAME.app"
read -r -p "Rebuild app from Swift source? [y/N] " _rebuild
[[ "$_rebuild" =~ ^[Yy]$ ]] && REBUILD=true || REBUILD=false

read -r -p "Sign the app? [y/N] " _sign
if [[ "$_sign" =~ ^[Yy]$ ]]; then
    read -r -p "Developer ID Application (e.g. 'Developer ID Application: Name (TEAMID)'): " DEVELOPER_ID
else
    DEVELOPER_ID=""
fi

read -r -p "Sign the package? [y/N] " _signpkg
if [[ "$_signpkg" =~ ^[Yy]$ ]]; then
    read -r -p "Developer ID Installer (e.g. 'Developer ID Installer: Name (TEAMID)'): " INSTALLER_ID
else
    INSTALLER_ID=""
fi

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
    cp "$SPM_DIR/Resources/DriveMapping.icns" "$APP_SOURCE/Contents/Resources/"

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

echo "→ Cleaning up payload..."
rm -rf "$APP_BUNDLE"

PKG=$(ls "$REPO_DIR/pkg/build/"*.pkg 2>/dev/null | head -1)

if [[ -n "$INSTALLER_ID" ]]; then
    SIGNED_PKG="${PKG%.pkg}-signed.pkg"
    echo "→ Signing package with: $INSTALLER_ID"
    productsign --sign "$INSTALLER_ID" "$PKG" "$SIGNED_PKG"
    echo "✓ Done — signed package at pkg/build/$(basename "$SIGNED_PKG")"
else
    echo "✓ Done — package at pkg/build/$(basename "$PKG")"
fi
