import SwiftUI

struct StatusMenuView: View {
    @EnvironmentObject var store: InstanceStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if store.instances.isEmpty {
                Text("No instances yet").foregroundStyle(.secondary)
            } else {
                ForEach(store.instances) { instance in
                    InstanceMenuRow(instance: instance) {
                        store.selectedInstanceID = instance.id
                        openWindow(id: "main")
                    }
                }
            }

            Divider()

            Button("Open ClickHouse Window") { openWindow(id: "main") }
            Button("Settings…") { openSettings() }

            Divider()

            Button("Quit ClickHouseApp") {
                for instance in store.instances { instance.stop() }
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(8)
        .frame(minWidth: 240)
    }
}

private struct InstanceMenuRow: View {
    @ObservedObject var instance: InstanceManager
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: onOpen) {
                statusLine
            }
            .buttonStyle(.plain)

            switch instance.state {
            case .notDownloaded:
                Button("Download ClickHouse") {
                    Task { await instance.ensureBinaryDownloaded() }
                }
            case .downloading(let progress):
                Text("Downloading… \(Int(progress * 100))%")
                    .foregroundStyle(.secondary)
            case .stopped, .failed:
                Button("Start Server") { instance.start() }
            case .starting:
                Text("Starting…").foregroundStyle(.secondary)
            case .running:
                Button("Stop Server") { instance.stop() }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch instance.state {
        case .notDownloaded:
            Label(instance.name, systemImage: "arrow.down.circle")
        case .downloading:
            Label(instance.name, systemImage: "arrow.down.circle")
        case .stopped:
            Label(instance.name, systemImage: "circle")
        case .starting:
            Label(instance.name, systemImage: "circle.dotted")
        case .running:
            Label("\(instance.name) — port \(String(instance.httpPort))", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Label(instance.name, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}
