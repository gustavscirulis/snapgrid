import SwiftUI
import SwiftData
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

    private var activeIndex: Int {
        spaceIndex(for: appState.activeSpaceId)
    }

    var body: some View {
        ZStack {
            Color.snapBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Space tab bar
                SpaceTabBar(
                    spaces: spaces,
                    activeSpaceId: appState.activeSpaceId,
                    pendingEditSpaceId: $pendingEditSpaceId,
                    onSelectSpace: switchToSpace,
                    onCreateSpace: createSpace,
                    onDeleteSpace: deleteSpace,
                    onRenameSpace: renameSpace,
                    onReorderSpaces: reorderSpaces,
                    onAssignToSpace: assignToSpace
                )
                .padding(.top, 8)

                // Main content — horizontal carousel of space pages
                // File-import .onDrop is scoped here (not the whole window) so it
                // doesn't steal drags from SpaceTabBar's .onDrop for space assignment.
                Group {
                    if allItems.isEmpty || debugSimulateEmptyState {
                        EmptyStateView(isDragTargeted: isDragTargeted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        GeometryReader { geo in
                            let pageWidth = geo.size.width
                            let pageHeight = geo.size.height

                            HStack(spacing: 0) {
                                // "All" page (index 0)
                                spacePageView(spaceId: nil, pageWidth: pageWidth, pageHeight: pageHeight, pageIndex: 0)

                                // Per-space pages (index 1+)
                                ForEach(Array(spaces.enumerated()), id: \.element.id) { index, space in
                                    spacePageView(spaceId: space.id, pageWidth: pageWidth, pageHeight: pageHeight, pageIndex: index + 1)
                                }
                            }
                            .offset(x: -CGFloat(activeIndex) * pageWidth)
                        }
                        .clipped()
                    }
                }
                .onDrop(of: [.fileURL, .image], isTargeted: $isDragTargeted) { providers in
                    handleDrop(providers)
                    return true
                }
            }

            // Detail overlay — hero animation from thumbnail to centered view
            // Existence check uses allItems so search changes can't remove the overlay.
            // Navigation uses activeFilteredItems when the item is in the set, else allItems.
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
                    }
                )
                }
            }

            // Floating video layer — ONE AVPlayerLayer that moves between grid and detail.
            // Placed after HeroDetailOverlay so it renders above the backdrop.
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
        .frame(minWidth: 540, minHeight: 400)
        .searchable(text: $appState.searchText, isPresented: $isSearchFieldPresented, placement: .toolbar, prompt: "Search patterns, descriptions...")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Spacer()
            }
        }
        // Note: .onDrop for file imports is on the content area Group above,
        // NOT here on the outer ZStack — so it doesn't steal drags from SpaceTabBar.
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
            MediaStorageService.shared.emptyOldTrash()
            MigrationService.migrateIfNeeded(context: modelContext)
            DataCleanupService.cleanOrphanedRecords(context: modelContext)
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
            // Uses resyncFromDisk() which clears cached state and does a full disk comparison,
            // because DispatchSource doesn't reliably fire for iCloud-synced file changes.
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                await syncWatcher.resyncFromDisk()
                // Analyze any new items that arrived without AI analysis
                await importService.analyzeUnanalyzedItems(from: allItems, context: modelContext)
            }
        }
        .onChange(of: allItems.count) { _, _ in
            // Rebuild index when items are added/removed (covers imports, syncs, deletions)
            searchService.buildIndex(items: allItems)
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
                // Fallback: overlay normally handles its own close via focus +
                // .onExitCommand. If focus is lost, dismiss immediately.
                appState.detailItem = nil
                appState.detailSourceFrame = nil
            } else if !appState.selectedIds.isEmpty {
                appState.clearSelection()
            }
        }
        .onKeyPress(.init("="), phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            appState.zoomIn()
            return .handled
        }
        .onKeyPress(.init("-"), phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            appState.zoomOut()
            return .handled
        }
        .environment(appState)
        .environment(videoPreview)
        .environment(importService)
    }

    // MARK: - Space Navigation

    private func switchToSpace(_ newId: String?) {
        withAnimation(SnapSpring.standard) {
            appState.activeSpaceId = newId
        }
    }

    private func spaceIndex(for id: String?) -> Int {
        guard let id else { return 0 }
        return (spaces.firstIndex(where: { $0.id == id }) ?? -1) + 1
    }

    @ViewBuilder
    private func spacePageView(spaceId: String?, pageWidth: CGFloat, pageHeight: CGFloat, pageIndex: Int) -> some View {
        let items = itemsForSpace(spaceId)

        Color.clear
            .frame(width: pageWidth, height: pageHeight)
            .overlay {
                if items.isEmpty && isSearchActive {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("No results found")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                } else if items.isEmpty && spaceId != nil {
                    EmptyStateView(mode: .spaceLevel, isDragTargeted: isDragTargeted)
                } else {
                    MasonryGridView(
                        items: items,
                        thumbnailSize: appState.thumbnailSize,
                        selectedIds: appState.selectedIds,
                        spaces: spaces,
                        activeSpaceId: spaceId,
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
                        onSetSelection: { ids in appState.selectedIds = ids },
                        coordinateSpaceName: "gridContent-\(spaceId ?? "all")"
                    )
                }
            }
            .clipped()
            .allowsHitTesting(pageIndex == activeIndex)
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
                // Fall back to image data (browser drags) — uses NSItemProviderReading
                // to handle any image format the provider offers
                else if provider.canLoadObject(ofClass: NSImage.self),
                        let image = try? await loadImageFromProvider(provider) {
                    images.append(image)
                }
            }

            if !urls.isEmpty {
                await importService.importFiles(urls, into: modelContext, spaceId: appState.activeSpaceId)
            }
            for image in images {
                await importService.importImage(image, into: modelContext, spaceId: appState.activeSpaceId)
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
            let supportedExts: Set<String> = ["png","jpg","jpeg","gif","bmp","tiff","webp","heic",
                                               "mp4","webm","mov","avi","m4v"]
            let validURLs = urls.filter { supportedExts.contains($0.pathExtension.lowercased()) }
            if !validURLs.isEmpty {
                Task {
                    await importService.importFiles(validURLs, into: modelContext, spaceId: appState.activeSpaceId)
                    appState.showToast("Pasted \(validURLs.count) item\(validURLs.count == 1 ? "" : "s")")
                }
                return
            }
        }

        // Fall back to image data (e.g. copied from browser, Preview, screenshot)
        if let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage], !images.isEmpty {
            Task {
                for image in images {
                    await importService.importImage(image, into: modelContext, spaceId: appState.activeSpaceId)
                }
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
        // electron/main.js:1761 — jpg|jpeg|png|gif|webp|bmp|tiff|mp4|webm|mov|avi
        // UploadZone.tsx:165 — image/*,video/*
        panel.allowedContentTypes = [
            .png, .jpeg, .gif, .bmp, .tiff, .webP, .heic,     // Images
            .mpeg4Movie, .movie, .avi                           // Videos (.webm has no UTType)
        ]

        panel.begin { response in
            if response == .OK {
                Task {
                    await importService.importFiles(panel.urls, into: modelContext, spaceId: appState.activeSpaceId)
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
            // Stage 1 — height crushes inward
            withAnimation(CardCrush.heightCrush) {
                for id in ids { appState.deletingItemStages[id] = 1 }
            }
            Task { @MainActor in
                // Stage 2 — width collapses + fade out
                try? await Task.sleep(for: CardCrush.widthDelay)
                withAnimation(CardCrush.widthCrush) {
                    for id in ids { appState.deletingItemStages[id] = 2 }
                }

                // Crush complete — commit deletion
                try? await Task.sleep(for: CardCrush.completeDelay)
                commitDeletion(ids)
            }
        }
    }

    private func commitDeletion(_ ids: Set<String>) {
        // Guard: if undo already removed these from the stage dictionary, skip
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
            try? modelContext.save()
        }
        syncWatcher.endLocalChange()

        // Clean up animation state after SwiftUI finishes removing views.
        // If cleaned up immediately, deleteStage snaps to 0 and the crushed
        // item briefly flashes at full size during the removal transition.
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
        try? modelContext.save()
        syncWatcher.endLocalChange()
        appState.showToast("Restored \(batch.count) item\(batch.count == 1 ? "" : "s")")
    }

    private func createSpace() {
        syncWatcher.beginLocalChange()
        let space = Space(name: "New Space", order: spaces.count)
        modelContext.insert(space)
        try? modelContext.save()
        // Build sidecar array manually — @Query hasn't updated yet with the new space
        var allSpaceSidecars = spaces.map { s in
            SidecarSpace(id: s.id, name: s.name, order: s.order,
                         createdAt: s.createdAt, customPrompt: s.customPrompt,
                         useCustomPrompt: s.useCustomPrompt)
        }
        allSpaceSidecars.append(SidecarSpace(id: space.id, name: space.name, order: space.order,
                                              createdAt: space.createdAt, customPrompt: space.customPrompt,
                                              useCustomPrompt: space.useCustomPrompt))
        MetadataSidecarService.shared.writeSpaceSidecars(allSpaceSidecars)
        syncWatcher.endLocalChange()
        switchToSpace(space.id)
        pendingEditSpaceId = space.id
    }

    private func deleteSpace(_ id: String) {
        guard let space = spaces.first(where: { $0.id == id }) else { return }

        // 1. Capture plain data before any SwiftData mutation
        let remainingSidecars = spaces.filter { $0.id != id }.map { s in
            SidecarSpace(id: s.id, name: s.name, order: s.order,
                         createdAt: s.createdAt, customPrompt: s.customPrompt,
                         useCustomPrompt: s.useCustomPrompt)
        }

        // 2. Switch away before mutation
        if appState.activeSpaceId == id {
            appState.activeSpaceId = nil
        }

        // 3. Suppress sync, manually nullify relationships, delete, write sidecar
        syncWatcher.beginLocalChange()
        for item in space.items {
            item.space = nil
        }
        modelContext.delete(space)
        try? modelContext.save()
        MetadataSidecarService.shared.writeSpaceSidecars(remainingSidecars)
        syncWatcher.endLocalChange()
    }

    private func renameSpace(_ id: String, _ newName: String) {
        if let space = spaces.first(where: { $0.id == id }) {
            syncWatcher.beginLocalChange()
            space.name = newName
            try? modelContext.save()
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
        try? modelContext.save()
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
        try? modelContext.save()

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
        appState.activeSpaceId = nil
    }

    private func retryAnalysis(_ ids: Set<String>) {
        let items = allItems.filter { ids.contains($0.id) }
        for item in items {
            item.analysisError = nil
            item.analysisResult = nil
        }
        try? modelContext.save()
        for item in items {
            Task {
                await importService.analyzeItem(item, context: modelContext)
            }
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
