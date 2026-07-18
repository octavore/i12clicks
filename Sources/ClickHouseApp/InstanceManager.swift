import Foundation
import Combine
import Darwin

enum InstanceState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case stopped
    case starting
    case running
    case failed(String)
}

@MainActor
final class InstanceManager: ObservableObject, @MainActor Identifiable {
    @Published var config: InstanceConfig
    @Published private(set) var state: InstanceState = .notDownloaded
    @Published private(set) var version: String?
    @Published private(set) var uptimeText: String?
    @Published private(set) var diskUsageText: String?
    @Published private(set) var logTail: String = ""

    var id: UUID { config.id }
    var httpPort: Int { config.httpPort }
    var tcpPort: Int { config.tcpPort }
    var name: String { config.name }
    var majorMinorVersion: String { config.majorMinorVersion }

    private let binaryManager = BinaryManager.shared
    private var process: Process?
    private var startedAt: Date?
    private var uptimeTimer: Timer?
    /// PID of a server we didn't spawn ourselves (e.g. left running by a
    /// previous app session that quit without calling stop()), discovered via
    /// the ClickHouse status lock file.
    private var externalPID: pid_t?
    private var logTailer: LogTailer?

    private let fm = FileManager.default
    private let instanceDir: URL

    var dataDirectoryURL: URL { instanceDir.appendingPathComponent("data", isDirectory: true) }
    var logPath: URL { instanceDir.appendingPathComponent("server.log") }
    private var binaryPath: URL { binaryManager.binaryPath(for: config.version) }

    init(config: InstanceConfig, instanceDir: URL) {
        self.config = config
        self.instanceDir = instanceDir

        try? fm.createDirectory(at: dataDirectoryURL, withIntermediateDirectories: true)

        if fm.fileExists(atPath: binaryPath.path) {
            fetchVersion()
            if let pid = aliveStatusFilePID() {
                externalPID = pid
                state = .running
                startedAt = statusFileStartDate() ?? Date()
                startUptimeTimer()
                startLogTailing()
            } else {
                state = .stopped
            }
        }

        refreshDiskUsage()
    }

    private func fetchVersion() {
        let binary = binaryPath
        Task.detached {
            let p = Process()
            p.executableURL = binary
            p.arguments = ["server", "--version"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            guard (try? p.run()) != nil else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run { [weak self] in
                self?.version = output?.isEmpty == false ? output : nil
            }
        }
    }

    func ensureBinaryDownloaded() async {
        if fm.fileExists(atPath: binaryPath.path) {
            state = .stopped
            return
        }

        state = .downloading(progress: 0)
        do {
            try await binaryManager.ensureDownloaded(version: config.version) { [weak self] progress in
                Task { @MainActor in self?.state = .downloading(progress: progress) }
            }
            state = .stopped
            fetchVersion()
        } catch {
            state = .failed("Download failed: \(error.localizedDescription)")
        }
    }

    func start() {
        guard fm.fileExists(atPath: binaryPath.path) else {
            state = .failed("ClickHouse binary not downloaded yet")
            return
        }
        guard process == nil, externalPID == nil else { return }

        if let pid = aliveStatusFilePID() {
            externalPID = pid
            state = .running
            startedAt = statusFileStartDate() ?? Date()
            startUptimeTimer()
            startLogTailing()
            return
        }

        removeStaleStatusFileIfNeeded()

        state = .starting

        let p = Process()
        p.executableURL = binaryPath
        p.currentDirectoryURL = dataDirectoryURL
        p.arguments = [
            "server",
            "--",
            "--path=\(dataDirectoryURL.path)/",
            "--listen_host=127.0.0.1",
            "--http_port=\(httpPort)",
            "--tcp_port=\(tcpPort)",
        ]

        fm.createFile(atPath: logPath.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: logPath) {
            p.standardOutput = handle
            p.standardError = handle
        }

        p.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.process = nil
                self?.stopUptimeTimer()
                self?.stopLogTailing()
                if case .failed = self?.state ?? .stopped {
                    // preserve failure reason
                } else {
                    self?.state = .stopped
                }
            }
        }

