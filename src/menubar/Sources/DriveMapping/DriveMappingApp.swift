import SwiftUI

@main
struct DriveMappingApp: App {
    var body: some Scene {
        MenuBarExtra("Drive Mapping", systemImage: "externaldrive.connected.to.line.below") {
            MenuBarView()
        }
        .menuBarExtraStyle(.menu)
    }
}
