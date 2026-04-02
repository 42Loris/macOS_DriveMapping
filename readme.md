# macOS Drive Mapping

Automatic network drive mapping for macOS managed devices. On every login and network change, the script attempts to mount all configured drives. If a server is unreachable the mount is skipped and logged — no network detection or SSID matching needed.

Authentication is handled transparently via PSSO and the Kerberos SSO Extension — no credentials are stored in the config.

## File overview

| File | Purpose | Edit? |
|------|---------|-------|
| `config.conf` | Drive URLs | **Yes** |
| `map_drives.sh` | Main mapping logic | No |
| `com.drivemapping.plist` | LaunchAgent template | No |
| `install.sh` | One-time setup per device | No |
| `uninstall.sh` | Removes the LaunchAgent | No |

## Quick start

1. Edit `config.conf` with your SMB URLs.
2. Run `bash install.sh` once per device (or deploy via MDM).
3. Test manually: `bash map_drives.sh`
4. Check log: `tail -f ~/Library/Logs/DriveMapping.log`

## config.conf reference

One SMB URL per line. The share name is automatically used as the mountpoint and log label:

```bash
DRIVE_URLS=(
    "smb://fileserver.corp.example.com/shared"
    "smb://fileserver.corp.example.com/home"
)
```

`smb://server/sharename` → mounts at `/Volumes/sharename`

## How the triggers work

The LaunchAgent fires on two events:

- **Login** — `RunAtLoad: true`
- **Network change** — `WatchPaths` on `/Library/Preferences/SystemConfiguration/`

`ThrottleInterval: 10` adds a 10-second delay after a network event so the system has time to complete the Kerberos ticket acquisition before the script runs.

## Dependencies

None — pure bash (3.2+, built-in on all macOS versions).

## MDM deployment

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

Build with `pkgbuild`:
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
