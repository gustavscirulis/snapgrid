import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MediaItem.createdAt, order: .reverse) private var allItems: [MediaItem]
    @Query(sort: \Space.order) private var spaces: [Space]
    @State private var appState = AppState()
    @State private var videoPreview = VideoPreviewManager()
    @State private var importService = ImportService()
    @State private var searchService = SearchIndexService()

    @State private var syncWatcher = SyncWatcher()
    @State private var isDragTargeted = false
    @State private var pendingEditSpaceId: String?
    @State private var showElectronImport = false
    @State private var debounceTask: Task<Void, Never>?
    @State private var indexRebuildTask: Task<Void, Never>?
    /// Pre-computed search scores keyed by item ID. Empty = no active search.
    @State private var searchScores: [String: Double] = [:]
    @State private var isSearchActive = false
    @State private var isSearchFieldPresented = false

    #if DEBUG
    @AppStorage("debugSimulateEmptyState") private var debugSimulateEmptyState = false
    #else
    private let debugSimulateEmptyState = false
    #endif

    private func itemsForSpace(_ spaceId: String?) -> [MediaItem] {
        var items = allItems

        if let spaceId {
            items = items.filter { $0.space?.id == spaceId }
        }

        guard isSearchActive else { return items }

        let scores = searchScores
        guard !scores.isEmpty else {
            // Search is active but no results yet — check for special keywords
            let query = appState.searchText.lowercased().trimmingCharacters(in: .whitespaces)
            if query == "video" { return items.filter { $0.isVideo } }
            if query == "image" { return items.filter { !$0.isVideo } }
            return []
        }

        return items
            .filter { scores[$0.id] != nil }
            .sorted { a, b in
                let scoreA = scores[a.id] ?? 0
                let scoreB = scores[b.id] ?? 0
                return scoreA > scoreB
            }
    }

    private var activeFilteredItems: [MediaItem] {
        itemsForSpace(appState.activeSpaceId)
    }

    private var detailItemTitle: String? {
        guard let detailId = appState.detailItem,
              let item = allItems.first(where: { $0.id == detailId }) else { return nil }
        return item.analysisResult?.imageSummary
    }

    var body: some View {
        NavigationSplitView {
            SpaceSidebarView(
                spaces: spaces,
                selection: $appState.sidebarSelection,
                pendingEditSpaceId: $pendingEditSpaceId,
                onCreateSpace: createSpace,
                onDeleteSpace: deleteSpace,
                onRenameSpace: renameSpace,
                onReorderSpaces: reorderSpaces,
                onAssignToSpace: assignToSpace
            )
        } detail: {
            ZStack {
                detailContent
                    .onDrop(of: [.fileURL, .image], isTargeted: $isDragTargeted) { providers in
                        if appState.isDraggingFromApp { return false }
                        handleDrop(providers)
                        return true
                    }

                // Detail overlay — hero animation from thumbnail to full-screen view
                if let detailId = appState.detailItem,
                   let sourceFrame = appState.detailSourceFrame {
                    let overlayItems = activeFilteredItems.contains(where: { $0.id == detailId })
                        ? activeFilteredItems : allItems
                    if let startIndex = overlayItems.firstIndex(where: { $0.id == detailId }) {
                    HeroDetailOverlay(
                        items: overlayItems,
                        startIndex: startIndex,
                        sourceFrame: sourceFrame,
                        onAnimationComplete: {
                            appState.detailItem = nil
                            appState.detailSourceFrame = nil
                        },
                        onCurrentItemChanged: { newId in
                            appState.detailItem = newId
                        },
                        onShare: { id, frame in
                            shareItems(Set([id]), sourceFrame: frame)
                        },
                        onRedoAnalysis: { id in
                            retryAnalysis(Set([id]))
                        },
                        onDelete: { id in
                            deleteItems(Set([id]))
                        },
                        onAssignToSpace: { id, spaceId in
                            assignToSpace(itemIds: Set([id]), spaceId: spaceId)
                        },
                        spaces: spaces,
                        activeSpaceId: appState.activeSpaceId
                    )
                    }
                }

                // Floating video layer — ONE AVPlayerLayer that moves between grid and detail.
                FloatingVideoLayer()

                // Selection badge
                if !appState.selectedIds.isEmpty {
                    VStack {
                        Spacer()
                        SelectionBadge(count: appState.selectedIds.count)
                            .padding(.bottom, 24)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(SnapSpring.standard, value: appState.selectedIds.isEmpty)
                }

                // Toast notifications
                ToastOverlay(toasts: appState.toasts)

                // Drag overlay — only for external drags (Finder, browser, etc.)
                if isDragTargeted && !appState.isDraggingFromApp {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.snapAccent, lineWidth: 3)
                        .background(Color.snapAccent.opacity(0.1))
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 400)
        .navigationTitle(detailItemTitle ?? "SnapGrid")
        .searchable(text: $appState.searchText, isPresented: $isSearchFieldPresented, placement: .toolbar, prompt: "Search patterns, descriptions...")
        .toolbar {
            if appState.detailItem != nil {
                ToolbarItem(placement: .navigation) {
                    Button {
                        NotificationCenter.default.post(name: .closeDetail, object: nil)
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
            }
            if let detailId = appState.detailItem {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if let window = NSApp.keyWindow {
                            let frame = CGRect(
                                x: window.frame.width - 100,
                                y: window.frame.height - 50,
                                width: 40, height: 40
                            )
                            shareItems(Set([detailId]), sourceFrame: frame)
                        }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .onChange(of: isDragTargeted) { _, targeted in
            if !targeted {
                appState.isDraggingFromApp = false
            }
        }
        .modifier(NotificationModifier(
            onImportFiles: { openImportPanel() },
            onImportElectron: { showElectronImport = true },
            onUndoDelete: { undoLastDelete() },
            onApiKeySaved: {
                Task {
                    await importService.analyzeUnanalyzedItems(from: Array(allItems), context: modelContext)
                }
            },
            onCreateNewSpace: { createSpace() },
            onFocusSearch: {
                isSearchFieldPresented = true
            },
            onSelectAll: { appState.selectAll(activeFilteredItems.map(\.id)) },
            onSwitchToSpace: { digit in
                if digit == 1 {
                    switchToSpace(nil)
                } else {
                    let idx = digit - 2
                    if idx < spaces.count {
                        switchToSpace(spaces[idx].id)
                    }
                }
            },
            onPasteImages: { handlePaste() }
        ))
        .sheet(isPresented: $showElectronImport) {
            ElectronImportView(isPresented: $showElectronImport)
                .presentationBackground(Color.snapCard)
        }
        .onChange(of: showElectronImport) { _, isPresented in
            if !isPresented {
                syncWatcher.beginLocalChange()
                syncWatcher.endLocalChange()
            }
        }
        .onChange(of: appState.searchText) { _, newValue in
            debounceTask?.cancel()
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                isSearchActive = false
                searchScores = [:]
            } else {
                isSearchActive = true
                debounceTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled else { return }

                    let lowered = trimmed.lowercased()
                    if lowered == "video" || lowered == "image" {
                        searchScores = [:]
                        return
                    }

                    // BM25 search: <1ms, pure dictionary lookups + arithmetic
                    let results = searchService.search(query: trimmed)
                    guard !Task.isCancelled else { return }
                    searchScores = Dictionary(uniqueKeysWithValues: results.map { ($0.itemId, $0.score) })
                }
            }
        }
        .task {
            // Reset any isAnalyzing flags stuck from a previous crash/kill
            let stuckDescriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.isAnalyzing == true })
            if let stuck = try? modelContext.fetch(stuckDescriptor), !stuck.isEmpty {
                for item in stuck { item.isAnalyzing = false }
                modelContext.saveOrLog()
                print("[Cleanup] Reset \(stuck.count) stuck isAnalyzing flags")
            }

            MediaStorageService.shared.emptyOldTrash()
            MigrationService.migrateIfNeeded(context: modelContext)
            DataCleanupService.cleanOrphanedRecords(context: modelContext)
            DataCleanupService.cleanOrphanedSidecars()
            await DataCleanupService.migrateVideoDimensions(context: modelContext)

            // Sync items that arrived via iCloud while app was closed
            await syncWatcher.initialSync(context: modelContext)
            syncWatcher.startWatching(context: modelContext)

            // Auto-download evicted iCloud files if user has opted in
            if UserDefaults.standard.bool(forKey: "keepFilesLocal") {
                iCloudDownloadManager.shared.downloadAll()
            }

            // Auto-analyze any items that arrived without AI analysis (e.g. from iOS share extension)
            await importService.analyzeUnanalyzedItems(from: allItems, context: modelContext)

            // Build search index from metadata (instant — pure tokenization + dictionary building)
            searchService.buildIndex(items: allItems)
            // Build word-vector embeddings in background for synonym matching (non-blocking)
            searchService.buildEmbeddingsInBackground(items: allItems)

            // Wire SyncWatcher callback — analyze new items arriving via iCloud in real-time
            syncWatcher.onNewUnanalyzedItems = { ids in
                Task {
                    let descriptor = FetchDescriptor<MediaItem>()
                    guard let items = try? modelContext.fetch(descriptor) else { return }
                    let newItems = items.filter { ids.contains($0.id) }
                    for item in newItems {
                        await importService.analyzeItem(item, context: modelContext)
                    }
                }
            }

        }
        .task {
            // Re-sync when app regains focus (picks up iCloud changes from other devices).
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                await syncWatcher.resyncFromDisk()
                await importService.analyzeUnanalyzedItems(from: allItems, context: modelContext)
            }
        }
        .onChange(of: allItems.count) { _, _ in
            indexRebuildTask?.cancel()
            indexRebuildTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                searchService.buildIndex(items: allItems)
            }
        }
        .task {
            for await notification in NotificationCenter.default.notifications(named: .analysisCompleted) {
                guard let itemId = notification.userInfo?["itemId"] as? String,
                      let item = allItems.first(where: { $0.id == itemId }) else { continue }
                searchService.addToIndex(item: item)
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .willResetAllData) {
                handleResetAllData()
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .deleteSelected) {
                deleteSelectedItems()
            }
        }
        .onDeleteCommand {
            deleteSelectedItems()
        }
        .onExitCommand {
            if appState.detailItem != nil {
                appState.detailItem = nil
                appState.detailSourceFrame = nil
            } else if !appState.selectedIds.isEmpty {
                appState.clearSelection()
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .zoomIn) {
                appState.zoomIn()
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .zoomOut) {
                appState.zoomOut()
            }
        }
        .environment(appState)
        .environment(videoPreview)
        .environment(importService)
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        let items = activeFilteredItems
        if allItems.isEmpty || debugSimulateEmptyState {
            EmptyStateView(isDragTargeted: isDragTargeted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty && isSearchActive {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.secondary)
                Text("No results found")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty && appState.activeSpaceId != nil {
            EmptyStateView(mode: .spaceLevel, isDragTargeted: isDragTargeted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            MasonryGridView(
                items: items,
                thumbnailSize: appState.thumbnailSize,
                spaces: spaces,
                activeSpaceId: appState.activeSpaceId,
                hiddenItemId: appState.detailItem,
                onSelect: { id, frame in
                    appState.detailSourceFrame = frame
                    appState.detailItem = id
                },
                onToggleSelect: { id in appState.toggleSelection(id) },
                onShiftSelect: { id in
                    appState.rangeSelect(
                        targetId: id,
                        orderedIds: items.map(\.id)
                    )
                },
                onDelete: deleteItems,
                onAssignToSpace: assignToSpace,
                onRetryAnalysis: retryAnalysis,
                onShare: { ids, frame in shareItems(ids, sourceFrame: frame) },
                onSetSelection: { ids in appState.selectedIds = ids },
                coordinateSpaceName: "gridContent"
            )
        }
    }

    // MARK: - Space Navigation

    private func switchToSpace(_ newId: String?) {
        appState.sidebarSelection = newId.map { .space($0) } ?? .all
    }

    // MARK: - Actions

    private func handleDrop(_ providers: [NSItemProvider]) {
        Task {
            var urls: [URL] = []
            var images: [NSImage] = []
            let storagePath = MediaStorageService.shared.mediaDir.path

            for provider in providers {
                // Try file URL first (local file drags from Finder)
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
                   let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier),
                   let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil),
                   url.isFileURL {
                    // Skip internal drags (grid items already in our storage)
                    if url.path.hasPrefix(storagePath) { continue }
                    urls.append(url)
                }
                // Fall back to image data (browser drags)
                else if provider.canLoadObject(ofClass: NSImage.self),
                        let image = try? await loadImageFromProvider(provider) {
                    images.append(image)
                }
            }

            if !urls.isEmpty || !images.isEmpty {
                syncWatcher.beginLocalChange()
                await importService.importFiles(urls, into: modelContext, spaceId: appState.activeSpaceId)
                for image in images {
                    await importService.importImage(image, into: modelContext, spaceId: appState.activeSpaceId)
                }
                syncWatcher.endLocalChange()
            }
        }
    }

    private func loadImageFromProvider(_ provider: NSItemProvider) async throws -> NSImage {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadObject(ofClass: NSImage.self) { object, error in
                if let image = object as? NSImage {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "SnapGrid", code: -1))
                }
            }
        }
    }

    private func handlePaste() {
        let pasteboard = NSPasteboard.general

        // Try file URLs first (e.g. copied files from Finder)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                              options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            let validURLs = urls.filter { SupportedMedia.isSupported($0.pathExtension) }
            if !validURLs.isEmpty {
                syncWatcher.beginLocalChange()
                Task {
                    await importService.importFiles(validURLs, into: modelContext, spaceId: appState.activeSpaceId)
                    syncWatcher.endLocalChange()
                    appState.showToast("Pasted \(validURLs.count) item\(validURLs.count == 1 ? "" : "s")")
                }
                return
            }
        }

        // Fall back to image data (e.g. copied from browser, Preview, screenshot)
        if let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage], !images.isEmpty {
            syncWatcher.beginLocalChange()
            Task {
                for image in images {
                    await importService.importImage(image, into: modelContext, spaceId: appState.activeSpaceId)
                }
                syncWatcher.endLocalChange()
                appState.showToast("Pasted \(images.count) image\(images.count == 1 ? "" : "s")")
            }
            return
        }

        // Fall back to text URL (e.g. copied URL from browser address bar)
        if let strings = pasteboard.readObjects(forClasses: [NSString.self]) as? [String] {
            let urls = strings.compactMap { str -> URL? in
                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let url = URL(string: trimmed),
                      let scheme = url.scheme?.lowercased(),
                      scheme == "http" || scheme == "https" else { return nil }
                return url
            }
            if !urls.isEmpty {
                syncWatcher.beginLocalChange()
                Task {
                    let hasTwitterURL = urls.contains(where: { TwitterVideoService.isTwitterURL($0) })
                    appState.showToast(hasTwitterURL ? "Downloading from X..." : "Downloading\(urls.count == 1 ? "" : " \(urls.count) items")...")
                    var successCount = 0
                    for url in urls {
                        do {
                            if TwitterVideoService.isTwitterURL(url) {
                                try await importService.importFromTwitterURL(url, into: modelContext, spaceId: appState.activeSpaceId)
                            } else {
                                try await importService.importFromURL(url, into: modelContext, spaceId: appState.activeSpaceId)
                            }
                            successCount += 1
                        } catch {
                            print("[Paste] Failed to import URL \(url): \(error)")
                            if TwitterVideoService.isTwitterURL(url) {
                                appState.showToast(error.localizedDescription)
                            }
                        }
                    }
                    syncWatcher.endLocalChange()
                    if successCount > 0 {
                        appState.showToast("Imported \(successCount) item\(successCount == 1 ? "" : "s")")
                    } else if !hasTwitterURL {
                        appState.showToast("URL doesn't point to a supported image or video")
                    }
                }
            }
        }
    }

    private func openImportPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = SupportedMedia.importableContentTypes

        panel.begin { response in
            if response == .OK {
                syncWatcher.beginLocalChange()
                Task {
                    await importService.importFiles(panel.urls, into: modelContext, spaceId: appState.activeSpaceId)
                    syncWatcher.endLocalChange()
                }
            }
        }
    }

    private func deleteItems(_ ids: Set<String>) {
        let items = allItems.filter { ids.contains($0.id) }
        guard !items.isEmpty else { return }

        // Snapshot for undo
        let batch = items.map { item in
            let ar = item.analysisResult
            return DeletedItemInfo(
                id: item.id,
                filename: item.filename,
                mediaType: item.mediaType,
                width: item.width,
                height: item.height,
                duration: item.duration,
                spaceId: item.space?.id,
                imageContext: ar?.imageContext,
                imageSummary: ar?.imageSummary,
                patterns: ar?.patterns,
                analyzedAt: ar?.analyzedAt,
                analysisProvider: ar?.provider,
                analysisModel: ar?.model
            )
        }
        appState.pushDeleteBatch(batch)
        appState.clearSelection()

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        if reduceMotion {
            withAnimation(CardCrush.reducedMotionFade) {
                for id in ids { appState.deletingItemStages[id] = 2 }
            }
            Task { @MainActor in
                try? await Task.sleep(for: CardCrush.reducedMotionDelay)
                commitDeletion(ids)
            }
        } else {
            withAnimation(CardCrush.heightCrush) {
                for id in ids { appState.deletingItemStages[id] = 1 }
            }
            Task { @MainActor in
                try? await Task.sleep(for: CardCrush.widthDelay)
                withAnimation(CardCrush.widthCrush) {
                    for id in ids { appState.deletingItemStages[id] = 2 }
                }

                try? await Task.sleep(for: CardCrush.completeDelay)
                commitDeletion(ids)
            }
        }
    }

    private func commitDeletion(_ ids: Set<String>) {
        guard ids.contains(where: { appState.deletingItemStages[$0] != nil }) else { return }

        let items = allItems.filter { ids.contains($0.id) }

        syncWatcher.beginLocalChange()
        var trashedCount = 0
        for item in items {
            do {
                try MediaStorageService.shared.moveToTrash(filename: item.filename, id: item.id)
                modelContext.delete(item)
                trashedCount += 1
            } catch {
                print("[Delete] Failed to trash \(item.id): \(error)")
            }
        }
        withAnimation(SnapSpring.standard) {
            modelContext.saveOrLog()
        }
        syncWatcher.endLocalChange()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            for id in ids { appState.deletingItemStages.removeValue(forKey: id) }
        }

        if trashedCount > 0 {
            appState.showToast("Moved \(trashedCount) item\(trashedCount == 1 ? "" : "s") to trash")
        }
        if trashedCount < items.count {
            appState.showToast("Failed to trash \(items.count - trashedCount) item\(items.count - trashedCount == 1 ? "" : "s")")
        }
    }

    private func deleteSelectedItems() {
        guard !appState.selectedIds.isEmpty else { return }
        deleteItems(appState.selectedIds)
    }

    private func undoLastDelete() {
        guard let batch = appState.popDeleteBatch() else { return }

        syncWatcher.beginLocalChange()
        for info in batch {
            try? MediaStorageService.shared.restoreFromTrash(filename: info.filename, id: info.id)

            let item = MediaItem(
                id: info.id,
                mediaType: info.mediaType,
                filename: info.filename,
                width: info.width,
                height: info.height,
                duration: info.duration
            )
            if let ctx = info.imageContext, let summary = info.imageSummary,
               let patterns = info.patterns, let provider = info.analysisProvider,
               let model = info.analysisModel {
                item.analysisResult = AnalysisResult(
                    imageContext: ctx,
                    imageSummary: summary,
                    patterns: patterns,
                    analyzedAt: info.analyzedAt ?? .now,
                    provider: provider,
                    model: model
                )
            }

            if let spaceId = info.spaceId {
                let descriptor = FetchDescriptor<Space>(predicate: #Predicate { $0.id == spaceId })
                item.space = try? modelContext.fetch(descriptor).first
            }

            modelContext.insert(item)
            MetadataSidecarService.shared.writeSidecar(for: item)
        }
        modelContext.saveOrLog()
        syncWatcher.endLocalChange()
        appState.showToast("Restored \(batch.count) item\(batch.count == 1 ? "" : "s")")
    }

    private func createSpace() {
        syncWatcher.beginLocalChange()
        let space = Space(name: "New Space", order: spaces.count)
        modelContext.insert(space)
        modelContext.saveOrLog()
        MetadataSidecarService.shared.writeSpaces(from: modelContext)
        syncWatcher.endLocalChange()
        switchToSpace(space.id)
        pendingEditSpaceId = space.id
    }

    private func deleteSpace(_ id: String) {
        guard let space = spaces.first(where: { $0.id == id }) else { return }

        if appState.activeSpaceId == id {
            appState.sidebarSelection = .all
        }

        syncWatcher.beginLocalChange()
        for item in space.items {
            item.space = nil
        }
        modelContext.delete(space)
        modelContext.saveOrLog()
        MetadataSidecarService.shared.writeSpaces(from: modelContext)
        syncWatcher.endLocalChange()
    }

    private func renameSpace(_ id: String, _ newName: String) {
        if let space = spaces.first(where: { $0.id == id }) {
            syncWatcher.beginLocalChange()
            space.name = newName
            modelContext.saveOrLog()
            MetadataSidecarService.shared.writeSpaces(Array(spaces))
            syncWatcher.endLocalChange()
        }
    }

    private func reorderSpaces(from fromIndex: Int, to toIndex: Int) {
        guard fromIndex != toIndex,
              fromIndex >= 0, fromIndex < spaces.count,
              toIndex >= 0, toIndex < spaces.count else { return }

        syncWatcher.beginLocalChange()
        var ordered = spaces.sorted(by: { $0.order < $1.order })
        let moved = ordered.remove(at: fromIndex)
        ordered.insert(moved, at: toIndex)

        for (i, space) in ordered.enumerated() {
            space.order = i
        }
        modelContext.saveOrLog()
        MetadataSidecarService.shared.writeSpaces(Array(spaces))
        syncWatcher.endLocalChange()
    }

    private func assignToSpace(itemIds: Set<String>, spaceId: String?) {
        let space = spaceId.flatMap { sid in spaces.first(where: { $0.id == sid }) }
        let itemsToUpdate = allItems.filter { itemIds.contains($0.id) }

        syncWatcher.beginLocalChange()
        for item in itemsToUpdate {
            item.space = space
        }
        modelContext.saveOrLog()

        for item in itemsToUpdate {
            MetadataSidecarService.shared.writeSidecar(for: item)
        }
        syncWatcher.endLocalChange()

        if let space, space.useCustomPrompt, space.customPrompt != nil {
            for item in itemsToUpdate {
                Task {
                    await importService.analyzeItem(item, context: modelContext)
                }
            }
        }
    }

    private func handleResetAllData() {
        appState.detailItem = nil
        appState.detailSourceFrame = nil
        appState.clearSelection()
        appState.sidebarSelection = .all
    }

    private func retryAnalysis(_ ids: Set<String>) {
        let items = allItems.filter { ids.contains($0.id) }
        for item in items {
            item.analysisError = nil
            item.analysisResult = nil
        }
        modelContext.saveOrLog()
        for item in items {
            Task {
                await importService.analyzeItem(item, context: modelContext)
            }
        }
    }

    private func shareItems(_ ids: Set<String>, sourceFrame: CGRect) {
        let urls = allItems
            .filter { ids.contains($0.id) }
            .map { MediaStorageService.shared.mediaURL(filename: $0.filename) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SnapGridShare")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempURLs = urls.compactMap { url -> URL? in
            let dest = tempDir.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: url, to: dest)
            return dest
        }
        guard !tempURLs.isEmpty else { return }

        let picker = NSSharingServicePicker(items: tempURLs)
        if let window = NSApp.keyWindow,
           let contentView = window.contentView {
            let rect = contentView.convert(sourceFrame, from: nil)
            picker.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
        }
    }

}

