import Foundation

struct ClickHouseRelease: Identifiable, Equatable {
    var id: String { tag }
    /// Full release tag (e.g. "v25.8.28.1-lts") — this is what actually gets downloaded.
    let tag: String
    /// "major.minor" (e.g. "25.8") shown in the picker.
    let label: String
}

enum BinaryManagerError: LocalizedError {
    case fetchFailed(String)

    var errorDescription: String? {
        switch self {
        case .fetchFailed(let message): return message
        }
    }
}

@MainActor
final class BinaryManager: ObservableObject {
    static let shared = BinaryManager()

    @Published private(set) var availableReleases: [ClickHouseRelease] = []
    @Published private(set) var isLoadingReleases = false
    @Published private(set) var releasesError: String?

    private let fm = FileManager.default

    private var appSupportDir: URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClickHouseApp", isDirectory: true)
    }

    private var binariesDir: URL { appSupportDir.appendingPathComponent("binaries", isDirectory: true) }

    func binaryPath(for version: String) -> URL {
        binariesDir.appendingPathComponent(version, isDirectory: true).appendingPathComponent("clickhouse")
    }

    func isDownloaded(version: String) -> Bool {
        fm.fileExists(atPath: binaryPath(for: version).path)
    }

    struct InstalledVersion: Identifiable, Equatable {
        var id: String { version }
        let version: String
        let sizeBytes: Int64
    }

    func listInstalledVersions() -> [InstalledVersion] {
        guard let versionDirs = try? fm.contentsOfDirectory(
            at: binariesDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return versionDirs.compactMap { dir in
            let binary = dir.appendingPathComponent("clickhouse")
            guard fm.fileExists(atPath: binary.path) else { return nil }
            let attributes = try? fm.attributesOfItem(atPath: binary.path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            return InstalledVersion(version: dir.lastPathComponent, sizeBytes: size)
        }
        .sorted { $0.version > $1.version }
    }

    func deleteInstalledVersion(_ version: String) throws {
        let dir = binariesDir.appendingPathComponent(version, isDirectory: true)
        try fm.removeItem(at: dir)
    }

    func refreshReleases() async {
        isLoadingReleases = true
        releasesError = nil
        defer { isLoadingReleases = false }

        do {
            let url = URL(string: "https://api.github.com/repos/ClickHouse/ClickHouse/releases?per_page=40")!
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw BinaryManagerError.fetchFailed("GitHub API returned an error")
            }

            struct RawRelease: Decodable {
                let tag_name: String
                let draft: Bool
                let prerelease: Bool
            }

            let raw = try JSONDecoder().decode([RawRelease].self, from: data)
            let sortedTags = raw
                .filter { !$0.draft && !$0.prerelease }
                .map(\.tag_name)
                .sorted { Self.versionComponents(of: $0).lexicographicallyPrecedes(Self.versionComponents(of: $1)) == false }

            // Keep only the latest patch/build per major.minor line.
            var seenMajorMinor: Set<String> = []
            var releases: [ClickHouseRelease] = []
            for tag in sortedTags {
                let components = Self.versionComponents(of: tag)
                guard components.count >= 2 else { continue }
                let label = "\(components[0]).\(components[1])"
                guard seenMajorMinor.insert(label).inserted else { continue }
                releases.append(ClickHouseRelease(tag: tag, label: label))
            }
            availableReleases = releases
        } catch {
            releasesError = error.localizedDescription
        }
    }

    /// Extracts the numeric dot-separated components from a release tag
    /// (e.g. "v25.8.28.1-lts" -> [25, 8, 28, 1]) so releases can be sorted
    /// newest-first regardless of their publish date (LTS patches for older
    /// branches can be published after newer stable releases).
    private static func versionComponents(of tag: String) -> [Int] {
        let digitsAndDots = tag.drop { $0 == "v" }.prefix { $0.isNumber || $0 == "." }
        return digitsAndDots.split(separator: ".").compactMap { Int($0) }
    }

    private var assetName: String {
        #if arch(arm64)
        return "clickhouse-macos-aarch64"
        #else
        return "clickhouse-macos"
        #endif
    }

    private func downloadURL(for version: String) -> URL {
        URL(string: "https://github.com/ClickHouse/ClickHouse/releases/download/\(version)/\(assetName)")!
    }

    func ensureDownloaded(version: String, onProgress: @escaping (Double) -> Void) async throws {
        let binaryPath = binaryPath(for: version)
        if fm.fileExists(atPath: binaryPath.path) { return }

        let binDir = binaryPath.deletingLastPathComponent()
        try fm.createDirectory(at: binDir, withIntermediateDirectories: true)

        let finalTempURL = try await downloadWithProgress(from: downloadURL(for: version), onProgress: onProgress)

        if fm.fileExists(atPath: binaryPath.path) {
            try fm.removeItem(at: binaryPath)
        }
        try fm.moveItem(at: finalTempURL, to: binaryPath)

        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryPath.path)
        try? removeQuarantine(at: binaryPath)
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

    /// Moves a pre-existing legacy binary (from before multi-instance support)
    /// into the versioned binaries layout, so it doesn't need to be re-downloaded.
    func adoptLegacyBinary(from legacyPath: URL) throws {
        let target = binaryPath(for: "legacy")
        guard !fm.fileExists(atPath: target.path) else { return }
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: legacyPath, to: target)
    }
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
