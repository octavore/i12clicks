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

            Section {
                optionalPortToggle("MySQL Port", port: instance.mysqlPort, isOn: $instance.mysqlPortEnabled)
                optionalPortToggle("PostgreSQL Port", port: instance.postgresPort, isOn: $instance.postgresPortEnabled)
                optionalPortToggle("Interserver HTTP Port", port: instance.interserverHTTPPort, isOn: $instance.interserverPortEnabled)
            } header: {
                Text("Optional Ports")
            } footer: {
                if instance.hasPendingPortChanges {
                    Text("Changes take effect the next time the server starts.")
                }
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

    private func optionalPortToggle(_ title: String, port: Int, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack {
                Text(title)
                Spacer()
                Text(String(port))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func pathRow(_ url: URL) -> some View {
        HStack(spacing: 8) {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Text(url.path)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .buttonStyle(.link)
            .help("Reveal in Finder\n\(url.path)")

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .help("Copy path")

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
    }
}