// MARK: - Notification Modifier
// Extracted to reduce body complexity and avoid Swift type-checker timeouts.

private struct NotificationModifier: ViewModifier {
    let onImportFiles: () -> Void
    let onImportElectron: () -> Void
    let onUndoDelete: () -> Void
    let onApiKeySaved: () -> Void
    let onCreateNewSpace: () -> Void
    let onFocusSearch: () -> Void
    let onSelectAll: () -> Void
    let onSwitchToSpace: (Int) -> Void
    let onPasteImages: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .importFiles)) { _ in
                onImportFiles()
            }
            .onReceive(NotificationCenter.default.publisher(for: .importElectronLibrary)) { _ in
                onImportElectron()
            }
            .onReceive(NotificationCenter.default.publisher(for: .undoDelete)) { _ in
                onUndoDelete()
            }
            .onReceive(NotificationCenter.default.publisher(for: .apiKeySaved)) { _ in
                onApiKeySaved()
            }
            .onReceive(NotificationCenter.default.publisher(for: .createNewSpace)) { _ in
                onCreateNewSpace()
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
                onFocusSearch()
            }
            .onReceive(NotificationCenter.default.publisher(for: .selectAll)) { _ in
                onSelectAll()
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchToSpaceByIndex)) { notification in
                guard let digit = notification.userInfo?["digit"] as? Int else { return }
                onSwitchToSpace(digit)
            }
            .onReceive(NotificationCenter.default.publisher(for: .pasteImages)) { _ in
                onPasteImages()
            }
    }
}
