import Foundation

/// Watches a log file for writes and reports newly appended text,
/// keeping only a bounded tail so the UI buffer doesn't grow forever.
@MainActor
final class LogTailer {
    private static let maxBufferBytes = 200_000

    private let path: String
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var offset: UInt64 = 0
    private let onUpdate: (String) -> Void
    private var buffer: String = ""

    init(url: URL, onUpdate: @escaping (String) -> Void) {
        self.path = url.path
        self.onUpdate = onUpdate
    }

    func start() {
        stop()

        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        readNewData()

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.readNewData() }
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
            }
        }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
        offset = 0
        buffer = ""
    }

    private func readNewData() {
        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        guard size >= offset else {
            // File was truncated/rotated; start over.
            offset = 0
            buffer = ""
            return readNewData()
        }
        guard size > offset else { return }

        try? handle.seek(toOffset: offset)
        guard let newData = try? handle.readToEnd() else { return }
        offset = size

        buffer += String(data: newData, encoding: .utf8) ?? ""
        if buffer.utf8.count > Self.maxBufferBytes {
            let excess = buffer.utf8.count - Self.maxBufferBytes
            buffer = String(buffer.dropFirst(excess))
        }
        onUpdate(buffer)
    }

    deinit {
        source?.cancel()
    }
}