        do {
            try p.run()
            process = p
            startLogTailing()
            Task {
                try? await Task.sleep(for: .seconds(1))
                await MainActor.run {
                    if self.process != nil {
                        self.state = .running
                        self.startedAt = Date()
                        self.startUptimeTimer()
                    }
                }
            }
        } catch {
            state = .failed("Failed to launch server: \(error.localizedDescription)")
        }
    }

    func stop() {
        if let p = process {
            p.terminate()
            return
        }
        if let pid = externalPID {
            kill(pid, SIGTERM)
            externalPID = nil
            stopUptimeTimer()
            stopLogTailing()
            state = .stopped
        }
    }

    /// Stops the instance and blocks (async) until the process is no longer running,
    /// used before deleting the instance's files. Times out after ~3s.
    func stopAndWait() async {
        guard process != nil || externalPID != nil else { return }
        stop()
        for _ in 0..<30 {
            if process == nil && externalPID == nil { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func statusFilePID() -> pid_t? {
        let statusPath = dataDirectoryURL.appendingPathComponent("status").path
        guard let contents = try? String(contentsOfFile: statusPath, encoding: .utf8),
              let pidLine = contents.split(separator: "\n").first(where: { $0.hasPrefix("PID:") }),
              let pid = pid_t(pidLine.dropFirst("PID:".count).trimmingCharacters(in: .whitespaces))
        else { return nil }
        return pid
    }

    private func aliveStatusFilePID() -> pid_t? {
        guard let pid = statusFilePID(), kill(pid, 0) == 0 else { return nil }
        return pid
    }

    private func statusFileStartDate() -> Date? {
        let statusPath = dataDirectoryURL.appendingPathComponent("status").path
        guard let contents = try? String(contentsOfFile: statusPath, encoding: .utf8),
              let line = contents.split(separator: "\n").first(where: { $0.hasPrefix("Started at:") })
        else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: line.dropFirst("Started at:".count).trimmingCharacters(in: .whitespaces))
    }

    /// ClickHouse writes `data/status` with the PID of the running server and
    /// refuses to start if the file exists. If the app was force-quit or crashed,
    /// the file survives even though no server is actually running, so we clear
    /// it here when the recorded PID is no longer alive.
    private func removeStaleStatusFileIfNeeded() {
        let statusPath = dataDirectoryURL.appendingPathComponent("status").path
        guard fm.fileExists(atPath: statusPath), aliveStatusFilePID() == nil else { return }
        try? fm.removeItem(atPath: statusPath)
    }

    private func startUptimeTimer() {
        uptimeTimer?.invalidate()
        updateUptimeText()
        uptimeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateUptimeText() }
        }
    }

    private func stopUptimeTimer() {
        uptimeTimer?.invalidate()
        uptimeTimer = nil
        startedAt = nil
        uptimeText = nil
    }

    private func updateUptimeText() {
        guard let startedAt else { return }
        let seconds = Int(Date().timeIntervalSince(startedAt))
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        uptimeText = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private func startLogTailing() {
        guard logTailer == nil else { return }
        let tailer = LogTailer(url: logPath) { [weak self] text in
            self?.logTail = text
        }
        tailer.start()
        logTailer = tailer
    }

    private func stopLogTailing() {
        logTailer?.stop()
        logTailer = nil
    }

    func refreshDiskUsage() {
        let dir = dataDirectoryURL
        Task.detached {
            let fm = FileManager.default
            var total: Int64 = 0
            if let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                while let url = enumerator.nextObject() as? URL {
                    if let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                       values.isRegularFile == true {
                        total += Int64(values.fileSize ?? 0)
                    }
                }
            }
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let text = formatter.string(fromByteCount: total)
            await MainActor.run { [weak self] in
                self?.diskUsageText = text
            }
        }
    }
}
