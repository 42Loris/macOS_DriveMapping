#!/bin/bash
# uninstall.sh — Removes the LaunchAgent and unmounts drives.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST_DEST="$HOME/Library/LaunchAgents/com.drivemapping.plist"

launchctl unload "$PLIST_DEST" 2>/dev/null && echo "Agent unloaded" || echo "Agent was not loaded"
rm -f "$PLIST_DEST" && echo "Plist removed"
echo "Uninstalled. Log remains at ~/Library/Logs/DriveMapping.log"
