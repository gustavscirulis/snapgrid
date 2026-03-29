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
    @State private var analysisTask: Task<Void, Never>?
    @State private var syncService = SyncService()
    @State private var searchService = SearchIndexService()
    @State private var debounceTask: Task<Void, Never>?
    @State private var searchScores: [String: Double] = [:]
    @State private var isSearchActive = false
    @State private var currentPage: Int? = 0
    @State private var showPhotosPicker = false
    @State private var showFilesPicker = false
    @State private var isImporting = false

    // MARK: - Index ↔ activeSpaceId bridging

    private var activeIndex: Int {
        guard let id = activeSpaceId else { return 0 }
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
                                    onItemSelected: handleItemSelected,
                                    onRetryAnalysis: handleRetryAnalysis
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

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 0) {
                                    let allPageItems = itemsForSpace(nil)
                                    if allPageItems.isEmpty && isSearchActive {
                                        SearchEmptyStateView()
                                            .containerRelativeFrame(.horizontal)
                                            .id(0)
                                            .background(PageOffsetReporter(pageIndex: 0))
                                    } else {
                                        ScrollView {
                                            MasonryGrid(
                                                items: allPageItems,
                                                availableWidth: gridWidth,
                                                selectedItemId: showOverlay ? selectedItemId : nil,
                                                onItemSelected: handleItemSelected
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
                                        if spaceItems.isEmpty && isSearchActive {
                                            SearchEmptyStateView()
                                                .containerRelativeFrame(.horizontal)
                                                .id(index + 1)
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
                                            .containerRelativeFrame(.horizontal)
                                            .id(index + 1)
                                            .background(PageOffsetReporter(pageIndex: index + 1))
                                        }
                                    }
                                }
                                .scrollTargetLayout()
                            }
                            .scrollTargetBehavior(.paging)
                            .scrollPosition(id: $currentPage)
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
                            if isSearchActive {
                                CloseSearchButton(searchText: $searchText)
                            } else {
                                addImagesMenu
                            }
                        }
                    } else {
                        ToolbarItem(placement: .topBarTrailing) {
                            if isSearchActive {
                                CloseSearchButton(searchText: $searchText)
                            } else {
                                addImagesMenu
                            }
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
                        gridItemRects: $gridItemRects,
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
                        },
                        onSearchPattern: { pattern in
                            searchText = pattern
                        },
                        onDelete: handleItemDeleted
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
        .onChange(of: currentPage) { _, newPage in
            let page = newPage ?? 0
            if page == 0 {
                activeSpaceId = nil
            } else if page > 0 && page <= spaces.count {
                activeSpaceId = spaces[page - 1].id
            }
        }
        .onChange(of: activeSpaceId) { _, _ in
            let target = activeIndex
            if currentPage != target {
                withAnimation(SnapSpring.standard) {
                    currentPage = target
                }
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

    // MARK: - Item Deletion

    private func handleItemDeleted(_ item: MediaItem) {
        if let rootURL = fileSystem.rootURL {
            try? MediaDeleteService.moveToTrash(
                filename: item.filename, id: item.id, rootURL: rootURL
            )
        }
        modelContext.delete(item)
        try? modelContext.save()
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

        // Analyze unanalyzed items if API keys are available
        analyzeUnanalyzedItems()

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
        analyzeUnanalyzedItems()
    }

    // MARK: - AI Analysis

    private func analyzeUnanalyzedItems() {
        guard keySyncService.isUnlocked else {
            print("[Analysis] Skipped — keySyncService not unlocked")
            return
        }
        guard let providerStr = keySyncService.activeProvider,
              let provider = AIProvider(rawValue: providerStr) else {
            print("[Analysis] Skipped — no active provider")
            return
        }
        guard let apiKey = keySyncService.activeAPIKey() else {
            print("[Analysis] Skipped — no API key for provider \(providerStr)")
            return
        }
        guard let rootURL = fileSystem.rootURL else {
            print("[Analysis] Skipped — no rootURL")
            return
        }

        let model = keySyncService.activeModel ?? provider.defaultModel
        let resolvedModel = (model == "auto") ? provider.defaultModel : model

        // Query model context directly — @Query may not have refreshed yet after sync
        let descriptor = FetchDescriptor<MediaItem>()
        let allCurrentItems = (try? modelContext.fetch(descriptor)) ?? []
        let unanalyzed = allCurrentItems.filter { $0.analysisResult == nil && !$0.isAnalyzing && $0.analysisError == nil && !$0.isVideo }
        guard !unanalyzed.isEmpty else {
            print("[Analysis] No unanalyzed items found (total: \(allCurrentItems.count))")
            return
        }

        print("[Analysis] Found \(unanalyzed.count) unanalyzed items, starting analysis")

        analysisTask?.cancel()
        analysisTask = Task {
            for item in unanalyzed {
                guard !Task.isCancelled else { break }

                item.isAnalyzing = true
                do {
                    let image = try loadImage(for: item, rootURL: rootURL)

                    // Resolve guidance and space context
                    var guidance: String?
                    var spaceContext: String?
                    if let space = item.space {
                        spaceContext = "This image belongs to a collection called \"\(space.name)\". Use this as context to inform your analysis."
                        if space.useCustomPrompt, let custom = space.customPrompt, !custom.isEmpty {
                            guidance = custom
                        }
                    }

                    let result = try await AIAnalysisService.shared.analyze(
                        image: image,
                        provider: provider,
                        model: resolvedModel,
                        apiKey: apiKey,
                        guidance: guidance,
                        spaceContext: spaceContext
                    )
                    item.analysisResult = result
                    item.isAnalyzing = false

                    // Write back to sidecar JSON so Mac picks up the analysis
                    writeSidecar(for: item, rootURL: rootURL)

                    // Rebuild search index to include new analysis
                    searchService.buildIndex(items: allItems)

                    try? modelContext.save()
                    print("[Analysis] Completed: \(item.id)")
                } catch {
                    item.isAnalyzing = false
                    item.analysisError = error.localizedDescription
                    print("[Analysis] Failed for \(item.id): \(error.localizedDescription)")
                }
            }
        }
    }

    private func loadImage(for item: MediaItem, rootURL: URL) throws -> UIImage {
        let imageURL = rootURL.appendingPathComponent("images/\(item.filename)")
        guard let data = try? Data(contentsOf: imageURL),
              let image = UIImage(data: data) else {
            throw AIAnalysisService.AnalysisError.imageConversionFailed
        }
        return image
    }

    private func writeSidecar(for item: MediaItem, rootURL: URL) {
        let metadataDir = rootURL.appendingPathComponent("metadata")
        let sidecarURL = metadataDir.appendingPathComponent("\(item.id).json")

        // Read existing sidecar to preserve all fields
        guard let existingData = try? Data(contentsOf: sidecarURL) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var json = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] else { return }

        // Add analysis fields
        if let result = item.analysisResult {
            json["imageContext"] = result.imageContext
            json["imageSummary"] = result.imageSummary
            json["patterns"] = result.patterns.map { ["name": $0.name, "confidence": $0.confidence] }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? updatedData.write(to: sidecarURL, options: .atomic)
        }
    }
}
