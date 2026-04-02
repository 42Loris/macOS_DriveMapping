#!/bin/bash
# map_drives.sh — Main network drive mapping script
# Reads config from config.conf (same directory).
# Triggered by launchd on login and network changes.
# DO NOT EDIT — configure via config.conf.
# Requires: bash 3.2+ (built-in on macOS), no external dependencies.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.conf"
LOG="$HOME/Library/Logs/DriveMapping.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG"
}

die() {
    log "ERROR: $*"
    exit 1
}

[[ -f "$CONFIG" ]] || die "config.conf not found at $CONFIG"
# shellcheck source=config.conf
source "$CONFIG"

# ---------------------------------------------------------------------------
# Drive mounting
# ---------------------------------------------------------------------------
mount_drive() {
    local url="$1"
    local label mountpoint smb_url
    label="$(basename "$url")"
    mountpoint="/Volumes/$label"
    smb_url="${url#smb:}"

    if mount | grep -q "on $mountpoint "; then
        log "Already mounted: $label ($mountpoint)"
        return 0
    fi

    mkdir -p "$mountpoint"

    if mount_smbfs "$smb_url" "$mountpoint" 2>/dev/null; then
        log "Mounted: $label -> $url"
    else
        log "WARNING: Could not mount $label ($url) — server may be unreachable"
    fi
}

# ---------------------------------------------------------------------------
# Main logic
# ---------------------------------------------------------------------------
log "--- Drive mapping check ---"

for url in "${DRIVE_URLS[@]}"; do
    mount_drive "$url"
done

log "--- Done ---"
