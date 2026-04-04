# macOS Drive Mapping

Automatic network drive mapping for macOS managed devices. On every login and network change, the script attempts to mount all configured SMB shares silently. Authentication is handled in order:

1. **Kerberos / Platform SSO** — silent, no credentials stored (AD-bound Macs)
2. **Keychain** — silent, credentials stored from a previous login
3. **Prompt** — one-time dialog, credentials saved to Keychain for all future logins

If a server is unreachable the mount is skipped and logged — no interaction, no errors shown to the user.

## Requirements

- macOS 12+
- [munkipkg](https://github.com/munki/munki-pkg) to build the package
- [Munki](https://github.com/munki/munki) for deployment
- Xcode Command Line Tools to compile the Swift helper (`xcode-select --install`)

## Configuration

Before building, edit `pkg/payload/Library/Scripts/DriveMapping/config.conf` with your SMB share URLs:

```bash
DRIVE_URLS=(
    "smb://fileserver.corp.example.com/shared"
    "smb://fileserver.corp.example.com/home"
)
```

`smb://server/sharename` → mounts at `/Volumes/sharename`

## Building the package

**Install munkipkg** (once):
```bash
brew install munki-pkg
```

**Build:**
1. Clone this repo
2. Edit `pkg/payload/Library/Scripts/DriveMapping/config.conf` (see above)
3. Compile the Swift mount helper (once, or after any source changes):
```bash
swiftc src/mount_helper.swift \
    -framework NetFS \
    -framework Security \
    -o pkg/payload/Library/Scripts/DriveMapping/mount_helper
```
4. Bump `version` in `pkg/build-info.plist` if this is an upgrade
5. Build the package:
```bash
munkipkg pkg/
```

The pkg is written to `pkg/build/` as `DriveMapping-<version>.pkg`.

**Import into Munki:**
```bash
munkiimport pkg/build/DriveMapping-1.0.pkg
```

## Project structure

```
├── pkg/                                          ← munkipkg project (builds the .pkg)
│   ├── build-info.plist                          ← version, identifier, munkipkg config
│   ├── icon.png                                  ← package icon
│   ├── payload/
│   │   └── Library/
│   │       ├── LaunchAgents/
│   │       │   └── com.drivemapping.plist        ← fires on login + network change
│   │       └── Scripts/DriveMapping/
│   │           ├── config.conf                   ← edit this (SMB URLs)
│   │           ├── map_drives.sh                 ← main script (do not edit)
│   │           ├── mount_helper                  ← compiled Swift binary (silent auth)
│   │           └── uninstall.sh                  ← removes all installed files
│   └── scripts/
│       ├── preinstall                            ← unloads existing agent on upgrade
│       └── postinstall                           ← loads agent after install
├── src/
│   └── mount_helper.swift                        ← Swift source for mount_helper binary
└── readme.md
```

> `pkg/build/` is gitignored — the built `.pkg` is not committed to the repo.

## How it works

The LaunchAgent fires on two events:

- **Login** — `RunAtLoad: true`
- **Network change** — `WatchPaths` on `/Library/Preferences/SystemConfiguration/`

`ThrottleInterval: 10` adds a 10-second delay after a network event to give the Kerberos SSO Extension time to acquire a ticket before the script runs.

`map_drives.sh` iterates over the configured URLs, pings each host, and calls `mount_helper` for reachable servers. `mount_helper` tries Kerberos first, then Keychain, then prompts once and saves the credentials — every subsequent mount is fully silent.

Logs are written to `~/Library/Logs/DriveMapping.log`.

## Versioning

Bump `version` in `pkg/build-info.plist` before each build. Munki uses this to determine whether to reinstall.

## Uninstalling

An `uninstall.sh` script is installed on the device at `/Library/Scripts/DriveMapping/uninstall.sh`.

**Manually** (run as root on the target device):
```bash
sudo bash /Library/Scripts/DriveMapping/uninstall.sh
```

**Via Munki** — add the following to the pkginfo so Munki runs the script automatically when the item is removed from a manifest:
```xml
<key>uninstall_method</key>
<string>uninstall_script</string>
<key>uninstall_script</key>
<string>#!/bin/bash
/Library/Scripts/DriveMapping/uninstall.sh
</string>
```

## Package signing

The package produced by `munkipkg` is **unsigned**. This is fine for Munki deployments — Munki installs packages via the `installer` command running as root, which bypasses Gatekeeper.

> **Note:** If your organisation uses endpoint security tooling (e.g. CrowdStrike, Jamf Protect) that explicitly blocks unsigned packages, installs will fail regardless of the Munki workflow.

If you need to sign the package, use a *Developer ID Installer* certificate (requires an Apple Developer account):

```bash
productsign --sign "Developer ID Installer: Your Name (TEAMID)" \
  pkg/build/DriveMapping-1.0.pkg pkg/build/DriveMapping-1.0-signed.pkg
```
