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

struct MainView: View {
    @EnvironmentObject var fileSystem: FileSystemManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \MediaItem.createdAt, order: .reverse) private var allItems: [MediaItem]
    @Query(sort: \Space.order) private var spaces: [Space]
    @State private var selectedIndex: Int?
    @State private var selectedItemId: String?
    @State private var sourceRect: CGRect = .zero
    @State private var thumbnailImage: UIImage?
    @State private var showOverlay = false
    @State private var activeSpaceId: String? = nil
    @State private var searchText = ""
    @State private var gridItemRects: [String: CGRect] = [:]
    @State private var isLoading = true
    @State private var error: String?
    @State private var hasAttemptedRescan = false
    @State private var tabScrollProgress: CGFloat = 0
    @State private var prefetchTask: Task<Void, Never>?
    @State private var syncService = SyncService()
    @State private var searchService = SearchIndexService()
    @State private var debounceTask: Task<Void, Never>?
    @State private var searchScores: [String: Double] = [:]
    @State private var isSearchActive = false
    @State private var showPhotosPicker = false
    @State private var showFilesPicker = false
    @State private var isImporting = false

    // MARK: - Index ↔ activeSpaceId bridging

    private var activeIndex: Int {
        guard let id = activeSpaceId else { return 0 }
        return (spaces.firstIndex { $0.id == id } ?? -1) + 1
    }

    private var activeIndexBinding: Binding<Int> {
        Binding(
            get: { activeIndex },
            set: { newIndex in
                withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                    if newIndex == 0 {
                        activeSpaceId = nil
                    } else if newIndex > 0 && newIndex <= spaces.count {
                        activeSpaceId = spaces[newIndex - 1].id
                    }
                }
            }
        )
    }

    // MARK: - Filtering

    private func itemsForSpace(_ spaceId: String?) -> [MediaItem] {
        var items: [MediaItem]
        if let spaceId {
            items = allItems.filter { $0.space?.id == spaceId }
        } else {
            items = Array(allItems)
        }

        guard isSearchActive else { return items }

        let scores = searchScores
        guard !scores.isEmpty else {
            let query = searchText.lowercased().trimmingCharacters(in: .whitespaces)
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
        itemsForSpace(activeSpaceId)
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
                        if items.isEmpty && isSearchActive {
                            SearchEmptyStateView()
                        } else {
                            ScrollView {
                                MasonryGrid(
                                    items: items,
                                    availableWidth: gridWidth,
                                    selectedItemId: showOverlay ? selectedItemId : nil,
                                    onItemSelected: handleItemSelected
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
                                activeSpaceId: $activeSpaceId,
                                scrollProgress: tabScrollProgress
                            )

                            TabView(selection: activeIndexBinding) {
                                let allItems = itemsForSpace(nil)
                                if allItems.isEmpty && isSearchActive {
                                    SearchEmptyStateView()
                                        .tag(0)
                                        .background(PageOffsetReporter(pageIndex: 0))
                                } else {
                                    ScrollView {
                                        MasonryGrid(
                                            items: allItems,
                                            availableWidth: gridWidth,
                                            selectedItemId: showOverlay ? selectedItemId : nil,
                                            onItemSelected: handleItemSelected
                                        )
                                        .padding(.horizontal, 12)
                                        .padding(.top, 12)
                                        .padding(.bottom, 70)
                                    }
                                    .refreshable { await loadContent() }
                                    .tag(0)
                                    .background(PageOffsetReporter(pageIndex: 0))
                                }

                                ForEach(Array(spaces.enumerated()), id: \.element.id) { index, space in
                                    let spaceItems = itemsForSpace(space.id)
                                    if spaceItems.isEmpty && isSearchActive {
                                        SearchEmptyStateView()
                                            .tag(index + 1)
                                            .background(PageOffsetReporter(pageIndex: index + 1))
                                    } else {
                                        ScrollView {
                                            MasonryGrid(
                                                items: spaceItems,
                                                availableWidth: gridWidth,
                                                selectedItemId: showOverlay ? selectedItemId : nil,
                                                onItemSelected: handleItemSelected
                                            )
                                            .padding(.horizontal, 12)
                                            .padding(.top, 12)
                                            .padding(.bottom, 70)
                                        }
                                        .refreshable { await loadContent() }
                                        .tag(index + 1)
                                        .background(PageOffsetReporter(pageIndex: index + 1))
                                    }
                                }
                            }
                            .tabViewStyle(.page(indexDisplayMode: .never))
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
                            addImagesMenu
                        }
                    } else {
                        ToolbarItem(placement: .topBarTrailing) {
                            addImagesMenu
                        }
                    }
                }
                .toolbarColorScheme(.dark, for: .navigationBar)
                .searchable(text: $searchText, prompt: "Search patterns, context...")
                .onPreferenceChange(GridItemRectsPreferenceKey.self) { rects in
                    gridItemRects = rects
                }
            }
            .overlay {
                if showOverlay, let startIndex = selectedIndex {
                    FullScreenImageOverlay(
                        items: currentVisibleItems,
                        startIndex: startIndex,
                        sourceRect: sourceRect,
                        screenSize: geo.size,
                        thumbnailImage: thumbnailImage,
                        gridItemRects: gridItemRects,
                        onDismissing: { currentItemId in
                            selectedItemId = currentItemId
                        },
                        onClose: {
                            var t = Transaction()
                            t.disablesAnimations = true
                            withTransaction(t) {
                                showOverlay = false
                                selectedIndex = nil
                                selectedItemId = nil
                                thumbnailImage = nil
                            }
                        }
                    )
                }
            }
        }
        .task {
            await loadContent()
        }
        .onChange(of: searchText) { _, newValue in
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
                    if lowered == "vid" || lowered == "img" {
                        searchScores = [:]
                        return
                    }

                    let results = searchService.search(query: trimmed)
                    guard !Task.isCancelled else { return }
                    searchScores = Dictionary(uniqueKeysWithValues: results.map { ($0.itemId, $0.score) })
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
        .sheet(isPresented: $showPhotosPicker) {
            PhotosPickerWrapper { images in
                handlePickedImages(images)
            }
        }
        .sheet(isPresented: $showFilesPicker) {
            DocumentPickerWrapper { images in
                handlePickedImages(images)
            }
        }
    }

    // MARK: - Add Images Menu

    private var addImagesMenu: some View {
        Menu {
            Button {
                showPhotosPicker = true
            } label: {
                Label("Choose from Photos", systemImage: "photo.on.rectangle")
            }
            Button {
                showFilesPicker = true
            } label: {
                Label("Choose from Files", systemImage: "folder")
            }
        } label: {
            Label("Add", systemImage: "plus")
        }
        .disabled(isImporting || fileSystem.rootURL == nil)
    }

    // MARK: - Item Selection

    private func handleItemSelected(_ item: MediaItem, _ rect: CGRect, _ thumb: UIImage?) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let visibleItems = currentVisibleItems
        selectedIndex = visibleItems.firstIndex(where: { $0.id == item.id }) ?? 0
        selectedItemId = item.id
        sourceRect = rect
        thumbnailImage = thumb
        showOverlay = true
    }

    // MARK: - Image Import

    private func handlePickedImages(_ images: [UIImage]) {
        guard !images.isEmpty, let rootURL = fileSystem.rootURL else { return }

        isImporting = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task {
            let result = await ImageImportService.importImages(images, to: rootURL)
            isImporting = false

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
}
