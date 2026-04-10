#!/bin/bash
# map_drives.sh — Main network drive mapping script
# Reads config from config.conf (same directory).
# Triggered by launchd on login and network changes.
# DO NOT EDIT — configure via config.conf.
# Requires: bash 3.2+ (built-in on macOS), no external dependencies.

set -uo pipefail

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
# Kerberos ticket validation
# ---------------------------------------------------------------------------

# Returns 0 if a valid (non-expired) Kerberos TGT exists.
# If $1 is a non-empty realm string, also verifies the ticket belongs to that realm.
check_kerberos_ticket() {
    local realm="${1:-}"

    # klist -s exits 0 if a valid TGT is present in the credential cache, 1 otherwise.
    /usr/bin/klist -s 2>/dev/null || return 1

    # If a realm is configured, confirm the default principal is in that realm.
    if [[ -n "$realm" ]]; then
        /usr/bin/klist 2>/dev/null | grep -qi "principal:.*@${realm}" || return 1
    fi

    return 0
}

# Waits up to TICKET_WAIT_TIMEOUT seconds for a valid Kerberos ticket.
# Mirrors the 30-second wait in networkShareMounter's performSoftRestartWithKerberosAuth().
# Always returns 0 so callers can decide whether to proceed or skip.
wait_for_kerberos_ticket() {
    local realm="${KERBEROS_REALM:-}"
    local timeout="${TICKET_WAIT_TIMEOUT:-30}"
    local interval="${TICKET_RETRY_INTERVAL:-5}"
    local elapsed=0

    if check_kerberos_ticket "$realm"; then
        log "Kerberos ticket valid${realm:+ for realm $realm}"
        return 0
    fi

    if [[ "$timeout" -le 0 ]]; then
        log "WARNING: No Kerberos ticket found and TICKET_WAIT_TIMEOUT=0 — proceeding immediately"
        return 0
    fi

    log "Waiting for Kerberos ticket${realm:+ (realm: $realm)} — timeout: ${timeout}s"

    while [[ $elapsed -lt $timeout ]]; do
        sleep "$interval"
        elapsed=$((elapsed + interval))

        if check_kerberos_ticket "$realm"; then
            log "Kerberos ticket obtained after ${elapsed}s"
            return 0
        fi

        log "Still waiting for Kerberos ticket... (${elapsed}/${timeout}s elapsed)"
    done

    log "WARNING: No valid Kerberos ticket after ${timeout}s — attempting mounts anyway"
    return 0
}

# ---------------------------------------------------------------------------
# Drive mounting
# ---------------------------------------------------------------------------

mount_drive() {
    local url="$1"
    local label mountpoint host smb_path

    label="$(basename "$url")"
    mountpoint="/Volumes/$label"
    # Strip smb: prefix → //server/share (format required by mount_smbfs)
    smb_path="${url#smb:}"
    # host = everything between smb:// and the next /
    host="${url#smb://}"
    host="${host%%/*}"

    if /sbin/mount | awk -v m="$mountpoint" '$3 == m { found = 1 } END { exit !found }'; then
        log "Already mounted: $label ($mountpoint)"
        return 0
    fi

    if ! ping -c1 -t2 "$host" &>/dev/null; then
        log "SKIPPED: $label — server unreachable ($host), not on the correct network"
        return 0
    fi

    mkdir -p "$mountpoint"

    # mount_smbfs -N: headless SMB mount — uses the Kerberos TGT automatically,
    # never prompts for a password. Equivalent to passing nil credentials in NetFSMountURLSync().
    if /sbin/mount_smbfs -N "$smb_path" "$mountpoint" 2>/dev/null; then
        log "Mounted: $label -> $url"
    else
        # Remove the empty directory we created so /Volumes stays clean.
        rmdir "$mountpoint" 2>/dev/null || true
        log "WARNING: Could not mount $label ($url) — server reachable but mount failed"
    fi
}

# ---------------------------------------------------------------------------
# Main logic
# ---------------------------------------------------------------------------
log "--- Drive mapping check ---"

# Wait for the Kerberos ticket before attempting any mounts.
# On login, the Kerberos SSO Extension (Platform SSO) may need a few seconds
# to acquire a TGT — this avoids mount failures from racing ahead of it.
wait_for_kerberos_ticket

for url in "${DRIVE_URLS[@]}"; do
    mount_drive "$url" || true
done

log "--- Done ---"
