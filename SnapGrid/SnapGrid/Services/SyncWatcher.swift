import Foundation
import SwiftData
import AppKit

/// Watches the metadata/ directory for JSON sidecars arriving via iCloud from other devices.
/// When new or updated sidecars are detected, imports them into SwiftData.
@MainActor
final class SyncWatcher {
    private var metadataSource: DispatchSourceFileSystemObject?
    private var spacesSource: DispatchSourceFileSystemObject?
    private var metadataFD: Int32 = -1
    private var spacesFD: Int32 = -1
    private var debounceTask: Task<Void, Never>?
    private var spacesDebounceTask: Task<Void, Never>?
    private var knownSidecarIds: Set<String> = []
    private var context: ModelContext?
    /// When true, ignore file-system events (we caused them ourselves).
    private var suppressingLocalChanges = false

    private let storage = MediaStorageService.shared
    private let sidecarService = MetadataSidecarService.shared

    // MARK: - Public API

    /// Call BEFORE local mutations that write sidecar/spaces files.
    func beginLocalChange() {
        suppressingLocalChanges = true
    }

    /// Call AFTER local mutations complete. Updates known state so the watcher
    /// won't react to our own file changes when suppression ends.
    func endLocalChange() {
        knownSidecarIds = Set(currentSidecarIds())
        // Keep suppressed briefly to outlast any DispatchSource events
        // that are already queued from our write.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.suppressingLocalChanges = false
        }
    }

    func startWatching(context: ModelContext) {
        stopWatching()
        self.context = context

        knownSidecarIds = Set(currentSidecarIds())

        // Watch metadata/ directory — use main queue so event handler is
        // already on the main thread, avoiding cross-isolation captures.
        metadataFD = open(storage.metadataDir.path, O_EVTONLY)
        if metadataFD >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: metadataFD,
                eventMask: .write,
                queue: .main
            )
            source.setEventHandler { [weak self] in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    self?.scheduleSync()
                }
            }
            let fd = metadataFD
            source.setCancelHandler { close(fd) }
            source.resume()
            metadataSource = source
        }

        // Watch base directory for spaces.json changes
        spacesFD = open(storage.baseURL.path, O_EVTONLY)
        if spacesFD >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: spacesFD,
                eventMask: .write,
                queue: .main
            )
            source.setEventHandler { [weak self] in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    self?.scheduleSyncSpaces()
                }
            }
            let fd = spacesFD
            source.setCancelHandler { close(fd) }
            source.resume()
            spacesSource = source
        }
    }

    func stopWatching() {
        metadataSource?.cancel()
        metadataSource = nil
        spacesSource?.cancel()
        spacesSource = nil
        debounceTask?.cancel()
        spacesDebounceTask?.cancel()
        context = nil
    }

    /// Perform an initial sync on launch — picks up items that arrived via iCloud while the app was closed.
    func initialSync(context: ModelContext) async {
        self.context = context
        await syncMetadataAsync()
        syncSpaces()
    }

    // MARK: - Debouncing

    private func scheduleSync() {
        guard !suppressingLocalChanges else { return }
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, !self.suppressingLocalChanges else { return }
            self.syncMetadata()
        }
    }

    private func scheduleSyncSpaces() {
        guard !suppressingLocalChanges else { return }
        spacesDebounceTask?.cancel()
        spacesDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, !self.suppressingLocalChanges else { return }
            self.syncSpaces()
        }
    }

    // MARK: - Metadata Sync

    /// Async version for initial sync — yields periodically to keep UI responsive.
    private func syncMetadataAsync() async {
        guard let context else { return }

        let currentIds = Set(currentSidecarIds())
        let newIds = currentIds.subtracting(knownSidecarIds)

        knownSidecarIds = currentIds

        if newIds.isEmpty { return }

        print("[SyncWatcher] Initial sync: importing \(newIds.count) items from iCloud...")
        var count = 0
        for id in newIds {
            importSidecar(id: id)
            count += 1
            if count % 10 == 0 {
                try? context.save()
                await Task.yield()
            }
        }
        try? context.save()
        print("[SyncWatcher] Initial sync complete: imported \(count) items")
    }

    private func syncMetadata() {
        guard let context else { return }

        let currentIds = Set(currentSidecarIds())
        let newIds = currentIds.subtracting(knownSidecarIds)
        let deletedIds = knownSidecarIds.subtracting(currentIds)

        knownSidecarIds = currentIds

        for id in newIds {
            importSidecar(id: id)
        }

        for id in deletedIds {
            removeItem(id: id)
        }

        if !newIds.isEmpty || !deletedIds.isEmpty {
            try? context.save()
        }
    }

    private func importSidecar(id: String) {
        guard let context else { return }

        let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == id })
        if let existing = try? context.fetch(descriptor), !existing.isEmpty { return }

        guard let sidecar = sidecarService.readSidecar(id: id) else { return }

        let mediaType: MediaType = sidecar.type == "video" ? .video : .image
        let ext = mediaType == .video ? "mp4" : "png"
        let filename = "\(id).\(ext)"

        let mediaURL = storage.mediaDir.appendingPathComponent(filename)
        let fm = FileManager.default
        if !fm.fileExists(atPath: mediaURL.path) {
            let placeholderName = ".\(filename).icloud"
            let placeholderURL = storage.mediaDir.appendingPathComponent(placeholderName)
            if fm.fileExists(atPath: placeholderURL.path) {
                try? fm.startDownloadingUbiquitousItem(at: mediaURL)
            } else {
                let altExt = mediaType == .video ? "mov" : "jpg"
                let altFilename = "\(id).\(altExt)"
                if !fm.fileExists(atPath: storage.mediaDir.appendingPathComponent(altFilename).path) {
                    print("[SyncWatcher] Media file not found for \(id), skipping")
                    return
                }
            }
        }

        let item = MediaItem(
            id: id,
            mediaType: mediaType,
            filename: filename,
            width: sidecar.width,
            height: sidecar.height,
            createdAt: sidecar.createdAt,
            duration: sidecar.duration
        )

        if let spaceId = sidecar.spaceId {
            let spaceDescriptor = FetchDescriptor<Space>(predicate: #Predicate { $0.id == spaceId })
            item.space = try? context.fetch(spaceDescriptor).first
        }

        if let imageContext = sidecar.imageContext, !imageContext.isEmpty {
            let patterns = (sidecar.patterns ?? []).map { PatternTag(name: $0.name, confidence: $0.confidence) }
            item.analysisResult = AnalysisResult(
                imageContext: imageContext,
                imageSummary: sidecar.imageSummary ?? "",
                patterns: patterns,
                provider: "synced",
                model: "icloud-sync"
            )
        }

        context.insert(item)

        if !storage.thumbnailExists(id: id) {
            Task.detached { [storage] in
                if mediaType == .video {
                    if let posterFrame = try? await VideoFrameExtractor.extractPosterFrame(from: storage.mediaURL(filename: filename)) {
                        _ = try? ThumbnailService.generateThumbnail(from: posterFrame, id: id)
                    }
                } else {
                    _ = try? await ThumbnailService.generateThumbnail(from: storage.mediaURL(filename: filename), id: id)
                }
            }
        }

        print("[SyncWatcher] Imported \(id) from iCloud")
    }

    private func removeItem(id: String) {
        guard let context else { return }

        let trashURL = storage.trashMetadataDir.appendingPathComponent("\(id).json")
        if FileManager.default.fileExists(atPath: trashURL.path) { return }

        let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == id })
        guard let item = (try? context.fetch(descriptor))?.first else { return }
        context.delete(item)
        print("[SyncWatcher] Removed \(id) (sidecar deleted on other device)")
    }

    // MARK: - Spaces Sync

    private func syncSpaces() {
        guard let context else { return }

        let sidecarSpaces = sidecarService.readSpaces()
        guard !sidecarSpaces.isEmpty else { return }

        let descriptor = FetchDescriptor<Space>()
        let existingSpaces = (try? context.fetch(descriptor)) ?? []
        let existingById = Dictionary(uniqueKeysWithValues: existingSpaces.map { ($0.id, $0) })
        let sidecarById = Dictionary(uniqueKeysWithValues: sidecarSpaces.map { ($0.id, $0) })

        for sidecar in sidecarSpaces {
            if existingById[sidecar.id] == nil {
                let space = Space(
                    id: sidecar.id,
                    name: sidecar.name,
                    order: sidecar.order,
                    createdAt: sidecar.createdAt
                )
                space.customPrompt = sidecar.customPrompt
                space.useCustomPrompt = sidecar.useCustomPrompt
                context.insert(space)
            }
        }

        for space in existingSpaces {
            if let sidecar = sidecarById[space.id] {
                if space.name != sidecar.name { space.name = sidecar.name }
                if space.order != sidecar.order { space.order = sidecar.order }
            }
        }

        try? context.save()
    }

    // MARK: - Helpers

    private nonisolated func currentSidecarIds() -> [String] {
        let metadataDir = MediaStorageService.shared.metadataDir
        let files = (try? FileManager.default.contentsOfDirectory(at: metadataDir, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
    }
}
