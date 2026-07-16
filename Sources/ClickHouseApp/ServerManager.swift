import Foundation
import Combine

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

    let httpPort = 8123
    let tcpPort = 9000

    private var process: Process?
    private var downloadObservation: NSKeyValueObservation?

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
            state = .stopped
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
        guard process == nil else { return }

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
                    if self.process != nil { self.state = .running }
                }
            }
        } catch {
            state = .failed("Failed to launch server: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard let p = process else { return }
        p.terminate()
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
