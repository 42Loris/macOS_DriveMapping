#!/bin/bash
# Uninstall DriveMapping — unloads LaunchAgents and removes all installed files.

CURRENT_USER=$(stat -f "%Su" /dev/console)
USER_ID=$(id -u "$CURRENT_USER" 2>/dev/null) || true

if [[ -n "$CURRENT_USER" && "$CURRENT_USER" != "root" && -n "$USER_ID" ]]; then
    launchctl bootout "gui/$USER_ID" /Library/LaunchAgents/com.drivemapping.plist 2>/dev/null || true
    launchctl bootout "gui/$USER_ID" /Library/LaunchAgents/com.drivemapping.menubar.plist 2>/dev/null || true
fi

rm -f  /Library/LaunchAgents/com.drivemapping.plist
rm -f  /Library/LaunchAgents/com.drivemapping.menubar.plist
rm -rf /Library/Scripts/DriveMapping/
rm -rf /Applications/DriveMapping.app

pkgutil --forget com.drivemapping 2>/dev/null || true
