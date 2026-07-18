import SwiftUI

struct InstanceView: View {
    @EnvironmentObject var store: InstanceStore
    @ObservedObject var instance: InstanceManager

    @State private var showingDeleteConfirmation = false

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("State") { statusBadge }
                if let version = instance.version {
                    LabeledContent("Version", value: version)
                }
                if let uptime = instance.uptimeText {
                    LabeledContent("Uptime", value: uptime)
                }
            }

            Section("Connection") {
                LabeledContent("HTTP Port", value: "\(instance.httpPort)")
                LabeledContent("TCP Port", value: "\(instance.tcpPort)")
                LabeledContent("Host", value: "127.0.0.1")
            }

            Section("Files") {
                LabeledContent("Data Directory") {
                    pathRow(instance.dataDirectoryURL)
                }
                LabeledContent("Log File") {
                    pathRow(instance.logPath)
                }
                LabeledContent("Disk Usage") {
                    HStack {
                        Text(instance.diskUsageText ?? "—")
                        Button {
                            instance.refreshDiskUsage()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                controls
            }

            Section {
                Button("Delete Instance…", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 420)
        .confirmationDialog(
            "Delete “\(instance.name)”?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await store.delete(instance) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This stops the server and permanently deletes its data directory. This cannot be undone.")
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch instance.state {
        case .notDownloaded:
            Button("Download ClickHouse") {
                Task { await instance.ensureBinaryDownloaded() }
            }
        case .downloading(let progress):
            ProgressView(value: progress) {
                Text("Downloading…")
            }
        case .stopped, .failed:
            Button("Start Server") { instance.start() }
        case .starting:
            HStack {
                ProgressView().controlSize(.small)
                Text("Starting…")
            }
        case .running:
            Button("Stop Server", role: .destructive) { instance.stop() }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch instance.state {
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
