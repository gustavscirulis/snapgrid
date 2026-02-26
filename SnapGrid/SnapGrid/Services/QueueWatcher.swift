import Foundation

@Observable
@MainActor
final class QueueWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let queueURL: URL
    var onNewFiles: (([URL]) -> Void)?

    private var knownFiles: Set<String> = []

    init(queueURL: URL) {
        self.queueURL = queueURL
    }

    func startWatching() {
        stopWatching()

        // Ensure queue directory exists
        try? FileManager.default.createDirectory(at: queueURL, withIntermediateDirectories: true)

        fileDescriptor = open(queueURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        // Snapshot current files
        knownFiles = Set(currentFileNames())

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: .global(qos: .utility)
        )

        source?.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.checkForNewFiles()
            }
        }

        source?.setCancelHandler { [weak self] in
            Task { @MainActor [weak self] in
                if let fd = self?.fileDescriptor, fd >= 0 {
                    close(fd)
                    self?.fileDescriptor = -1
                }
            }
        }

        source?.resume()
    }

    func stopWatching() {
        source?.cancel()
        source = nil
    }

    private func checkForNewFiles() {
        let currentNames = Set(currentFileNames())
        let newNames = currentNames.subtracting(knownFiles)
        knownFiles = currentNames

        guard !newNames.isEmpty else { return }

        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "mp4", "webm", "mov"]

        let newURLs = newNames
            .map { queueURL.appendingPathComponent($0) }
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) }

        if !newURLs.isEmpty {
            onNewFiles?(newURLs)
        }
    }

    private nonisolated func currentFileNames() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: queueURL.path)
            .filter { !$0.hasPrefix(".") }) ?? []
    }

    nonisolated deinit {
        // source cleanup handled by stopWatching() called before dealloc
    }
}
