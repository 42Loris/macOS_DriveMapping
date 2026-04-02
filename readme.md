# macOS Drive Mapping

Automatic network drive mapping for macOS managed devices — equivalent to a Windows Scheduled Task triggered on login and network connection.

## File overview

| File | Purpose | Edit? |
|------|---------|-------|
| `config.json` | Network identifier + drive paths | **Yes** |
| `map_drives.sh` | Main mapping logic | No |
| `com.drivemapping.plist` | LaunchAgent template | No |
| `install.sh` | One-time setup per device | No |
| `uninstall.sh` | Removes the LaunchAgent | No |

## Quick start

1. Edit `config.json` with your SSID/domain and SMB paths.
2. Run `bash install.sh` once per device (or deploy via MDM).
3. Test manually: `bash map_drives.sh`
4. Check log: `tail -f ~/Library/Logs/DriveMapping.log`

## config.json reference

```json
{
  "network": {
    "ssid": "Corporate-WiFi",        // WiFi network name (optional)
    "domain_suffix": "corp.acme.com",// DNS search domain (optional)
    "ip_prefix": "10.0."             // IP address prefix (optional)
  },
  "drives": [
    {
      "url": "smb://server/share",   // SMB/AFP/NFS URL
      "mountpoint": "/Volumes/Name", // Where to mount
      "label": "Human-readable name" // Used in logs
    }
  ]
}
```

At least one `network` field must match for drives to be mounted. Using `domain_suffix` or `ip_prefix` is recommended for managed devices (works for both wired and wireless).

## How the triggers work

macOS uses `launchd` instead of Windows Scheduled Tasks:

| Windows trigger | macOS equivalent |
|----------------|-----------------|
| At log on | `RunAtLoad: true` in LaunchAgent |
| On network connection | `WatchPaths` on `/Library/Preferences/SystemConfiguration/` |

`ThrottleInterval: 10` adds a 10-second delay after a network event so the system has time to resolve DNS before the script runs.

## MDM deployment options

### Jamf Pro
- Deploy `map_drives.sh` and `config.json` to a fixed path (e.g. `/Library/Scripts/DriveMapping/`) via Policy > Files & Processes or a package.
- Deploy `com.drivemapping.plist` (pre-filled) to `/Library/LaunchAgents/` — Jamf loads it automatically.
- Use a Policy with trigger **Login** as a fallback/initial run.
- For per-user config, use Extension Attributes or Jamf Parameters (`$4`–`$11`) passed into the script.

### Kandji / Mosyle / Addigy
- Use the built-in **Custom Script** library to run `install.sh` at enrolment.
- Deploy files via a **Custom App** or **Managed Files** feature.

### Native MDM (Apple MDM protocol)
- Use a `com.apple.loginitems` Configuration Profile to run the script at login (macOS 13+).
- Combine with a `com.apple.MCX` profile for SMB mount points (limited, no SSID condition).

### NoMAD / Jamf Connect
- Best for identity-aware mapping (mount based on AD group membership).
- Supports Kerberos tickets for seamless SMB auth.
