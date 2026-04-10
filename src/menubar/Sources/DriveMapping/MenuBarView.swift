import SwiftUI

struct MenuBarView: View {
    @State private var status: Status = .idle

    enum Status: Equatable {
        case idle
        case running
        case success(Date)
        case failed

        var label: String {
            switch self {
            case .idle:               return "Not run yet"
            case .running:            return "Mounting shares..."
            case .success(let date):  return "Last mounted: \(date.formatted(date: .omitted, time: .shortened))"
            case .failed:             return "Mount failed — check log"
            }
        }

        var color: Color {
            switch self {
            case .idle, .running: return .secondary
            case .success:        return .green
            case .failed:         return .red
            }
        }
    }

    var body: some View {
        Label(status.label, systemImage: statusIcon)
            .foregroundStyle(status.color)

        Divider()

        Button(status == .running ? "Mounting..." : "Mount Shares") {
            runScript()
        }
        .disabled(status == .running)

        Divider()

        Button("Open Log") {
            openLog()
        }

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }

    private var statusIcon: String {
        switch status {
        case .idle:    return "minus.circle"
        case .running: return "arrow.triangle.2.circlepath"
        case .success: return "checkmark.circle.fill"
        case .failed:  return "xmark.circle.fill"
        }
    }

    private func runScript() {
        status = .running

        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["/Library/Scripts/DriveMapping/map_drives.sh"]

            do {
                try process.run()
                process.waitUntilExit()
                let newStatus: Status = process.terminationStatus == 0
                    ? .success(Date())
                    : .failed
                await MainActor.run { status = newStatus }
            } catch {
                await MainActor.run { status = .failed }
            }
        }
    }

    private func openLog() {
        let log = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DriveMapping.log")
        NSWorkspace.shared.open(log)
    }
}
