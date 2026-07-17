import SwiftUI

struct StatusMenuView: View {
    @EnvironmentObject var server: ServerManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            statusLine

            Divider()

            switch server.state {
            case .notDownloaded:
                Button("Download ClickHouse") {
                    Task { await server.ensureBinaryDownloaded() }
                }
            case .downloading(let progress):
                Text("Downloading… \(Int(progress * 100))%")
                    .foregroundStyle(.secondary)
            case .stopped, .failed:
                Button("Start Server") { server.start() }
            case .starting:
                Text("Starting…").foregroundStyle(.secondary)
            case .running:
                Button("Stop Server") { server.stop() }
            }

            Button("Open ClickHouse Window") { openWindow(id: "main") }

            Divider()

            Button("Reveal Data Directory") {
                NSWorkspace.shared.activateFileViewerSelecting([server.dataDirectoryURL])
            }
            Button("Reveal Log File") {
                NSWorkspace.shared.activateFileViewerSelecting([server.logPath])
            }

            Divider()

            Button("Quit ClickHouseApp") {
                server.stop()
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(8)
        .frame(minWidth: 220)
    }

    private var isRunning: Bool {
        if case .running = server.state { return true }
        return false
    }

    @ViewBuilder
    private var statusLine: some View {
        switch server.state {
        case .notDownloaded:
            Label("Not downloaded", systemImage: "arrow.down.circle")
        case .downloading:
            Label("Downloading", systemImage: "arrow.down.circle")
        case .stopped:
            Label("Stopped", systemImage: "circle")
        case .starting:
            Label("Starting", systemImage: "circle.dotted")
        case .running:
            Label("Running on port \(server.httpPort)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .lineLimit(3)
        }
    }
}
