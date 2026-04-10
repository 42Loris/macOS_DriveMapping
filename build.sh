#!/bin/bash
# build.sh — builds the menu bar app and packages everything with munkipkg.
# Usage: ./build.sh [--sign "Developer ID Application: Your Name (TEAMID)"]

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="DriveMapping"
SPM_DIR="$REPO_DIR/MenuBarApp"
BINARY="$SPM_DIR/.build/release/$APP_NAME"
APP_BUNDLE="$REPO_DIR/payload/Applications/$APP_NAME.app"
DEVELOPER_ID="${2:-}"  # optional: pass --sign "Developer ID Application: ..."

# Parse --sign argument
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sign) DEVELOPER_ID="$2"; shift 2 ;;
        *) shift ;;
    esac
done

echo "→ Building Swift app..."
cd "$SPM_DIR"
swift build -c release

echo "→ Assembling .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY"                        "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$SPM_DIR/Resources/Info.plist"  "$APP_BUNDLE/Contents/Info.plist"

# Optional code signing
if [[ -n "$DEVELOPER_ID" ]]; then
    echo "→ Signing with: $DEVELOPER_ID"
    codesign --force --options runtime --sign "$DEVELOPER_ID" "$APP_BUNDLE"
else
    echo "→ Skipping code signing (pass --sign \"Developer ID Application: ...\" to sign)"
fi

echo "→ Building package with munkipkg..."
cd "$REPO_DIR"
munkipkg .

echo "✓ Done — package at build/$(ls build/*.pkg | xargs basename)"
