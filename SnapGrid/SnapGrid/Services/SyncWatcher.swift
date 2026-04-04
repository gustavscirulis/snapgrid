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
    private var knownSidecarIds: [String: Date] = [:]
    private var context: ModelContext?
    /// When true, ignore file-system events (we caused them ourselves).
    private var suppressingLocalChanges = false

    private let storage = MediaStorageService.shared
    private let sidecarService = MetadataSidecarService.shared

    /// Called when new items without analysis are imported via sync.
    var onNewUnanalyzedItems: (([String]) -> Void)?

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

    /// Update for existing items whose sidecar changed (e.g. space assignment, analysis, source URL).
    private struct SidecarUpdateData: Sendable {
        let id: String
        let spaceId: String?
        let sourceURL: String?
        let imageContext: String?
        let imageSummary: String?
        let patterns: [SidecarPattern]?
        let analyzedAt: Date?
    }

    // MARK: - Public API

    /// Call BEFORE local mutations that write sidecar/spaces files.
    func beginLocalChange() {
        suppressingLocalChanges = true
    }

    /// Call AFTER local mutations complete. Updates known state so the watcher
    /// won't react to our own file changes when suppression ends.
    func endLocalChange() {
        knownSidecarIds = Self.currentSidecarIdsWithDatesFromDisk()
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

        knownSidecarIds = Self.currentSidecarIdsWithDatesFromDisk()

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
        metadataFD = -1
        spacesSource?.cancel()
        spacesSource = nil
        spacesFD = -1
        debounceTask?.cancel()
        spacesDebounceTask?.cancel()
        context = nil
    }

    /// Perform an initial sync on launch — picks up items that arrived via iCloud while the app was closed.
    func initialSync(context: ModelContext) async {
        self.context = context
        await syncSpaces()          // Spaces FIRST so items can resolve spaceId
        await syncMetadataAsync()
    }

    /// Force a full re-sync by clearing cached state so every file on disk is re-evaluated.
    /// Handles additions, modifications, and deletions. Use on app focus to catch iCloud changes
    /// that DispatchSource may have missed.
    func resyncFromDisk() async {
        knownSidecarIds = [:]
        await syncMetadata()
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

    /// Result of gathering file changes on a background thread.
    private struct GatheredChanges: Sendable {
        let newItems: [SidecarImportData]
        let updates: [SidecarUpdateData]
        let deletedIds: Set<String>
        let currentDates: [String: Date]
    }

    /// Shared Phase 1: Gather all file-derived changes on a background thread.
    /// When `detectDeletions` is true (ongoing sync), also reports IDs that disappeared from disk.
    private func gatherChangesFromDisk(detectDeletions: Bool) async -> GatheredChanges {
        let knownDates = knownSidecarIds

        return await Task.detached(priority: .userInitiated) {
            let currentDates = Self.currentSidecarIdsWithDatesFromDisk()
            let currentIds = Set(currentDates.keys)
            let knownIds = Set(knownDates.keys)
            let newIds = currentIds.subtracting(knownIds)

            // Detect modified sidecars (existing IDs whose mod date changed)
            var modifiedIds: Set<String> = []
            for id in currentIds.intersection(knownIds) {
                if let currentDate = currentDates[id],
                   let knownDate = knownDates[id],
                   currentDate > knownDate {
                    modifiedIds.insert(id)
                }
            }

            var newItems: [SidecarImportData] = []
            newItems.reserveCapacity(newIds.count)
            for id in newIds {
                if let data = Self.gatherSidecarData(id: id) {
                    newItems.append(data)
                }
            }

            var updates: [SidecarUpdateData] = []
            for id in modifiedIds {
                if let sidecar = MetadataSidecarService.shared.readSidecar(id: id) {
                    updates.append(SidecarUpdateData(
                        id: id,
                        spaceId: sidecar.spaceId,
                        sourceURL: sidecar.sourceURL,
                        imageContext: sidecar.imageContext,
                        imageSummary: sidecar.imageSummary,
                        patterns: sidecar.patterns,
                        analyzedAt: sidecar.analyzedAt
                    ))
                }
            }

            // Filter out items moved to local trash (not truly deleted by remote)
            var deletedIds: Set<String> = []
            if detectDeletions {
                let rawDeletedIds = knownIds.subtracting(currentIds)
                for id in rawDeletedIds {
                    if !Self.isInTrash(id: id) {
                        deletedIds.insert(id)
                    }
                }
            }

            return GatheredChanges(
                newItems: newItems, updates: updates,
                deletedIds: deletedIds, currentDates: currentDates
            )
        }.value
    }

    /// Initial sync on launch — gathers then applies in batches with yielding.
    private func syncMetadataAsync() async {
        guard context != nil else { return }

        let changes = await gatherChangesFromDisk(detectDeletions: false)
        knownSidecarIds = changes.currentDates

        guard !changes.newItems.isEmpty || !changes.updates.isEmpty else { return }

        // Apply to SwiftData on main actor, in batches
        if !changes.newItems.isEmpty {
            print("[SyncWatcher] Initial sync: importing \(changes.newItems.count) items...")
            var count = 0
            for data in changes.newItems {
                applyImport(data)
                count += 1
                if count % 20 == 0 {
                    context?.saveOrLog()
                    await Task.yield()
                }
            }
            print("[SyncWatcher] Initial sync complete: imported \(count) items")
        }

        for update in changes.updates {
            applySpaceUpdate(update)
        }

        context?.saveOrLog()
    }

    /// Ongoing sync — triggered by DispatchSource after debounce.
    private func syncMetadata() async {
        guard context != nil else { return }

        let changes = await gatherChangesFromDisk(detectDeletions: true)
        knownSidecarIds = changes.currentDates

        var unanalyzedIds: [String] = []
        for data in changes.newItems {
            applyImport(data)
            if data.sidecar.imageContext == nil || (data.sidecar.imageContext?.isEmpty ?? true) {
                unanalyzedIds.append(data.id)
            }
        }

        for update in changes.updates {
            applySpaceUpdate(update)
        }

        for id in changes.deletedIds {
            removeItemFromContext(id: id)
        }

        if !changes.newItems.isEmpty || !changes.updates.isEmpty || !changes.deletedIds.isEmpty {
            context?.saveOrLog()
        }

        if !unanalyzedIds.isEmpty {
            onNewUnanalyzedItems?(unanalyzedIds)
        }
    }

    /// Apply pre-gathered sidecar data to SwiftData. No file I/O — only model operations.
    private func applyImport(_ data: SidecarImportData) {
        guard let context else { return }

        let dataId = data.id
        let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == dataId })
        if let existing = try? context.fetch(descriptor), let existingItem = existing.first {
            // Item already imported — still reconcile space assignment and sourceURL
            if let spaceId = data.sidecar.spaceId, existingItem.space?.id != spaceId {
                let spaceDescriptor = FetchDescriptor<Space>(predicate: #Predicate { $0.id == spaceId })
                existingItem.space = try? context.fetch(spaceDescriptor).first
            } else if data.sidecar.spaceId == nil && existingItem.space != nil {
                existingItem.space = nil
            }
            if existingItem.sourceURL == nil, let sourceURL = data.sidecar.sourceURL {
                existingItem.sourceURL = sourceURL
            }
            return
        }

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

        item.sourceURL = data.sidecar.sourceURL

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
                analyzedAt: data.sidecar.analyzedAt ?? .now,
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

    /// Update space assignment, analysis, and source URL on an existing item. No file I/O.
    private func applySpaceUpdate(_ update: SidecarUpdateData) {
        guard let context else { return }

        let updateId = update.id
        let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == updateId })
        guard let item = (try? context.fetch(descriptor))?.first else { return }

        if let spaceId = update.spaceId {
            if item.space?.id != spaceId {
                let spaceDescriptor = FetchDescriptor<Space>(predicate: #Predicate { $0.id == spaceId })
                item.space = try? context.fetch(spaceDescriptor).first
                print("[SyncWatcher] Updated space for \(update.id) -> \(spaceId)")
            }
        } else if item.space != nil {
            item.space = nil
            print("[SyncWatcher] Removed space assignment for \(update.id)")
        }

        if item.sourceURL == nil, let sourceURL = update.sourceURL {
            item.sourceURL = sourceURL
            print("[SyncWatcher] Updated sourceURL for \(update.id)")
        }

        // Sync analysis results if the remote sidecar has newer or missing-locally analysis
        if let imageContext = update.imageContext, !imageContext.isEmpty {
            let shouldSync: Bool
            if item.analysisResult == nil {
                shouldSync = true
            } else if let remoteDate = update.analyzedAt,
                      let localDate = item.analysisResult?.analyzedAt,
                      remoteDate > localDate {
                shouldSync = true
            } else {
                shouldSync = false
            }

            if shouldSync {
                let patterns = (update.patterns ?? []).map { PatternTag(name: $0.name, confidence: $0.confidence) }
                item.analysisResult = AnalysisResult(
                    imageContext: imageContext,
                    imageSummary: update.imageSummary ?? "",
                    patterns: patterns,
                    analyzedAt: update.analyzedAt ?? .now,
                    provider: "synced",
                    model: "icloud-sync"
                )
                print("[SyncWatcher] Synced analysis result for \(update.id)")
            }
        }
    }

    // MARK: - Spaces Sync

    /// Read spaces.json on background thread, apply to SwiftData on main actor.
    private func syncSpaces() async {
        guard let context else { return }

        // Phase 1: Read JSON on background thread (use wrapper format for all-space guidance)
        let spacesFile = await Task.detached {
            MetadataSidecarService.shared.readSpacesFile()
        }.value

        let sidecarSpaces = spacesFile.spaces

        // Phase 2: Sync all-space guidance to UserDefaults
        if let allGuidance = spacesFile.allSpaceGuidance {
            UserDefaults.standard.set(allGuidance, forKey: "allSpacePrompt")
        }
        UserDefaults.standard.set(spacesFile.useAllSpaceGuidance, forKey: "useAllSpacePrompt")

        // Phase 3: Apply spaces to SwiftData on main actor
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
                if space.customPrompt != sidecar.customPrompt { space.customPrompt = sidecar.customPrompt }
                if space.useCustomPrompt != sidecar.useCustomPrompt { space.useCustomPrompt = sidecar.useCustomPrompt }
            } else {
                // Space was deleted on the other device
                context.delete(space)
                print("[SyncWatcher] Removed space \(space.name) (deleted on other device)")
            }
        }

        context.saveOrLog()
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

    /// List sidecar IDs with their modification dates from disk. Safe to call from any thread.
    private nonisolated static func currentSidecarIdsWithDatesFromDisk() -> [String: Date] {
        let metadataDir = MediaStorageService.shared.metadataDir
        let files = (try? FileManager.default.contentsOfDirectory(
            at: metadataDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        var result: [String: Date] = [:]
        for file in files where file.pathExtension == "json" {
            let id = file.deletingPathExtension().lastPathComponent
            let modDate = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            result[id] = modDate
        }
        return result
    }

    /// Check whether a sidecar was moved to trash (not deleted by remote). Safe to call from any thread.
    private nonisolated static func isInTrash(id: String) -> Bool {
        let trashURL = MediaStorageService.shared.trashMetadataDir.appendingPathComponent("\(id).json")
        return FileManager.default.fileExists(atPath: trashURL.path)
    }
}
