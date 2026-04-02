#!/bin/bash
# map_drives.sh — Main network drive mapping script
# Reads config from config.json (same directory).
# Triggered by launchd on login and network changes.
# DO NOT EDIT — configure via config.json.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.json"
LOG="$HOME/Library/Logs/DriveMapping.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG"
}

die() {
    log "ERROR: $*"
    exit 1
}

[[ -f "$CONFIG" ]] || die "config.json not found at $CONFIG"

# ---------------------------------------------------------------------------
# Parse config.json with python3 (built-in on macOS)
# ---------------------------------------------------------------------------
read_config() {
    python3 -c "
import json, sys
with open('$CONFIG') as f:
    c = json.load(f)
key = sys.argv[1]
parts = key.split('.')
val = c
for p in parts:
    val = val.get(p, '')
print(val if not isinstance(val, list) else json.dumps(val))
" "$1"
}

# ---------------------------------------------------------------------------
# Network detection
# ---------------------------------------------------------------------------
get_current_ssid() {
    networksetup -getairportnetwork en0 2>/dev/null | awk -F': ' '{print $2}'
}

get_current_ip() {
    ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true
}

get_search_domain() {
    scutil --dns 2>/dev/null | awk '/search domain/ {print $NF}' | head -1
}

is_on_corporate_network() {
    local cfg_ssid cfg_domain cfg_ip_prefix
    cfg_ssid="$(read_config network.ssid)"
    cfg_domain="$(read_config network.domain_suffix)"
    cfg_ip_prefix="$(read_config network.ip_prefix)"

    # Match any configured identifier (at least one must match)
    local matched=0

    if [[ -n "$cfg_ssid" ]]; then
        local current_ssid
        current_ssid="$(get_current_ssid)"
        [[ "$current_ssid" == "$cfg_ssid" ]] && matched=1
    fi

    if [[ -n "$cfg_domain" && $matched -eq 0 ]]; then
        local current_domain
        current_domain="$(get_search_domain)"
        [[ "$current_domain" == *"$cfg_domain"* ]] && matched=1
    fi

    if [[ -n "$cfg_ip_prefix" && $matched -eq 0 ]]; then
        local current_ip
        current_ip="$(get_current_ip)"
        [[ "$current_ip" == "$cfg_ip_prefix"* ]] && matched=1
    fi

    return $((1 - matched))
}

# ---------------------------------------------------------------------------
# Drive mounting
# ---------------------------------------------------------------------------
mount_drive() {
    local url="$1" mountpoint="$2" label="$3"

    if mount | grep -q "on $mountpoint "; then
        log "Already mounted: $label ($mountpoint)"
        return 0
    fi

    mkdir -p "$mountpoint"

    if open "$url" 2>/dev/null; then
        log "Mounted: $label -> $url"
    else
        log "WARNING: Could not mount $label ($url) — server may be unreachable"
    fi
}

unmount_drive() {
    local mountpoint="$1" label="$2"

    if mount | grep -q "on $mountpoint "; then
        diskutil unmount "$mountpoint" 2>/dev/null && log "Unmounted: $label" || true
    fi
}

# ---------------------------------------------------------------------------
# Main logic
# ---------------------------------------------------------------------------
log "--- Drive mapping check ---"

DRIVES="$(read_config drives)"
DRIVE_COUNT=$(python3 -c "import json; d=json.loads('$DRIVES'); print(len(d))")

if is_on_corporate_network; then
    log "Corporate network detected — mounting drives"
    for i in $(seq 0 $((DRIVE_COUNT - 1))); do
        url=$(python3      -c "import json; d=json.loads('$DRIVES'); print(d[$i]['url'])")
        mountpoint=$(python3 -c "import json; d=json.loads('$DRIVES'); print(d[$i]['mountpoint'])")
        label=$(python3    -c "import json; d=json.loads('$DRIVES'); print(d[$i]['label'])")
        mount_drive "$url" "$mountpoint" "$label"
    done
else
    log "Not on corporate network — skipping (or unmounting)"
    for i in $(seq 0 $((DRIVE_COUNT - 1))); do
        mountpoint=$(python3 -c "import json; d=json.loads('$DRIVES'); print(d[$i]['mountpoint'])")
        label=$(python3      -c "import json; d=json.loads('$DRIVES'); print(d[$i]['label'])")
        unmount_drive "$mountpoint" "$label"
    done
fi

log "--- Done ---"
