import SwiftUI

struct StatusMenuView: View {
    @EnvironmentObject var store: InstanceStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if store.instances.isEmpty {
            Text("No instances yet")
        } else {
            ForEach(store.instances) { instance in
                InstanceMenu(instance: instance) {
                    store.selectedInstanceID = instance.id
                    openWindow(id: "main")
                }
            }
        }

        Divider()

        Button("Open InternationalClicks...") { openWindow(id: "main") }

        Button("Settings...") { openSettings() }
            .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit InternationalClicks") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

/// Each instance gets a native submenu: its status as the title/icon, and the
/// relevant action nested inside.
private struct InstanceMenu: View {
    @ObservedObject var instance: InstanceManager
    let onOpen: () -> Void

    var body: some View {
        Menu {
            switch instance.state {
            case .notDownloaded:
                Button("Download ClickHouse") {
                    Task { await instance.ensureBinaryDownloaded() }
                }
            case .downloading(let progress):
                Text("Downloading… \(Int(progress * 100))%")
            case .stopped, .failed:
                Button("Start Server") { instance.start() }
            case .starting:
                Text("Starting…")
            case .running:
                Button("Stop Server") { instance.stop() }
            }

            Button("Show in App", action: onOpen)
        } label: {
            Label(title, systemImage: statusIcon)
        }
    }

    private var title: String {
        instance.state == .running
            ? "\(instance.name): port \(String(instance.httpPort))" : instance.name
    }

    private var statusIcon: String {
        switch instance.state {
        case .notDownloaded, .downloading: return "arrow.down.circle"
        case .stopped: return "circle"
        case .starting: return "circle.dotted"
        case .running: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}
