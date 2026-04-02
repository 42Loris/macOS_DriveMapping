# macOS Drive Mapping

Automatic network drive mapping for macOS managed devices. On every login and network change, the script attempts to mount all configured drives silently using the logged-in user's Kerberos credentials (PSSO). If a server is unreachable the mount is skipped and logged — no interaction, no prompts.

## Requirements

- macOS with Platform SSO + Kerberos SSO Extension configured via MDM
- [munkipkg](https://github.com/munki/munki-pkg) to build the package
- [Munki](https://github.com/munki/munki) for deployment

## Building the package

**Install munkipkg** (once):
```bash
brew install munki-pkg
```

**Build:**
1. Clone this repo
2. Edit `payload/Library/Scripts/DriveMapping/config.conf` with your SMB URLs
3. Bump `version` in `build-info.plist` if this is an upgrade
4. Run from the repo root:
```bash
munkipkg .
```

The pkg is written to the `build/` folder as `DriveMapping-1.0.pkg`.

**Import into Munki:**
```bash
munkiimport build/DriveMapping-1.0.pkg
```

## config.conf

One SMB URL per line. The share name is used automatically as the mountpoint and log label:

```bash
DRIVE_URLS=(
    "smb://fileserver.corp.example.com/shared"
    "smb://fileserver.corp.example.com/home"
)
```

`smb://server/sharename` → mounts at `/Volumes/sharename`

## Project structure

```
├── build-info.plist                          ← munkipkg config
├── payload/
│   └── Library/
│       ├── LaunchAgents/
│       │   └── com.drivemapping.plist        ← fires on login + network change
│       └── Scripts/
│           └── DriveMapping/
│               ├── map_drives.sh             ← main script (do not edit)
│               └── config.conf               ← edit this
└── scripts/
    ├── preinstall                            ← unloads existing agent on upgrade
    └── postinstall                           ← loads agent after install
```

## How it works

The LaunchAgent fires on two events:

- **Login** — `RunAtLoad: true`
- **Network change** — `WatchPaths` on `/Library/Preferences/SystemConfiguration/`

`ThrottleInterval: 10` adds a 10-second delay after a network event to give the Kerberos SSO Extension time to acquire a ticket before the script runs.

Authentication is fully transparent — `mount_smbfs` picks up the user's Kerberos ticket automatically. No credentials are stored anywhere.

Logs are written to `~/Library/Logs/DriveMapping.log`.

## Versioning

Bump `version` in `build-info.plist` before each build. Munki uses this to determine whether to reinstall.
