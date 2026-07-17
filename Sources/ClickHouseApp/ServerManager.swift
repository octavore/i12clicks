import Foundation
import Combine
import Darwin

enum ServerState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case stopped
    case starting
    case running
    case failed(String)
}

@MainActor
final class ServerManager: ObservableObject {
    @Published private(set) var state: ServerState = .notDownloaded
    @Published private(set) var version: String?
    @Published private(set) var uptimeText: String?

    let httpPort = 8123
    let tcpPort = 9000

    private var process: Process?
    private var downloadObservation: NSKeyValueObservation?
    private var startedAt: Date?
    private var uptimeTimer: Timer?
    /// PID of a server we didn't spawn ourselves (e.g. left running by a
    /// previous app session that quit without calling stop()), discovered via
    /// the ClickHouse status lock file.
    private var externalPID: pid_t?

    private let fm = FileManager.default

    private var appSupportDir: URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClickHouseApp", isDirectory: true)
    }

    private var binDir: URL { appSupportDir.appendingPathComponent("bin", isDirectory: true) }
    private var binaryPath: URL { binDir.appendingPathComponent("clickhouse") }
    private var dataDir: URL { appSupportDir.appendingPathComponent("data", isDirectory: true) }
    var logPath: URL { appSupportDir.appendingPathComponent("server.log") }

    init() {
        if fm.fileExists(atPath: binaryPath.path) {
            fetchVersion()
            if let pid = aliveStatusFilePID() {
                externalPID = pid
                state = .running
                startedAt = statusFileStartDate() ?? Date()
                startUptimeTimer()
            } else {
                state = .stopped
            }
        }
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

    private var downloadURL: URL {
        #if arch(arm64)
        let path = "master/macos-aarch64/clickhouse"
        #else
        let path = "master/macos/clickhouse"
        #endif
        return URL(string: "https://builds.clickhouse.com/\(path)")!
    }

    func ensureBinaryDownloaded() async {
        if fm.fileExists(atPath: binaryPath.path) {
            state = .stopped
            return
        }

        do {
            try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: dataDir, withIntermediateDirectories: true)

            state = .downloading(progress: 0)

            let finalTempURL = try await downloadWithProgress(from: downloadURL) { [weak self] progress in
                Task { @MainActor in self?.state = .downloading(progress: progress) }
            }

            if fm.fileExists(atPath: binaryPath.path) {
                try fm.removeItem(at: binaryPath)
            }
            try fm.moveItem(at: finalTempURL, to: binaryPath)

            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryPath.path)
            try? removeQuarantine(at: binaryPath)

            state = .stopped
            fetchVersion()
        } catch {
            state = .failed("Download failed: \(error.localizedDescription)")
        }
    }

    private func downloadWithProgress(
        from url: URL,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {
        let delegate = DownloadProgressDelegate(onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        return try await withCheckedThrowingContinuation { continuation in
            delegate.onFinish = { result in continuation.resume(with: result) }
            session.downloadTask(with: url).resume()
        }
    }

    private func removeQuarantine(at url: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        p.arguments = ["-d", "com.apple.quarantine", url.path]
        try p.run()
        p.waitUntilExit()
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
            return
        }

        removeStaleStatusFileIfNeeded()

        state = .starting

        let p = Process()
        p.executableURL = binaryPath
        p.currentDirectoryURL = dataDir
        p.arguments = [
            "server",
            "--",
            "--path=\(dataDir.path)/",
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
            state = .stopped
        }
    }

    private func statusFilePID() -> pid_t? {
        let statusPath = dataDir.appendingPathComponent("status").path
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
        let statusPath = dataDir.appendingPathComponent("status").path
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
        let statusPath = dataDir.appendingPathComponent("status").path
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

    var dataDirectoryURL: URL { dataDir }
}

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    nonisolated(unsafe) let onProgress: (Double) -> Void
    nonisolated(unsafe) var onFinish: ((Result<URL, Error>) -> Void)?

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: tempURL)
            onFinish?(.success(tempURL))
        } catch {
            onFinish?(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            onFinish?(.failure(error))
        }
    }
}
