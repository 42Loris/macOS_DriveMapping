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
    local label mountpoint smb_url host
    label="$(basename "$url")"
    mountpoint="/Volumes/$label"
    smb_url="${url#smb:}"
    host="$(echo "$url" | sed 's|smb://||;s|/.*||')"

    if mount | grep -q "on $mountpoint "; then
        log "Already mounted: $label ($mountpoint)"
        return 0
    fi

    if ! ping -c1 -t2 "$host" &>/dev/null; then
        log "SKIPPED: $label — server unreachable ($host), not on the correct network"
        return 0
    fi

    if [[ -x "$SCRIPT_DIR/mount_helper" ]]; then
        if "$SCRIPT_DIR/mount_helper" "$url" &>/dev/null; then
            log "Mounted: $label -> $url"
        else
            log "WARNING: Could not mount $label ($url) — mount_helper failed"
        fi
    else
        if osascript -e "mount volume \"$url\"" &>/dev/null; then
            log "Mounted: $label -> $url"
        else
            log "WARNING: Could not mount $label ($url) — server reachable but mount failed"
        fi
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
