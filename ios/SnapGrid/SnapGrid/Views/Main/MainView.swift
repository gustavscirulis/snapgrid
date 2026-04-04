import SwiftUI
import SwiftData

// MARK: - Preference key for continuous TabView scroll tracking

private struct PageOffsetData: Equatable {
    let pageIndex: Int
    let minX: CGFloat
}

private struct PageOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: PageOffsetData? = nil
    static func reduce(value: inout PageOffsetData?, nextValue: () -> PageOffsetData?) {
        value = nextValue() ?? value
    }
}

private struct PageOffsetReporter: View {
    let pageIndex: Int

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .preference(
                    key: PageOffsetPreferenceKey.self,
                    value: PageOffsetData(
                        pageIndex: pageIndex,
                        minX: geo.frame(in: .named("pagerContainer")).minX
                    )
                )
        }
    }
}

private struct CloseSearchButton: View {
    @Environment(\.dismissSearch) private var dismissSearch
    @Binding var searchText: String

    var body: some View {
        Button {
            searchText = ""
            dismissSearch()
        } label: {
            Label("Close Search", systemImage: "xmark")
        }
    }
}

struct MainView: View {
    @EnvironmentObject var fileSystem: FileSystemManager
    @EnvironmentObject var keySyncService: KeySyncService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \MediaItem.createdAt, order: .reverse) private var allItems: [MediaItem]
    @Query(sort: \Space.order) private var spaces: [Space]
    @State private var appState = AppState()
    @State private var gridItemRects: [String: CGRect] = [:]
    @State private var isLoading = true
    @State private var error: String?
    @State private var hasAttemptedRescan = false
    @State private var tabScrollProgress: CGFloat = 0
    @State private var prefetchTask: Task<Void, Never>?
    @State private var syncService = SyncService()
    @State private var searchService = SearchIndexService()
    @State private var analysisCoordinator = AnalysisCoordinator()
    @State private var debounceTask: Task<Void, Never>?

    // MARK: - Index ↔ activeSpaceId bridging

    private var activeIndex: Int {
        guard let id = appState.activeSpaceId else { return 0 }
        return (spaces.firstIndex { $0.id == id } ?? -1) + 1
    }

    // MARK: - Filtering

    private func itemsForSpace(_ spaceId: String?) -> [MediaItem] {
        var items: [MediaItem]
        if let spaceId {
            items = allItems.filter { $0.space?.id == spaceId }
        } else {
            items = Array(allItems)
        }

        guard appState.isSearchActive else { return items }

        let scores = appState.searchScores
        guard !scores.isEmpty else {
            let query = appState.searchText.lowercased().trimmingCharacters(in: .whitespaces)
            if query == "vid" { return items.filter { $0.isVideo } }
            if query == "img" { return items.filter { !$0.isVideo } }
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

    private var currentVisibleItems: [MediaItem] {
        itemsForSpace(appState.activeSpaceId)
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let gridWidth = geo.size.width - 24

            NavigationStack {
                ZStack {
                    Color.snapDarkBackground
                        .ignoresSafeArea()

                    if isLoading {
                        ProgressView()
                            .tint(.white.opacity(0.6))
                    } else if let error {
                        ErrorStateView(message: error) {
                            await loadContent()
                        }
                    } else if allItems.isEmpty {
                        EmptyStateView()
                    } else if spaces.isEmpty {
                        let items = itemsForSpace(nil)
                        if items.isEmpty && appState.isSearchActive {
                            SearchEmptyStateView()
                        } else {
                            ScrollView {
                                MasonryGrid(
                                    items: items,
                                    availableWidth: gridWidth,
                                    selectedItemId: appState.showOverlay ? appState.selectedItemId : nil,
                                    onItemSelected: handleItemSelected,
                                    onRetryAnalysis: handleRetryAnalysis,
                                    onShareItem: handleShareItem,
                                    onDeleteItem: { item in appState.itemToDelete = item }
                                )
                                .padding(.horizontal, 12)
                                .padding(.bottom, 70)
                            }
                            .refreshable {
                                hasAttemptedRescan = false
                                await loadContent()
                            }
                        }
                    } else {
                        VStack(spacing: 0) {
                            SpaceTabBar(
                                spaces: spaces,
                                activeSpaceId: $appState.activeSpaceId,
                                scrollProgress: tabScrollProgress,
                                onAssignToSpace: handleAssignToSpace
                            )

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 0) {
                                    let allPageItems = itemsForSpace(nil)
                                    if allPageItems.isEmpty && appState.isSearchActive {
                                        SearchEmptyStateView()
                                            .containerRelativeFrame(.horizontal)
                                            .id(0)
                                            .background(PageOffsetReporter(pageIndex: 0))
                                    } else {
                                        ScrollView {
                                            MasonryGrid(
                                                items: allPageItems,
                                                availableWidth: gridWidth,
                                                selectedItemId: appState.showOverlay ? appState.selectedItemId : nil,
                                                onItemSelected: handleItemSelected,
                                                onRetryAnalysis: handleRetryAnalysis,
                                                onShareItem: handleShareItem,
                                                onDeleteItem: { item in appState.itemToDelete = item }
                                            )
                                            .padding(.horizontal, 12)
                                            .padding(.top, 12)
                                            .padding(.bottom, 70)
                                        }
                                        .refreshable { await loadContent() }
                                        .containerRelativeFrame(.horizontal)
                                        .id(0)
                                        .background(PageOffsetReporter(pageIndex: 0))
                                    }

                                    ForEach(Array(spaces.enumerated()), id: \.element.id) { index, space in
                                        let spaceItems = itemsForSpace(space.id)
                                        if spaceItems.isEmpty && appState.isSearchActive {
                                            SearchEmptyStateView()
                                                .containerRelativeFrame(.horizontal)
                                                .id(index + 1)
                                                .background(PageOffsetReporter(pageIndex: index + 1))
                                        } else {
                                            ScrollView {
                                                MasonryGrid(
                                                    items: spaceItems,
                                                    availableWidth: gridWidth,
                                                    selectedItemId: appState.showOverlay ? appState.selectedItemId : nil,
                                                    onItemSelected: handleItemSelected,
                                                    onRetryAnalysis: handleRetryAnalysis,
                                                    onShareItem: handleShareItem,
                                                    onRemoveFromSpace: handleRemoveFromSpace,
                                                    onDeleteItem: { item in appState.itemToDelete = item }
                                                )
                                                .padding(.horizontal, 12)
                                                .padding(.top, 12)
                                                .padding(.bottom, 70)
                                            }
                                            .refreshable { await loadContent() }
                                            .containerRelativeFrame(.horizontal)
                                            .id(index + 1)
                                            .background(PageOffsetReporter(pageIndex: index + 1))
                                        }
                                    }
                                }
                                .scrollTargetLayout()
                            }
                            .scrollTargetBehavior(.paging)
                            .scrollPosition(id: $appState.currentPage)
                            .coordinateSpace(name: "pagerContainer")
                            .onPreferenceChange(PageOffsetPreferenceKey.self) { data in
                                guard let data = data else { return }
                                let containerWidth = geo.size.width
                                guard containerWidth > 0 else { return }
                                let progress = CGFloat(data.pageIndex) - data.minX / containerWidth
                                tabScrollProgress = min(max(progress, 0), CGFloat(spaces.count))
                            }
                        }
                    }
                }
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("SnapGrid")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if #available(iOS 26.0, *) {
                        DefaultToolbarItem(kind: .search, placement: .bottomBar)
                        ToolbarSpacer(.flexible, placement: .bottomBar)
                        ToolbarItem(placement: .bottomBar) {
                            if appState.isSearchActive {
                                CloseSearchButton(searchText: $appState.searchText)
                            } else {
                                addImagesMenu
                            }
                        }
                    } else {
                        ToolbarItem(placement: .topBarTrailing) {
                            if appState.isSearchActive {
                                CloseSearchButton(searchText: $appState.searchText)
                            } else {
                                addImagesMenu
                            }
                        }
                    }
                }
                .toolbarColorScheme(.dark, for: .navigationBar)
                .searchable(text: $appState.searchText, prompt: "Search patterns, context...")
                .onPreferenceChange(GridItemRectsPreferenceKey.self) { rects in
                    gridItemRects = rects
                }
            }
            .overlay {
                if appState.showOverlay, let startIndex = appState.selectedIndex {
                    FullScreenImageOverlay(
                        items: currentVisibleItems,
                        startIndex: startIndex,
                        sourceRect: appState.sourceRect,
                        screenSize: geo.size,
                        thumbnailImage: appState.thumbnailImage,
                        gridItemRects: $gridItemRects,
                        onDismissing: { currentItemId in
                            appState.selectedItemId = currentItemId
                        },
                        onClose: {
                            var t = Transaction()
                            t.disablesAnimations = true
                            withTransaction(t) {
                                appState.showOverlay = false
                                appState.selectedIndex = nil
                                appState.selectedItemId = nil
                                appState.thumbnailImage = nil
                            }
                        },
                        onSearchPattern: { pattern in
                            appState.searchText = pattern
                        },
                        onDelete: handleItemDeleted
                    )
                }
            }
        }
        .task {
            await loadContent()
        }
        .onChange(of: appState.searchText) { _, newValue in
            debounceTask?.cancel()
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                appState.isSearchActive = false
                appState.searchScores = [:]
            } else {
                appState.isSearchActive = true
                debounceTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled else { return }

                    let lowered = trimmed.lowercased()
                    if lowered == "vid" || lowered == "img" {
                        appState.searchScores = [:]
                        return
                    }

                    let results = searchService.search(query: trimmed)
                    guard !Task.isCancelled else { return }
                    appState.searchScores = Dictionary(uniqueKeysWithValues: results.map { ($0.itemId, $0.score) })
                }
            }
        }
        .onChange(of: allItems.count) { _, _ in
            searchService.buildIndex(items: allItems)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                if let rootURL = fileSystem.rootURL {
                    ShareImportService.importPendingItems(to: rootURL)
                }
                Task { await loadContent() }
            }
        }
        .onChange(of: appState.currentPage) { _, newPage in
            let page = newPage ?? 0
            if page == 0 {
                appState.activeSpaceId = nil
            } else if page > 0 && page <= spaces.count {
                appState.activeSpaceId = spaces[page - 1].id
            }
        }
        .onChange(of: appState.activeSpaceId) { _, _ in
            let target = activeIndex
            if appState.currentPage != target {
                withAnimation(SnapSpring.resolvedStandard) {
                    appState.currentPage = target
                }
            }
        }
        .sheet(isPresented: $appState.showPhotosPicker) {
            PhotosPickerWrapper { images in
                handlePickedImages(images)
            }
        }
        .sheet(isPresented: $appState.showFilesPicker) {
            DocumentPickerWrapper { images in
                handlePickedImages(images)
            }
        }
        .sheet(isPresented: Binding(
            get: { appState.shareItem != nil },
            set: { if !$0 { appState.shareItem = nil } }
        )) {
            if let url = appState.shareItem {
                ActivityView(activityItems: [url])
                    .presentationDetents([.medium, .large])
            }
        }
        .confirmationDialog(
            "Delete this item?",
            isPresented: Binding(
                get: { appState.itemToDelete != nil },
                set: { if !$0 { appState.itemToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let item = appState.itemToDelete {
                    handleItemDeleted(item)
                    appState.itemToDelete = nil
                }
            }
        }
    }

    // MARK: - Add Images Menu

    private var addImagesMenu: some View {
        Menu {
            Button {
                appState.showPhotosPicker = true
            } label: {
                Label("Choose from Photos", systemImage: "photo.on.rectangle")
            }
            Button {
                appState.showFilesPicker = true
            } label: {
                Label("Choose from Files", systemImage: "folder")
            }
        } label: {
            Label("Add", systemImage: "plus")
        }
        .disabled(appState.isImporting || fileSystem.rootURL == nil)
    }

    // MARK: - Item Selection

    private func handleItemSelected(_ item: MediaItem, _ rect: CGRect, _ thumb: UIImage?) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let visibleItems = currentVisibleItems
        appState.selectedIndex = visibleItems.firstIndex(where: { $0.id == item.id }) ?? 0
        appState.selectedItemId = item.id
        appState.sourceRect = rect
        appState.thumbnailImage = thumb
        appState.showOverlay = true
    }

    // MARK: - Space Assignment (Drag & Drop)

    private func handleAssignToSpace(itemId: String, spaceId: String?) {
        guard let item = allItems.first(where: { $0.id == itemId }) else { return }

        // Skip if already in the target space
        let currentSpaceId = item.space?.id
        if currentSpaceId == spaceId { return }

        // Update SwiftData
        let space: Space? = spaceId.flatMap { sid in
            spaces.first(where: { $0.id == sid })
        }
        item.space = space
        modelContext.saveOrLog()

        // Persist to sidecar JSON for iCloud sync
        if let rootURL = fileSystem.rootURL {
            SidecarWriteService.writeSpaceId(for: item, rootURL: rootURL)
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: - Item Deletion

    private func handleItemDeleted(_ item: MediaItem) {
        if let rootURL = fileSystem.rootURL {
            try? MediaDeleteService.moveToTrash(
                filename: item.filename, id: item.id, rootURL: rootURL
            )
        }
        modelContext.delete(item)
        modelContext.saveOrLog()
    }

    // MARK: - Item Sharing

    private func handleShareItem(_ item: MediaItem) {
        guard let url = item.mediaURL else { return }
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: tempURL)
        do {
            try FileManager.default.copyItem(at: url, to: tempURL)
            appState.shareItem = tempURL
        } catch {
            appState.shareItem = url
        }
    }

    // MARK: - Remove from Space

    private func handleRemoveFromSpace(_ item: MediaItem) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        item.space = nil
        modelContext.saveOrLog()

        if let rootURL = fileSystem.rootURL {
            SidecarWriteService.writeSpaceId(for: item, rootURL: rootURL)
        }
    }

    // MARK: - Image Import

    private func handlePickedImages(_ images: [UIImage]) {
        guard !images.isEmpty, let rootURL = fileSystem.rootURL else { return }

        appState.isImporting = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task {
            let result = await ImageImportService.importImages(images, to: rootURL, spaceId: appState.activeSpaceId)
            appState.isImporting = false

            if result.successCount > 0 {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                await loadContent()
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    // MARK: - Data Loading

    private func loadContent() async {
        let isInitialLoad = isLoading
        error = nil

        // Reset any isAnalyzing flags stuck from a previous crash/kill
        let stuckDescriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.isAnalyzing == true })
        if let stuck = try? modelContext.fetch(stuckDescriptor), !stuck.isEmpty {
            for item in stuck { item.isAnalyzing = false }
            modelContext.saveOrLog()
            print("[Cleanup] Reset \(stuck.count) stuck isAnalyzing flags")
        }

        guard let rootURL = fileSystem.rootURL else {
            self.error = "No access to SnapGrid folder"
            self.isLoading = false
            return
        }

        let skipped = await syncService.sync(rootURL: rootURL, context: modelContext)
        isLoading = false

        // Build search index
        searchService.buildIndex(items: allItems)

        // Prefetch thumbnails
        prefetchTask?.cancel()
        let screenWidth = UIScreen.main.bounds.width
        let columnWidth = (screenWidth - 24 - 8) / 2
        prefetchTask = ThumbnailCache.shared.prefetchThumbnails(for: allItems, targetPixelWidth: columnWidth * 2)

        // Analyze unanalyzed items if API keys are available
        analysisCoordinator.analyzeUnanalyzed(
            keySyncService: keySyncService,
            fileSystem: fileSystem,
            modelContext: modelContext,
            searchService: searchService,
            allItems: allItems
        )

        // Re-scan if some iCloud files were still downloading
        if skipped > 0 && !hasAttemptedRescan {
            hasAttemptedRescan = true
            print("[MainView] \(skipped) files pending iCloud download, will re-scan in 15s")
            Task {
                try? await Task.sleep(for: .seconds(15))
                hasAttemptedRescan = false
                await loadContent()
            }
        }
    }

    private func handleRetryAnalysis(_ item: MediaItem) {
        item.analysisError = nil
        item.analysisResult = nil
        modelContext.saveOrLog()
        analysisCoordinator.analyzeItems(
            [item],
            keySyncService: keySyncService,
            fileSystem: fileSystem,
            modelContext: modelContext,
            searchService: searchService,
            allItems: allItems
        )
    }
}
