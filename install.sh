#!/bin/bash
# install.sh — One-time setup: installs the LaunchAgent for the current user.
# Run once per device (or deploy via MDM as a script).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST_TEMPLATE="$SCRIPT_DIR/com.drivemapping.plist"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
PLIST_DEST="$LAUNCH_AGENTS/com.drivemapping.plist"
LOG_DIR="$HOME/Library/Logs"
LOG_FILE="$LOG_DIR/DriveMapping.log"
MAIN_SCRIPT="$SCRIPT_DIR/map_drives.sh"

echo "=== DriveMapping install ==="
echo "Script dir : $SCRIPT_DIR"
echo "LaunchAgent: $PLIST_DEST"
echo "Log        : $LOG_FILE"
echo ""

# Validate prerequisites
[[ -f "$PLIST_TEMPLATE" ]] || { echo "ERROR: com.drivemapping.plist not found"; exit 1; }
[[ -f "$MAIN_SCRIPT" ]]    || { echo "ERROR: map_drives.sh not found"; exit 1; }
[[ -f "$SCRIPT_DIR/config.json" ]] || { echo "ERROR: config.json not found"; exit 1; }

# Make scripts executable
chmod +x "$MAIN_SCRIPT"

# Create directories
mkdir -p "$LAUNCH_AGENTS" "$LOG_DIR"

# Unload existing agent (ignore errors if not loaded)
launchctl unload "$PLIST_DEST" 2>/dev/null || true

# Copy and fill in placeholders
sed \
    -e "s|SCRIPT_PATH_PLACEHOLDER|$MAIN_SCRIPT|g" \
    -e "s|LOG_PATH_PLACEHOLDER|$LOG_FILE|g" \
    "$PLIST_TEMPLATE" > "$PLIST_DEST"

# Validate the resulting plist
plutil -lint "$PLIST_DEST" || { echo "ERROR: Generated plist is invalid"; exit 1; }

# Load the agent
launchctl load "$PLIST_DEST"

echo ""
echo "Installed successfully."
echo "The agent will run at every login and on network changes."
echo "Log: $LOG_FILE"
echo ""
echo "Manual test: bash $MAIN_SCRIPT"
echo "Uninstall  : bash $SCRIPT_DIR/uninstall.sh"
