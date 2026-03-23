import Foundation
import SwiftData
import AppKit

/// Watches the metadata/ directory for JSON sidecars arriving via iCloud from other devices.
/// When new or updated sidecars are detected, imports them into SwiftData.
///
/// File I/O (JSON reads, file-existence checks, iCloud download triggers) runs on background
/// threads via `Task.detached`. SwiftData mutations stay on `@MainActor`.
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

    // MARK: - Background I/O Types

    /// Sendable bridge carrying file-derived data from background thread to main actor.
    private struct SidecarImportData: Sendable {
        let id: String
        let sidecar: SidecarMetadata
        let mediaType: MediaType
        let filename: String
        let mediaFileFound: Bool
        let needsThumbnail: Bool
    }

    // MARK: - Public API

    /// Call BEFORE local mutations that write sidecar/spaces files.
    func beginLocalChange() {
        suppressingLocalChanges = true
    }

    /// Call AFTER local mutations complete. Updates known state so the watcher
    /// won't react to our own file changes when suppression ends.
    func endLocalChange() {
        knownSidecarIds = Set(Self.currentSidecarIdsFromDisk())
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

        knownSidecarIds = Set(Self.currentSidecarIdsFromDisk())

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
        await syncSpaces()
    }

    // MARK: - Debouncing

    private func scheduleSync() {
        guard !suppressingLocalChanges else { return }
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, !self.suppressingLocalChanges else { return }
            await self.syncMetadata()
        }
    }

    private func scheduleSyncSpaces() {
        guard !suppressingLocalChanges else { return }
        spacesDebounceTask?.cancel()
        spacesDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, !self.suppressingLocalChanges else { return }
            await self.syncSpaces()
        }
    }

    // MARK: - Metadata Sync

    /// Async version for initial sync — gathers file data on background thread,
    /// then applies to SwiftData on main actor in batches.
    private func syncMetadataAsync() async {
        guard context != nil else { return }

        let knownIds = knownSidecarIds

        // Phase 1: Gather all file data on a background thread
        let (gathered, currentIds) = await Task.detached(priority: .userInitiated) {
            let currentIds = Set(Self.currentSidecarIdsFromDisk())
            let newIds = currentIds.subtracting(knownIds)

            if newIds.isEmpty { return ([SidecarImportData](), currentIds) }

            print("[SyncWatcher] Initial sync: gathering \(newIds.count) items from iCloud...")

            var results: [SidecarImportData] = []
            results.reserveCapacity(newIds.count)
            for id in newIds {
                if let data = Self.gatherSidecarData(id: id) {
                    results.append(data)
                }
            }
            return (results, currentIds)
        }.value

        knownSidecarIds = currentIds

        guard !gathered.isEmpty else { return }

        // Phase 2: Apply to SwiftData on main actor, in batches
        print("[SyncWatcher] Initial sync: importing \(gathered.count) items...")
        var count = 0
        for data in gathered {
            applyImport(data)
            count += 1
            if count % 20 == 0 {
                try? context?.save()
                await Task.yield()
            }
        }
        try? context?.save()
        print("[SyncWatcher] Initial sync complete: imported \(count) items")
    }

    /// Ongoing sync — triggered by DispatchSource after debounce.
    private func syncMetadata() async {
        guard context != nil else { return }

        let knownIds = knownSidecarIds

        // Phase 1: Gather on background thread
        let (gathered, deletedItemIds, currentIds) = await Task.detached(priority: .userInitiated) {
            let currentIds = Set(Self.currentSidecarIdsFromDisk())
            let newIds = currentIds.subtracting(knownIds)
            let rawDeletedIds = knownIds.subtracting(currentIds)

            var gathered: [SidecarImportData] = []
            for id in newIds {
                if let data = Self.gatherSidecarData(id: id) {
                    gathered.append(data)
                }
            }

            // Filter out items that were moved to trash (not truly deleted by remote)
            var deletedItemIds: Set<String> = []
            for id in rawDeletedIds {
                if !Self.isInTrash(id: id) {
                    deletedItemIds.insert(id)
                }
            }

            return (gathered, deletedItemIds, currentIds)
        }.value

        // Phase 2: Apply on main actor
        knownSidecarIds = currentIds

        for data in gathered {
            applyImport(data)
        }

        for id in deletedItemIds {
            removeItemFromContext(id: id)
        }

        if !gathered.isEmpty || !deletedItemIds.isEmpty {
            try? context?.save()
        }
    }

    /// Apply pre-gathered sidecar data to SwiftData. No file I/O — only model operations.
    private func applyImport(_ data: SidecarImportData) {
        guard let context else { return }

        let dataId = data.id
        let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == dataId })
        if let existing = try? context.fetch(descriptor), !existing.isEmpty { return }

        guard data.mediaFileFound else {
            print("[SyncWatcher] Media file not found for \(data.id), skipping")
            return
        }

        let item = MediaItem(
            id: data.id,
            mediaType: data.mediaType,
            filename: data.filename,
            width: data.sidecar.width,
            height: data.sidecar.height,
            createdAt: data.sidecar.createdAt,
            duration: data.sidecar.duration
        )

        if let spaceId = data.sidecar.spaceId {
            let spaceDescriptor = FetchDescriptor<Space>(predicate: #Predicate { $0.id == spaceId })
            item.space = try? context.fetch(spaceDescriptor).first
        }

        if let imageContext = data.sidecar.imageContext, !imageContext.isEmpty {
            let patterns = (data.sidecar.patterns ?? []).map { PatternTag(name: $0.name, confidence: $0.confidence) }
            item.analysisResult = AnalysisResult(
                imageContext: imageContext,
                imageSummary: data.sidecar.imageSummary ?? "",
                patterns: patterns,
                provider: "synced",
                model: "icloud-sync"
            )
        }

        context.insert(item)

        if data.needsThumbnail {
            let filename = data.filename
            let mediaType = data.mediaType
            let id = data.id
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

        print("[SyncWatcher] Imported \(data.id) from iCloud")
    }

    /// Remove a SwiftData item by ID. No file I/O.
    private func removeItemFromContext(id: String) {
        guard let context else { return }
        let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == id })
        guard let item = (try? context.fetch(descriptor))?.first else { return }
        context.delete(item)
        print("[SyncWatcher] Removed \(id) (sidecar deleted on other device)")
    }

    // MARK: - Spaces Sync

    /// Read spaces.json on background thread, apply to SwiftData on main actor.
    private func syncSpaces() async {
        guard let context else { return }

        // Phase 1: Read JSON on background thread
        let sidecarSpaces = await Task.detached {
            MetadataSidecarService.shared.readSpaces()
        }.value

        guard !sidecarSpaces.isEmpty else { return }

        // Phase 2: Apply to SwiftData on main actor
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

    // MARK: - Background File I/O Helpers (nonisolated)

    /// Gather all file-derived data for a single sidecar on a background thread.
    /// Reads JSON, checks media file existence, triggers iCloud downloads. No SwiftData access.
    private nonisolated static func gatherSidecarData(id: String) -> SidecarImportData? {
        let storage = MediaStorageService.shared
        let sidecarService = MetadataSidecarService.shared

        guard let sidecar = sidecarService.readSidecar(id: id) else { return nil }

        let mediaType: MediaType = sidecar.type == "video" ? .video : .image
        let ext = mediaType == .video ? "mp4" : "png"
        let filename = "\(id).\(ext)"

        let mediaURL = storage.mediaDir.appendingPathComponent(filename)
        let fm = FileManager.default
        var mediaFileFound = true

        if !fm.fileExists(atPath: mediaURL.path) {
            let placeholderName = ".\(filename).icloud"
            let placeholderURL = storage.mediaDir.appendingPathComponent(placeholderName)
            if fm.fileExists(atPath: placeholderURL.path) {
                try? fm.startDownloadingUbiquitousItem(at: mediaURL)
            } else {
                let altExt = mediaType == .video ? "mov" : "jpg"
                let altFilename = "\(id).\(altExt)"
                if !fm.fileExists(atPath: storage.mediaDir.appendingPathComponent(altFilename).path) {
                    mediaFileFound = false
                }
            }
        }

        let needsThumbnail = !storage.thumbnailExists(id: id)

        return SidecarImportData(
            id: id,
            sidecar: sidecar,
            mediaType: mediaType,
            filename: filename,
            mediaFileFound: mediaFileFound,
            needsThumbnail: needsThumbnail
        )
    }

    /// List sidecar IDs from disk. Safe to call from any thread.
    private nonisolated static func currentSidecarIdsFromDisk() -> [String] {
        let metadataDir = MediaStorageService.shared.metadataDir
        let files = (try? FileManager.default.contentsOfDirectory(at: metadataDir, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    /// Check whether a sidecar was moved to trash (not deleted by remote). Safe to call from any thread.
    private nonisolated static func isInTrash(id: String) -> Bool {
        let trashURL = MediaStorageService.shared.trashMetadataDir.appendingPathComponent("\(id).json")
        return FileManager.default.fileExists(atPath: trashURL.path)
    }
}
