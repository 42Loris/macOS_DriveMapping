# macOS Drive Mapping

Automatic network drive mapping for macOS managed devices. On every login and network change, the script attempts to mount all configured drives silently using the logged-in user's Kerberos credentials (PSSO). If a server is unreachable the mount is skipped and logged — no interaction, no prompts.

## Requirements

- macOS with Platform SSO + Kerberos SSO Extension configured via MDM
- [munkipkg](https://github.com/munki/munki-pkg) to build the package
- [Munki](https://github.com/munki/munki) for deployment

## Configuration

Before building, edit `payload/Library/Scripts/DriveMapping/config.conf` with your SMB share URLs.

One SMB URL per line:

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
2. Configure `payload/Library/Scripts/DriveMapping/config.conf` (see above)
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

## Uninstalling

An `uninstall.sh` script is installed on the device at `/Library/Scripts/DriveMapping/uninstall.sh`. It unloads the LaunchAgent and removes all installed files.

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
CURRENT_USER=$(stat -f "%Su" /dev/console)
USER_ID=$(id -u "$CURRENT_USER" 2>/dev/null) || true
if [[ -n "$CURRENT_USER" && "$CURRENT_USER" != "root" && -n "$USER_ID" ]]; then
    launchctl bootout "gui/$USER_ID" /Library/LaunchAgents/com.drivemapping.plist 2>/dev/null || true
fi
rm -f /Library/LaunchAgents/com.drivemapping.plist
rm -rf /Library/Scripts/DriveMapping/
</string>
```

## Package signing

The package produced by `munkipkg` is **unsigned**. This is fine for Munki deployments — Munki installs packages via the `installer` command running as root, which bypasses Gatekeeper. End users will not see any security warning during a managed install.

> **Warning:** If your organisation uses endpoint security tooling (e.g. CrowdStrike, Jamf Protect) with a policy that explicitly blocks unsigned packages, installs will fail regardless of the Munki workflow.

If you need to sign and notarize the package (e.g. for direct distribution or to satisfy a strict security policy):

1. **Sign** with a *Developer ID Installer* certificate (requires an Apple Developer account):
   ```bash
   productsign --sign "Developer ID Installer: Your Name (TEAMID)" \
     build/DriveMapping-1.0.pkg build/DriveMapping-1.0-signed.pkg
   ```

2. **Notarize:**
   ```bash
   xcrun notarytool submit build/DriveMapping-1.0-signed.pkg \
     --apple-id you@example.com --team-id TEAMID --wait
   ```

3. **Staple the notarization ticket:**
   ```bash
   xcrun stapler staple build/DriveMapping-1.0-signed.pkg
   ```

Use `DriveMapping-1.0-signed.pkg` for distribution after these steps.
