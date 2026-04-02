# macOS Drive Mapping

Automatic network drive mapping for macOS managed devices — equivalent to a Windows Scheduled Task triggered on login and network connection.

On every login and network change, the script attempts to mount all configured drives. If a server is unreachable the mount is skipped and logged — no network detection or SSID matching needed.

## File overview

| File | Purpose | Edit? |
|------|---------|-------|
| `config.conf` | Drive paths | **Yes** |
| `map_drives.sh` | Main mapping logic | No |
| `com.drivemapping.plist` | LaunchAgent template | No |
| `install.sh` | One-time setup per device | No |
| `uninstall.sh` | Removes the LaunchAgent | No |

## Quick start

1. Edit `config.conf` with your SMB paths.
2. Run `bash install.sh` once per device (or deploy via MDM).
3. Test manually: `bash map_drives.sh`
4. Check log: `tail -f ~/Library/Logs/DriveMapping.log`

## config.conf reference

```bash
# Drives — parallel arrays (keep the same number of elements in each).
DRIVE_URLS=(
    "smb://server/share"
)

DRIVE_MOUNTPOINTS=(
    "/Volumes/Share"
)

DRIVE_LABELS=(
    "Human-readable name"   # Used in logs
)
```

## Dependencies

None — pure bash (3.2+, built-in on all macOS versions).

## How the triggers work

macOS uses `launchd` instead of Windows Scheduled Tasks:

| Windows trigger | macOS equivalent |
|----------------|-----------------|
| At log on | `RunAtLoad: true` in LaunchAgent |
| On network connection | `WatchPaths` on `/Library/Preferences/SystemConfiguration/` |

`ThrottleInterval: 10` adds a 10-second delay after a network event so the system has time to resolve DNS before the script runs.

## MDM deployment options

### Munki (recommended)
Build a flat pkg containing the files and a `postinstall` script that loads the LaunchAgent:

```
DriveMapping.pkg
├── payload/
│   └── Library/Scripts/DriveMapping/
│       ├── map_drives.sh
│       └── config.conf
└── postinstall     ← launchctl load the plist
```

Use `pkgbuild` to build:
```bash
pkgbuild \
  --root payload/ \
  --scripts scripts/ \
  --identifier com.drivemapping \
  --version 1.0 \
  DriveMapping.pkg
```

### Intune
Use a single self-contained shell script that writes all files to disk and loads the LaunchAgent. Intune can deploy one script per policy.

### Jamf Pro
- Deploy files to a fixed path (e.g. `/Library/Scripts/DriveMapping/`) via Policy > Files & Processes or a package.
- Deploy `com.drivemapping.plist` (pre-filled) to `/Library/LaunchAgents/`.

### NoMAD / Jamf Connect
Best for identity-aware mapping (mount based on AD group membership). Supports Kerberos tickets for seamless SMB auth.
