import SwiftUI

struct InstanceView: View {
    @EnvironmentObject var server: ServerManager

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("State") { statusBadge }
                if let version = server.version {
                    LabeledContent("Version", value: version)
                }
                if let uptime = server.uptimeText {
                    LabeledContent("Uptime", value: uptime)
                }
            }

            Section("Connection") {
                LabeledContent("HTTP Port", value: "\(server.httpPort)")
                LabeledContent("TCP Port", value: "\(server.tcpPort)")
                LabeledContent("Host", value: "127.0.0.1")
            }

            Section("Files") {
                LabeledContent("Data Directory") {
                    pathRow(server.dataDirectoryURL)
                }
                LabeledContent("Log File") {
                    pathRow(server.logPath)
                }
            }

            Section {
                controls
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 420)
    }

    @ViewBuilder
    private var controls: some View {
        switch server.state {
        case .notDownloaded:
            Button("Download ClickHouse") {
                Task { await server.ensureBinaryDownloaded() }
            }
        case .downloading(let progress):
            ProgressView(value: progress) {
                Text("Downloading…")
            }
        case .stopped, .failed:
            Button("Start Server") { server.start() }
        case .starting:
            HStack {
                ProgressView().controlSize(.small)
                Text("Starting…")
            }
        case .running:
            Button("Stop Server", role: .destructive) { server.stop() }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch server.state {
        case .notDownloaded:
            Label("Not downloaded", systemImage: "arrow.down.circle")
        case .downloading(let progress):
            Label("Downloading \(Int(progress * 100))%", systemImage: "arrow.down.circle")
        case .stopped:
            Label("Stopped", systemImage: "circle")
        case .starting:
            Label("Starting", systemImage: "circle.dotted")
        case .running:
            Label("Running", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .lineLimit(3)
        }
    }

    private func pathRow(_ url: URL) -> some View {
        HStack {
            Text(url.path)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
        }
    }
}
