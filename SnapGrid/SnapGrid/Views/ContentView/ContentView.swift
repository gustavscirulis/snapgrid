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

    @State private var syncWatcher = SyncWatcher()
    @State private var isDragTargeted = false
    @State private var pendingEditSpaceId: String?
    @State private var showElectronImport = false
    @AppStorage("appTheme") private var themeSetting: String = AppTheme.system.rawValue

    private func itemsForSpace(_ spaceId: String?) -> [MediaItem] {
        var items = allItems

        if let spaceId {
            items = items.filter { $0.space?.id == spaceId }
        }

        if !appState.searchText.isEmpty {
            let query = appState.searchText.lowercased()
            items = items.filter { item in
                if let patterns = item.analysisResult?.patterns,
                   patterns.contains(where: { $0.name.lowercased().contains(query) }) {
                    return true
                }
                if let context = item.analysisResult?.imageContext.lowercased(), context.contains(query) {
                    return true
                }
                if let summary = item.analysisResult?.imageSummary.lowercased(), summary.contains(query) {
                    return true
                }
                if query == "video" && item.isVideo { return true }
                if query == "image" && !item.isVideo { return true }
                return false
            }
        }

        return items
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
                if allItems.isEmpty {
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

            // Detail overlay — hero animation from thumbnail to centered view
            if let detailId = appState.detailItem,
               let item = allItems.first(where: { $0.id == detailId }),
               let sourceFrame = appState.detailSourceFrame {
                HeroDetailOverlay(
                    item: item,
                    sourceFrame: sourceFrame,
                    onAnimationComplete: {
                        appState.detailItem = nil
                        appState.detailSourceFrame = nil
                    }
                )
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

            // Drag overlay
            if isDragTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.snapAccent, lineWidth: 3)
                    .background(Color.snapAccent.opacity(0.1))
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 540, minHeight: 400)
        .searchable(text: $appState.searchText, placement: .toolbar, prompt: "Search patterns, descriptions...")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Spacer()
            }
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $isDragTargeted) { providers in
            handleDrop(providers)
            return true
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
                // Search from the theme frame (contentView's superview) to reach
                // toolbar views — .searchable places NSSearchField in the toolbar,
                // which is outside contentView's hierarchy
                if let window = NSApp.keyWindow,
                   let rootView = window.contentView?.superview,
                   let searchField = findSearchField(in: rootView) {
                    window.makeFirstResponder(searchField)
                }
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
        .preferredColorScheme((AppTheme(rawValue: themeSetting) ?? .system).colorScheme)
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
                if items.isEmpty && spaceId != nil {
                    EmptyStateView(mode: .spaceLevel, isDragTargeted: isDragTargeted)
                } else if items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("No results found")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
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

            for provider in providers {
                // Try file URL first (local file drags from Finder)
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
                   let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier),
                   let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil),
                   url.isFileURL {
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

        syncWatcher.beginLocalChange()
        for item in items {
            try? MediaStorageService.shared.moveToTrash(filename: item.filename, id: item.id)
            modelContext.delete(item)
        }
        try? modelContext.save()
        syncWatcher.endLocalChange()
        appState.clearSelection()
        appState.showToast("Moved \(items.count) item\(items.count == 1 ? "" : "s") to trash")
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
        MetadataSidecarService.shared.writeSpaces(Array(spaces))
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

    private func retryAnalysis(_ item: MediaItem) {
        item.analysisError = nil
        item.analysisResult = nil
        try? modelContext.save()
        Task {
            await importService.analyzeItem(item, context: modelContext)
        }
    }

    private func findSearchField(in view: NSView?) -> NSSearchField? {
        guard let view else { return nil }
        if let searchField = view as? NSSearchField { return searchField }
        for subview in view.subviews {
            if let found = findSearchField(in: subview) { return found }
        }
        return nil
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
