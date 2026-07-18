import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var store: InstanceStore
    @Environment(\.openSettings) private var openSettings
    @State private var showingCreateSheet = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(store.instances, selection: $store.selectedInstanceID) { instance in
                    InstanceRow(instance: instance).tag(instance.id)
                }

                Divider()

                Button {
                    showingCreateSheet = true
                } label: {
                    Label("Add Instance", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(8)
            }
            .navigationTitle("Instances")
            .toolbar {
                ToolbarItem {
                    Button {
                        openSettings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        } detail: {
            if let instance = store.instances.first(where: { $0.id == store.selectedInstanceID }) {
                InstanceDetailView(instance: instance)
            } else {
                ContentUnavailableView(
                    "No Instance Selected",
                    systemImage: "cylinder.split.1x2",
                    description: Text("Create a ClickHouse instance to get started.")
                )
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .sheet(isPresented: $showingCreateSheet) {
            CreateInstanceSheet()
                .environmentObject(store)
        }
    }
}

private struct InstanceRow: View {
    @ObservedObject var instance: InstanceManager

    var body: some View {
        HStack {
            statusDot
            VStack(alignment: .leading) {
                Text(instance.name)
                Text("v\(instance.majorMinorVersion) · Port \(String(instance.httpPort))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch instance.state {
        case .running: return .green
        case .starting, .downloading: return .yellow
        case .failed: return .red
        case .stopped, .notDownloaded: return .gray
        }
    }
}

private struct InstanceDetailView: View {
    @ObservedObject var instance: InstanceManager

    var body: some View {
        TabView {
            InstanceView(instance: instance)
                .tabItem { Label("Instance", systemImage: "server.rack") }

            QueryWindowView(instance: instance)
                .tabItem { Label("Query", systemImage: "terminal") }

            LogsView(instance: instance)
                .tabItem { Label("Logs", systemImage: "doc.text") }
        }
    }
}
