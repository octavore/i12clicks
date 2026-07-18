import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var store: InstanceStore
    @ObservedObject var binaryManager = BinaryManager.shared

    @State private var installedVersions: [BinaryManager.InstalledVersion] = []
    @State private var pendingDeleteVersion: String?
    @State private var showDeleteAllConfirmation = false
    @State private var isDeletingAll = false

    var body: some View {
        Form {
            Section("Installed ClickHouse Versions") {
                if installedVersions.isEmpty {
                    Text("No versions downloaded yet").foregroundStyle(.secondary)
                } else {
                    ForEach(installedVersions) { installed in
                        LabeledContent(installed.version) {
                            HStack {
                                Text(formattedSize(installed.sizeBytes))
                                    .foregroundStyle(.secondary)
                                Button(role: .destructive) {
                                    pendingDeleteVersion = installed.version
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                                .disabled(instancesUsing(installed.version).isEmpty == false)
                                .help(
                                    instancesUsing(installed.version).isEmpty
                                        ? "Delete this version"
                                        : "In use by: \(instancesUsing(installed.version).joined(separator: ", "))"
                                )
                            }
                        }
                    }
                }
            }

            Section("Reset App") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        "Stops all instances and permanently deletes every instance, its data, and all downloaded ClickHouse binaries."
                    )
                    .foregroundStyle(.secondary)
                    Button(role: .destructive) {
                        showDeleteAllConfirmation = true
                    } label: {
                        Text("Delete All Application Data…")
                    }
                    .disabled(isDeletingAll)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refresh() }
        .confirmationDialog(
            "Delete version \(pendingDeleteVersion ?? "")?",
            isPresented: Binding(
                get: { pendingDeleteVersion != nil },
                set: { if !$0 { pendingDeleteVersion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let version = pendingDeleteVersion {
                    try? binaryManager.deleteInstalledVersion(version)
                    refresh()
                }
                pendingDeleteVersion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteVersion = nil }
        } message: {
            Text(
                "This removes the downloaded binary. Instances using it will need to re-download before starting."
            )
        }
        .confirmationDialog(
            "Delete all application data?",
            isPresented: $showDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) {
                isDeletingAll = true
                Task {
                    await store.deleteAllApplicationData()
                    isDeletingAll = false
                    refresh()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This stops all instances and permanently deletes every instance, its data, and all downloaded ClickHouse binaries. This cannot be undone."
            )
        }
    }

    private func refresh() {
        installedVersions = binaryManager.listInstalledVersions()
    }

    private func instancesUsing(_ version: String) -> [String] {
        store.instances.filter { $0.config.version == version }.map(\.name)
    }

    private func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
