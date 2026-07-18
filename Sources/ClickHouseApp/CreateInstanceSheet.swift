import SwiftUI

struct CreateInstanceSheet: View {
    @EnvironmentObject var store: InstanceStore
    @ObservedObject var binaryManager = BinaryManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name = "New Instance"
    @State private var selectedVersion: String?

    var body: some View {
        Form {
            TextField("Name", text: $name)

            Picker("Version", selection: $selectedVersion) {
                Text("Choose…").tag(String?.none)
                ForEach(binaryManager.availableReleases) { release in
                    Text(release.label).tag(String?.some(release.tag))
                }
            }

            if binaryManager.isLoadingReleases {
                ProgressView("Loading versions…")
            } else if let error = binaryManager.releasesError {
                Text(error).foregroundStyle(.red)
            }

            HStack {
                Button("Refresh Versions") {
                    Task { await binaryManager.refreshReleases() }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") {
                    store.create(name: name.isEmpty ? "New Instance" : name, version: selectedVersion!)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedVersion == nil)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 380, minHeight: 220)
        .task {
            if binaryManager.availableReleases.isEmpty {
                await binaryManager.refreshReleases()
            }
        }
    }
}
