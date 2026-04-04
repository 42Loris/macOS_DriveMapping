// mount_helper.swift — Silent SMB mount using Keychain credentials
// Compile: swiftc mount_helper.swift -framework NetFS -framework Security -o mount_helper
// Usage:   mount_helper <smb://host/share>
//
// Flow:
//   1. Look up credentials in Keychain → mount silently via NetFS
//   2. Nothing in Keychain → prompt user once (osascript dialog), save to Keychain, mount
//   3. Mount fails despite credentials → exit 1 (map_drives.sh logs a warning)
//
// Exit code: 0 = success, 1 = failure

import Foundation
import NetFS
import Security

// NetFS C string constants are not auto-bridged to Swift — define raw values manually.
// Source: /System/Library/Frameworks/NetFS.framework/Headers/NetFS.h
private let kNetFSUseGuestAccessKey = "UseGuestAccess" as CFString

// MARK: - Keychain

/// Returns true if a Keychain entry for this host already exists (SSO marker or real credentials).
func hasKeychainEntry(for host: String) -> Bool {
    let query: [String: Any] = [
        kSecClass as String:      kSecClassInternetPassword,
        kSecAttrServer as String: host,
        kSecMatchLimit as String: kSecMatchLimitOne
    ]
    return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
}

func findCredentials(for host: String) -> (user: String, password: String)? {
    let query: [String: Any] = [
        kSecClass as String:            kSecClassInternetPassword,
        kSecAttrServer as String:       host,
        kSecReturnAttributes as String: true,
        kSecReturnData as String:       true,
        kSecMatchLimit as String:       kSecMatchLimitOne
    ]

    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
          let item     = result as? [String: Any],
          let pwdData  = item[kSecValueData as String] as? Data,
          let password = String(data: pwdData, encoding: .utf8),
          let user     = item[kSecAttrAccount as String] as? String
    else { return nil }

    return (user, password)
}

func saveCredentials(host: String, user: String, password: String) {
    // Remove any existing entry first to avoid duplicates
    let deleteQuery: [String: Any] = [
        kSecClass as String:      kSecClassInternetPassword,
        kSecAttrServer as String: host
    ]
    SecItemDelete(deleteQuery as CFDictionary)

    let attributes: [String: Any] = [
        kSecClass as String:           kSecClassInternetPassword,
        kSecAttrServer as String:      host,
        kSecAttrAccount as String:     user,
        kSecAttrProtocol as String:    kSecAttrProtocolSMB,
        kSecAttrLabel as String:       "DriveMapping: \(host)",
        kSecValueData as String:       password.data(using: .utf8)!
    ]

    let status = SecItemAdd(attributes as CFDictionary, nil)
    if status != errSecSuccess {
        fputs("WARNING: Could not save credentials to Keychain (status \(status))\n", stderr)
    }
}

// MARK: - First-time credential prompt (osascript)

/// Shows a two-step dialog (username, then password) and returns the entered values.
/// Returns nil if the user cancelled.
func promptCredentials(for host: String) -> (user: String, password: String)? {
    func runAppleScript(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = Pipe() // suppress osascript errors

        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil } // user cancelled
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let userScript = """
        text returned of (display dialog "Netzlaufwerk verbinden\n\nServer: \(host)\n\nBenutzername:" \
            default answer "" \
            with title "DriveMapping" \
            buttons {"Abbrechen", "Weiter"} \
            default button "Weiter")
    """

    guard let user = runAppleScript(userScript), !user.isEmpty else { return nil }

    let passwordScript = """
        text returned of (display dialog "Passwort für \(user)@\(host):" \
            default answer "" \
            with title "DriveMapping" \
            with hidden answer \
            buttons {"Abbrechen", "Verbinden"} \
            default button "Verbinden")
    """

    guard let password = runAppleScript(passwordScript), !password.isEmpty else { return nil }

    return (user, password)
}

// MARK: - NetFS mount

func netfsMount(shareURL: URL, mountDirURL: URL, user: String?, password: String?, useGuest: Bool = false) -> Int32 {
    let openOptions  = NSMutableDictionary()
    let mountOptions = NSMutableDictionary()
    var mountPoints: Unmanaged<CFArray>?

    if useGuest {
        openOptions[kNetFSUseGuestAccessKey] = true
    }

    let result = NetFSMountURLSync(
        shareURL    as CFURL,
        mountDirURL as CFURL,
        user     as CFString?,
        password as CFString?,
        openOptions,
        mountOptions,
        &mountPoints
    )

    mountPoints?.release()
    return result
}

// MARK: - Main mount logic

func mountSMB(_ urlString: String) -> Int32 {
    guard let shareURL = URL(string: urlString), let host = shareURL.host else {
        fputs("ERROR: Invalid URL: \(urlString)\n", stderr)
        return 1
    }

    let label     = shareURL.lastPathComponent
    let mountPath = "/Volumes/\(label)"

    try? FileManager.default.createDirectory(
        atPath: mountPath,
        withIntermediateDirectories: true,
        attributes: nil
    )

    let mountDirURL = URL(fileURLWithPath: mountPath, isDirectory: true)

    // --- 1. Try Kerberos / SSO (silent, works on AD-joined Macs) ---
    // Passing nil/nil without guest flag lets NetFS use the current Kerberos ticket.
    let kerberosResult = netfsMount(shareURL: shareURL, mountDirURL: mountDirURL,
                                    user: nil, password: nil, useGuest: false)
    if kerberosResult == 0 {
        print("Mounted (SSO): \(label) -> \(urlString) as \(NSUserName())")
        return 0
    }

    // --- 2. Try stored Keychain credentials ---
    if let creds = findCredentials(for: host) {
        let result = netfsMount(shareURL: shareURL, mountDirURL: mountDirURL,
                                user: creds.user, password: creds.password)
        if result == 0 {
            print("Mounted: \(label) -> \(urlString)")
            return 0
        }
        // Credentials wrong/expired → fall through to prompt
        fputs("INFO: Keychain credentials failed for \(host), prompting user...\n", stderr)
    }

    // --- 3. No credentials (or expired) → prompt once, save, mount ---
    guard let creds = promptCredentials(for: host) else {
        fputs("WARNING: User cancelled credential prompt for \(host)\n", stderr)
        return 1
    }

    saveCredentials(host: host, user: creds.user, password: creds.password)

    let result = netfsMount(shareURL: shareURL, mountDirURL: mountDirURL,
                            user: creds.user, password: creds.password)
    if result == 0 {
        print("Mounted: \(label) -> \(urlString)")
        return 0
    }

    fputs("WARNING: Mount failed for \(urlString) (NetFS error: \(result))\n", stderr)
    return 1
}

// MARK: - Entry point

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: mount_helper <smb://host/share>\n", stderr)
    exit(1)
}

exit(mountSMB(CommandLine.arguments[1]))
