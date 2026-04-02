#!/bin/bash
# map_drives.sh — Main network drive mapping script
# Reads config from config.json (same directory).
# Triggered by launchd on login and network changes.
# DO NOT EDIT — configure via config.json.
# Requires: plutil (built-in on macOS 10.2+), no external dependencies.

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
# Parse config.json with plutil (built-in on macOS, no external dependencies)
# ---------------------------------------------------------------------------
read_config() {
    plutil -extract "$1" raw -o - "$CONFIG" 2>/dev/null || echo ""
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

if is_on_corporate_network; then
    log "Corporate network detected — mounting drives"
    i=0
    while plutil -extract "drives.$i.url" raw -o - "$CONFIG" &>/dev/null; do
        url=$(plutil -extract "drives.$i.url" raw -o - "$CONFIG")
        mountpoint=$(plutil -extract "drives.$i.mountpoint" raw -o - "$CONFIG")
        label=$(plutil -extract "drives.$i.label" raw -o - "$CONFIG")
        mount_drive "$url" "$mountpoint" "$label"
        i=$((i + 1))
    done
else
    log "Not on corporate network — skipping (or unmounting)"
    i=0
    while plutil -extract "drives.$i.url" raw -o - "$CONFIG" &>/dev/null; do
        mountpoint=$(plutil -extract "drives.$i.mountpoint" raw -o - "$CONFIG")
        label=$(plutil -extract "drives.$i.label" raw -o - "$CONFIG")
        unmount_drive "$mountpoint" "$label"
        i=$((i + 1))
    done
fi

log "--- Done ---"
