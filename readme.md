# macOS Drive Mapping

Automatic network drive mapping for macOS managed devices. On every login and network change, the script attempts to mount all configured drives silently using the logged-in user's Kerberos credentials (PSSO). If a server is unreachable the mount is skipped and logged — no interaction, no prompts.

A menu bar app (`DriveMapping.app`) provides a status icon and manual controls.

## Requirements

- macOS 13+ with Platform SSO + Kerberos SSO Extension configured via MDM
- [munkipkg](https://github.com/munki/munki-pkg) to build the package
- [Munki](https://github.com/munki/munki) for deployment
- Xcode command-line tools (`xcode-select --install`) — required to compile the Swift menu bar app
- An **Apple Developer account** with a *Developer ID Application* certificate (app signing) and a *Developer ID Installer* certificate (package signing)

## Configuration

Before building, edit `pkg/payload/Library/Scripts/DriveMapping/map_drives.sh` and set your SMB share URLs:

```bash
DRIVE_URLS=(
    "smb://fileserver.corp.example.com/shared"
    "smb://fileserver.corp.example.com/home"
)
```

`smb://server/sharename` → mounts at `/Volumes/sharename`

## Project structure

```
├── build.sh                                      ← main build script
├── src/
│   └── menubar/                                  ← Swift source for the menu bar app
│       └── Resources/
│           ├── Info.plist
│           └── DriveMapping.icns                 ← app icon 
└── pkg/
    ├── build-info.plist                          ← munkipkg config + version
    ├── scripts/
    │   ├── preinstall                            ← unloads existing agents on upgrade
    │   └── postinstall                           ← loads agents after install
    └── payload/
        └── Library/
            ├── LaunchAgents/
            │   ├── com.drivemapping.plist        ← fires map_drives.sh on login + network change
            │   └── com.drivemapping.menubar.plist← keeps DriveMapping.app running at login
            └── Scripts/DriveMapping/
                ├── map_drives.sh                 ← main mount script
                └── uninstall.sh                  ← removes all installed files
```

## Building the package

### Prerequisites (once)

```bash
brew install munki-pkg
```

### Build

`build.sh` is interactive — run it and answer the prompts:

```
./build.sh

Rebuild app from Swift source? [y/N]
Sign the app? [y/N]
  → Developer ID Application (e.g. 'Developer ID Application: Name (TEAMID)'):
Sign the package? [y/N]
  → Developer ID Installer (e.g. 'Developer ID Installer: Name (TEAMID)'):
```

The script will:

1. Optionally compile the Swift source in `src/menubar/` and assemble `DriveMapping.app`
2. Optionally sign the app with your *Developer ID Application* certificate (hardened runtime)
3. Copy the app into the munkipkg payload and run `munkipkg`
4. Clean up all intermediate artifacts (`src/DriveMapping.app`, `pkg/payload/Applications/`)
5. Optionally sign the resulting package with your *Developer ID Installer* certificate via `productsign`

The final package lands in `pkg/build/`. If you signed it, the output is `DriveMapping-<version>-signed.pkg`.

> **Unsigned packages** are fine for Munki deployments — Munki installs via `installer` as root, which bypasses Gatekeeper. Sign the package only if your endpoint security tooling (e.g. CrowdStrike, Jamf Protect) explicitly blocks unsigned installers.

> **Note:** `src/DriveMapping.app` is intentionally excluded from git (`.gitignore`) so that a personally signed binary is never committed to the repo.

## How startup / auto-launch works

Two LaunchAgents are installed to `/Library/LaunchAgents/` and loaded into the user's login session by the package's `postinstall` script.

| Agent | Purpose | Trigger |
|---|---|---|
| `com.drivemapping` | Runs `map_drives.sh` to mount SMB shares | Login (`RunAtLoad`) + network change (`WatchPaths`) |
| `com.drivemapping.menubar` | Keeps `DriveMapping.app` running | Login (`RunAtLoad`), restarted automatically (`KeepAlive`) |

### Why LaunchAgents and not Login Items

LaunchAgents live in `/Library/LaunchAgents/` (system-wide, managed by MDM/Munki) rather than the per-user Login Items list. This means:

- They are installed once for all users on the machine.
- They survive user profile rebuilds and are re-applied on re-enrollment.
- They can be managed and removed centrally via Munki without user interaction.

### What happens at install time

The package's `postinstall` script immediately bootstraps both agents into the currently logged-in user's session via `launchctl bootstrap gui/<uid>`, so the drives are mapped and the menu bar app launches without requiring a logout/login cycle.

On **upgrade**, `preinstall` runs `launchctl bootout` first to unload the old agents cleanly before the new files are written.

### What happens at every subsequent login

`launchd` reads `/Library/LaunchAgents/com.drivemapping.plist` and `/Library/LaunchAgents/com.drivemapping.menubar.plist` and starts both agents automatically for every user who logs in.

`ThrottleInterval: 10` on `com.drivemapping` adds a 10-second delay after a network event to give the Kerberos SSO Extension time to acquire a ticket before mount is attempted.

## How authentication works

Authentication is fully transparent — `mount_smbfs` picks up the logged-in user's Kerberos ticket (issued by Platform SSO) automatically. No credentials are stored anywhere.

Logs are written to `~/Library/Logs/DriveMapping.log`.

## Importing into Munki

```bash
munkiimport pkg/build/DriveMapping-1.0-signed.pkg
```

## Versioning

Bump `version` in `pkg/build-info.plist` before each build. Munki uses this to determine whether to reinstall.

## Uninstalling

An `uninstall.sh` script is installed at `/Library/Scripts/DriveMapping/uninstall.sh`. It unloads both LaunchAgents and removes all installed files.

**Manually** (run as root on the target device):

```bash
sudo bash /Library/Scripts/DriveMapping/uninstall.sh
```

**Via Munki** — add the following to the pkginfo so Munki runs the script automatically on removal:

```xml
<key>uninstall_method</key>
<string>uninstall_script</string>
<key>uninstall_script</key>
<string>#!/bin/bash
/Library/Scripts/DriveMapping/uninstall.sh
</string>
```
