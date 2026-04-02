#!/bin/bash
# Uninstall DriveMapping — unloads the LaunchAgent and removes all installed files.

CURRENT_USER=$(stat -f "%Su" /dev/console)
USER_ID=$(id -u "$CURRENT_USER" 2>/dev/null) || true

if [[ -n "$CURRENT_USER" && "$CURRENT_USER" != "root" && -n "$USER_ID" ]]; then
    launchctl bootout "gui/$USER_ID" /Library/LaunchAgents/com.drivemapping.plist 2>/dev/null || true
fi

rm -f /Library/LaunchAgents/com.drivemapping.plist
rm -rf /Library/Scripts/DriveMapping/
