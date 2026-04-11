import SwiftUI
import SwiftData

struct MainView: View {
    @EnvironmentObject var fileSystem: FileSystemManager
    @EnvironmentObject var keySyncService: KeySyncService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \MediaItem.createdAt, order: .reverse) private var allItems: [MediaItem]
    @Query(sort: \Space.order) private var spaces: [Space]
    @State private var appState = AppState()
    @State private var isLoading = true
    @State private var error: String?
    @State private var hasAttemptedRescan = false
    @State private var prefetchTask: Task<Void, Never>?
    @State private var syncService = SyncService()
    @State private var searchService = SearchIndexService()
    @State private var analysisCoordinator = AnalysisCoordinator()
    @State private var debounceTask: Task<Void, Never>?
    @State private var indexRebuildTask: Task<Void, Never>?
    @State private var showNewSpaceAlert = false
    @State private var newSpaceName = ""
    @State private var showRenameSpaceAlert = false
    @State private var renameSpaceName = ""
    @State private var renameSpaceId: String?
    @State private var gridItemRects: [String: CGRect] = [:]

    // MARK: - Filtering

    private var searchBaseItems: [MediaItem] {
        if let spaceId = appState.searchSpaceId {
            return allItems.filter { $0.belongs(to: spaceId) }
        }
        return Array(allItems)
    }

    private var searchResultItems: [MediaItem] {
        let scores = appState.searchScores
        let query = appState.searchText.lowercased().trimmingCharacters(in: .whitespaces)
        let base = searchBaseItems

        guard !query.isEmpty else { return [] }

        if query == "vid" { return base.filter { $0.isVideo } }
        if query == "img" { return base.filter { !$0.isVideo } }

        guard !scores.isEmpty else { return [] }

        return base
            .filter { scores[$0.id] != nil }
            .sorted { (scores[$0.id] ?? 0) > (scores[$1.id] ?? 0) }
    }

    private var searchContentItems: [MediaItem] {
        let query = appState.searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return searchBaseItems }
        return searchResultItems
    }

    private var detailOverlayItems: [MediaItem] {
        guard let host = appState.detailHost else { return [] }

        switch host {
        case .all, .search:
            return searchContentItems
        case .space(let spaceId):
            return allItems.filter { $0.belongs(to: spaceId) }
        }
    }

    private var detailOverlayTitle: String {
        guard let host = appState.detailHost else { return "SnapGrid" }

        switch host {
        case .all:
            return "All media"
        case .search:
            return "SnapGrid"
        case .space(let spaceId):
            return spaces.first(where: { $0.id == spaceId })?.name ?? "Space"
        }
    }

    // MARK: - Body

    var body: some View {
        @Bindable var appState = appState

        GeometryReader { geo in
            let gridWidth = geo.size.width - 24

            ZStack {
                tabContent(gridWidth: gridWidth)
                    .allowsHitTesting(!appState.showOverlay)

                if appState.showOverlay, appState.selectedIndex != nil, !detailOverlayItems.isEmpty {
                    MediaDetailModal(
                        items: detailOverlayItems,
                        title: detailOverlayTitle,
                        showOverlay: $appState.showOverlay,
                        selectedItemId: $appState.selectedItemId,
                        selectedIndex: $appState.selectedIndex,
                        sourceRect: appState.sourceRect,
                        thumbnailImage: $appState.thumbnailImage,
                        gridItemRects: $gridItemRects,
                        onSearchPattern: handleSearchPattern,
                        onDelete: handleItemDeleted,
                        onOverlayClosed: handleOverlayClosed
                    )
                    .zIndex(1)
                }
            }
            .onPreferenceChange(GridItemRectsPreferenceKey.self) { gridItemRects = $0 }
        }
        .task {
            await loadContent()
        }
        .onChange(of: appState.searchText) { _, newValue in
            debounceTask?.cancel()
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                appState.searchScores = [:]
            } else {
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
            indexRebuildTask?.cancel()
            indexRebuildTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                searchService.buildIndex(items: allItems)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                if let rootURL = fileSystem.rootURL {
                    ShareImportService.importPendingItems(to: rootURL)
                }
                Task { await loadContent() }
            }
        }
        .onChange(of: appState.selectedTab) { _, newTab in
            if newTab == .search {
                if appState.pendingGlobalSearch {
                    appState.searchSpaceId = nil
                    appState.pendingGlobalSearch = false
                } else {
                    appState.searchSpaceId = appState.activeSpaceId
                }
            } else {
                appState.searchSpaceId = nil
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
        .alert("New Space", isPresented: $showNewSpaceAlert) {
            TextField("Space name", text: $newSpaceName)
            Button("Create") {
                let name = newSpaceName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                commitNewSpace(name: name)
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Space", isPresented: $showRenameSpaceAlert) {
            TextField("Space name", text: $renameSpaceName)
            Button("Rename") {
                let name = renameSpaceName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, let id = renameSpaceId else { return }
                renameSpace(id, name)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func tabContent(gridWidth: CGFloat) -> some View {
        if #available(iOS 26, *) {
            TabView(selection: $appState.selectedTab) {
                Tab("All", systemImage: "square.grid.2x2", value: AppTab.all) {
                    allItemsContent(gridWidth: gridWidth)
                }
                Tab("Spaces", systemImage: "folder", value: AppTab.spaces) {
                    spacesContent(gridWidth: gridWidth)
                }
                Tab(value: AppTab.search, role: .search) {
                    searchContent(gridWidth: gridWidth)
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            .tabViewSearchActivation(.searchTabSelection)
            .tint(.white)
        } else {
            TabView(selection: $appState.selectedTab) {
                allItemsContent(gridWidth: gridWidth)
                    .tabItem { Label("All", systemImage: "square.grid.2x2") }
                    .tag(AppTab.all)
                spacesContent(gridWidth: gridWidth)
                    .tabItem { Label("Spaces", systemImage: "folder") }
                    .tag(AppTab.spaces)
            }
            .tint(.white)
        }
    }

    @ViewBuilder
    private func allItemsContent(gridWidth: CGFloat) -> some View {
        @Bindable var appState = appState

        AllItemsTab(
            items: searchContentItems,
            spaces: spaces,
            gridWidth: gridWidth,
            isLoading: isLoading,
            error: error,
            selectedItemId: appState.selectedItemId,
            showOverlay: appState.showOverlay,
            searchText: $appState.searchText,
            onItemSelected: { item, rect, thumbnail in
                handleItemSelected(item, rect, thumbnail, host: .all)
            },
            onRetryAnalysis: handleRetryAnalysis,
            onShareItem: handleShareItem,
            onDeleteItem: { item in appState.itemToDelete = item },
            onAssignToSpace: handleAssignToSpace,
            onLoadContent: loadContent,
            addImagesMenu: addImagesMenu
        )
    }

    @ViewBuilder
    private func spacesContent(gridWidth: CGFloat) -> some View {
        @Bindable var appState = appState

        SpacesTab(
            spaces: spaces,
            allItems: allItems,
            selectedItemId: appState.selectedItemId,
            showOverlay: appState.showOverlay,
            setActiveSpaceId: { appState.activeSpaceId = $0 },
            onItemSelected: handleItemSelected,
            onRetryAnalysis: handleRetryAnalysis,
            onShareItem: handleShareItem,
            onDeleteItem: { item in appState.itemToDelete = item },
            onAssignToSpace: handleAssignToSpace,
            onLoadContent: loadContent,
            onCreateSpace: createSpace,
            onRenameSpace: beginRenameSpace,
            onDeleteSpace: deleteSpace,
            addImagesMenu: addImagesMenu
        )
    }

    @ViewBuilder
    private func searchContent(gridWidth: CGFloat) -> some View {
        @Bindable var appState = appState
        let items = searchContentItems
        let scopedSpaceName = appState.searchSpaceId.flatMap { id in spaces.first { $0.id == id }?.name }

        NavigationStack {
            ZStack {
                Color.snapDarkBackground
                    .ignoresSafeArea()

                if items.isEmpty && !appState.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    SearchEmptyStateView()
                } else if items.isEmpty {
                    EmptyStateView()
                } else {
                    ScrollView {
                        MasonryGrid(
                            items: items,
                            spaces: spaces,
                            availableWidth: gridWidth,
                            selectedItemId: appState.showOverlay ? appState.selectedItemId : nil,
                            onItemSelected: { item, rect, thumbnail in
                                handleItemSelected(item, rect, thumbnail, host: .search)
                            },
                            onRetryAnalysis: handleRetryAnalysis,
                            onShareItem: handleShareItem,
                            onDeleteItem: { item in appState.itemToDelete = item },
                            onAssignToSpace: handleAssignToSpace
                        )
                        .padding(.horizontal, 12)
                        .padding(.bottom, 70)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .navigationTitle(scopedSpaceName ?? "SnapGrid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .searchable(
                text: $appState.searchText,
                prompt: scopedSpaceName.map { "Search in \($0)..." } ?? "Search patterns, context..."
            )
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

    private func handleItemSelected(_ item: MediaItem, _ rect: CGRect, _ thumb: UIImage?, host: DetailHost) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        appState.detailHost = host
        let visibleItems = detailOverlayItems
        appState.selectedIndex = visibleItems.firstIndex(where: { $0.id == item.id }) ?? 0
        appState.selectedItemId = item.id
        appState.sourceRect = rect
        appState.thumbnailImage = thumb
        appState.showOverlay = true
    }

    private func handleOverlayClosed() {
        appState.detailHost = nil
        appState.applyPendingSearchIfNeeded(prefersDedicatedSearchTab: supportsDedicatedSearchTab)
    }

    private func handleSearchPattern(_ pattern: String) {
        appState.queuePatternSearch(pattern)
    }

    private var supportsDedicatedSearchTab: Bool {
        if #available(iOS 26, *) {
            return true
        }
        return false
    }

    // MARK: - Space Creation

    private func createSpace() {
        newSpaceName = ""
        showNewSpaceAlert = true
    }

    private func commitNewSpace(name: String) {
        let space = Space(name: name, order: spaces.count)
        modelContext.insert(space)
        modelContext.saveOrLog()

        if let rootURL = fileSystem.rootURL {
            let allSpaces = (try? modelContext.fetch(FetchDescriptor<Space>(sortBy: [SortDescriptor(\.order)]))) ?? []
            SidecarWriteService.writeSpaces(allSpaces, rootURL: rootURL)
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func beginRenameSpace(_ id: String) {
        guard let space = spaces.first(where: { $0.id == id }) else { return }
        renameSpaceName = space.name
        renameSpaceId = id
        showRenameSpaceAlert = true
    }

    private func renameSpace(_ id: String, _ newName: String) {
        guard let space = spaces.first(where: { $0.id == id }) else { return }
        space.name = newName
        modelContext.saveOrLog()

        if let rootURL = fileSystem.rootURL {
            let allSpaces = (try? modelContext.fetch(FetchDescriptor<Space>(sortBy: [SortDescriptor(\.order)]))) ?? []
            SidecarWriteService.writeSpaces(allSpaces, rootURL: rootURL)
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func deleteSpace(_ id: String) {
        guard let space = spaces.first(where: { $0.id == id }) else { return }

        if appState.activeSpaceId == id {
            appState.activeSpaceId = nil
        }

        let itemsToUpdate = space.items
        for item in itemsToUpdate {
            item.removeSpace(id: id)
        }
        modelContext.delete(space)
        modelContext.saveOrLog()

        if let rootURL = fileSystem.rootURL {
            let allSpaces = (try? modelContext.fetch(FetchDescriptor<Space>(sortBy: [SortDescriptor(\.order)]))) ?? []
            SidecarWriteService.writeSpaces(allSpaces, rootURL: rootURL)
            for item in itemsToUpdate {
                SidecarWriteService.writeSpaceMembership(for: item, rootURL: rootURL)
            }
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Space Assignment

    private func handleAssignToSpace(itemId: String, spaceId: String?) {
        guard let item = allItems.first(where: { $0.id == itemId }) else { return }
        var shouldReanalyze = false

        if let spaceId {
            guard let space = spaces.first(where: { $0.id == spaceId }) else { return }
            let added = item.toggleSpace(space)
            shouldReanalyze = added && space.useCustomPrompt && space.customPrompt != nil
        } else {
            guard item.clearSpaces() else { return }
        }

        modelContext.saveOrLog()

        if let rootURL = fileSystem.rootURL {
            SidecarWriteService.writeSpaceMembership(for: item, rootURL: rootURL)
        }

        if shouldReanalyze {
            analysisCoordinator.analyzeItems([item], allItems: allItems)
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

        if isInitialLoad {
            MediaDeleteService.emptyOldTrash(rootURL: rootURL)
        }

        let skipped = await syncService.sync(rootURL: rootURL, context: modelContext)
        isLoading = false

        searchService.buildIndex(items: allItems)

        prefetchTask?.cancel()
        let screenWidth = UIScreen.main.bounds.width
        let columnWidth = (screenWidth - 24 - 8) / 2
        prefetchTask = ThumbnailCache.shared.prefetchThumbnails(for: allItems, targetPixelWidth: columnWidth * 2)

        analysisCoordinator.configure(
            keySyncService: keySyncService,
            fileSystem: fileSystem,
            modelContext: modelContext,
            searchService: searchService
        )

        analysisCoordinator.analyzeUnanalyzed(allItems: allItems)

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
        analysisCoordinator.analyzeItems([item], allItems: allItems)
    }
}
