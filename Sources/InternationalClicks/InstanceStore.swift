import Foundation
import Combine

@MainActor
final class InstanceStore: ObservableObject {
    @Published private(set) var instances: [InstanceManager] = []
    @Published var selectedInstanceID: UUID?

    private let fm = FileManager.default
    private let binaryManager = BinaryManager.shared
    private var configCancellables: [UUID: AnyCancellable] = [:]

    private var appSupportDir: URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("InternationalClicks", isDirectory: true)
    }

    private var instancesRootDir: URL { appSupportDir.appendingPathComponent("instances", isDirectory: true) }
    private var configFile: URL { appSupportDir.appendingPathComponent("instances.json") }

    init() {
        try? fm.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        migrateLegacyLayoutIfNeeded()

        let configs = loadConfigs()
        instances = configs.map { config in
            InstanceManager(config: config, instanceDir: instancesRootDir.appendingPathComponent(config.id.uuidString, isDirectory: true))
        }
        instances.forEach(observeConfigChanges)
        selectedInstanceID = instances.first?.id
    }

    /// Persists whenever an instance's config changes (e.g. a port toggle),
    /// not just on create/delete.
    private func observeConfigChanges(for manager: InstanceManager) {
        configCancellables[manager.id] = manager.$config
            .dropFirst()
            .sink { [weak self] _ in self?.saveConfigs() }
    }

    private func loadConfigs() -> [InstanceConfig] {
        guard let data = try? Data(contentsOf: configFile),
              let configs = try? JSONDecoder().decode([InstanceConfig].self, from: data)
        else { return [] }
        return configs
    }

    private func saveConfigs() {
        let configs = instances.map(\.config)
        guard let data = try? JSONEncoder().encode(configs) else { return }
        try? data.write(to: configFile)
    }

    /// Before multi-instance support, the app kept a single binary at
    /// `bin/clickhouse` and a single data dir at `data/`. Adopt that layout
    /// as a "Default" instance the first time this runs, so existing users
    /// don't lose their server or its data.
    private func migrateLegacyLayoutIfNeeded() {
        guard !fm.fileExists(atPath: configFile.path) else { return }

        let legacyBin = appSupportDir.appendingPathComponent("bin/clickhouse")
        let legacyData = appSupportDir.appendingPathComponent("data", isDirectory: true)
        let legacyLog = appSupportDir.appendingPathComponent("server.log")
        guard fm.fileExists(atPath: legacyBin.path) else { return }

        let id = UUID()
        let instanceDir = instancesRootDir.appendingPathComponent(id.uuidString, isDirectory: true)

        do {
            try? binaryManager.adoptLegacyBinary(from: legacyBin)
            try fm.createDirectory(at: instanceDir, withIntermediateDirectories: true)
            if fm.fileExists(atPath: legacyData.path) {
                try fm.moveItem(at: legacyData, to: instanceDir.appendingPathComponent("data"))
            }
            if fm.fileExists(atPath: legacyLog.path) {
                try fm.moveItem(at: legacyLog, to: instanceDir.appendingPathComponent("server.log"))
            }
            try? fm.removeItem(at: appSupportDir.appendingPathComponent("bin", isDirectory: true))

            let config = InstanceConfig(id: id, name: "Default", version: "legacy", httpPort: 8123, tcpPort: 9000)
            let data = try JSONEncoder().encode([config])
            try data.write(to: configFile)
        } catch {
            // Best-effort migration; if it fails the user just starts fresh.
        }
    }

    private func nextAvailablePorts() -> (http: Int, tcp: Int) {
        let usedHTTP = instances.map(\.httpPort)
        let usedTCP = instances.map(\.tcpPort)
        let http = (usedHTTP.max() ?? 8122) + 1
        let tcp = (usedTCP.max() ?? 8999) + 1
        return (http, tcp)
    }

    @discardableResult
    func create(name: String, version: String) -> InstanceManager {
        let ports = nextAvailablePorts()
        let config = InstanceConfig(name: name, version: version, httpPort: ports.http, tcpPort: ports.tcp)
        let instanceDir = instancesRootDir.appendingPathComponent(config.id.uuidString, isDirectory: true)
        let manager = InstanceManager(config: config, instanceDir: instanceDir)
        instances.append(manager)
        observeConfigChanges(for: manager)
        saveConfigs()
        selectedInstanceID = manager.id
        Task { await manager.ensureBinaryDownloaded() }
        return manager
    }

    func delete(_ instance: InstanceManager) async {
        await instance.stopAndWait()

        let instanceDir = instancesRootDir.appendingPathComponent(instance.id.uuidString, isDirectory: true)
        try? fm.removeItem(at: instanceDir)

        instances.removeAll { $0.id == instance.id }
        configCancellables.removeValue(forKey: instance.id)
        saveConfigs()

        if selectedInstanceID == instance.id {
            selectedInstanceID = instances.first?.id
        }
    }
}
