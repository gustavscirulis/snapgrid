import SwiftUI

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
    @State private var selectedIndex: Int?
    @State private var selectedItemId: String?
    @State private var sourceRect: CGRect = .zero
    @State private var thumbnailImage: UIImage?
    @State private var showOverlay = false
    @State private var items: [SnapGridItem] = []
    @State private var spaces: [Space] = []
    @State private var activeSpaceId: String? = nil
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var error: String?
    @State private var hasAttemptedRescan = false
    @State private var tabScrollProgress: CGFloat = 0

    // MARK: - Index ↔ activeSpaceId bridging

    private var activeIndex: Int {
        guard let id = activeSpaceId else { return 0 }
        return (spaces.firstIndex { $0.id == id } ?? -1) + 1
    }

    /// Binding that syncs TabView page selection with activeSpaceId.
    /// The `set` wraps in withAnimation so the underline slides on swipe completion.
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

    private var searchFilteredItems: [SnapGridItem] {
        guard !searchText.isEmpty else { return items }
        let query = searchText.lowercased()
        return items.filter { matchesSearch($0, query: query) }
    }

    private func itemsForSpace(_ space: Space) -> [SnapGridItem] {
        var result = items.filter { $0.spaceId == space.id }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { matchesSearch($0, query: query) }
        }
        return result
    }

    private func matchesSearch(_ item: SnapGridItem, query: String) -> Bool {
        if let patterns = item.patterns,
           patterns.contains(where: { $0.name.lowercased().contains(query) }) {
            return true
        }
        if let context = item.imageContext?.lowercased(), context.contains(query) {
            return true
        }
        if let title = item.title?.lowercased(), title.contains(query) {
            return true
        }
        if query == "vid" && item.isVideo { return true }
        if query == "img" && !item.isVideo { return true }
        return false
    }

    /// Items visible in the currently active space/tab (used for full-screen swipe navigation)
    private var currentVisibleItems: [SnapGridItem] {
        if let activeSpaceId, let space = spaces.first(where: { $0.id == activeSpaceId }) {
            return itemsForSpace(space)
        }
        return searchFilteredItems
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let gridWidth = geo.size.width - 24 // 12pt padding on each side

            ZStack {
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
                        } else if items.isEmpty {
                            EmptyStateView()
                        } else if spaces.isEmpty {
                            ScrollView {
                                MasonryGrid(
                                    items: searchFilteredItems,
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
                        } else {
                            VStack(spacing: 0) {
                                SpaceTabBar(
                                    spaces: spaces,
                                    activeSpaceId: $activeSpaceId,
                                    scrollProgress: tabScrollProgress
                                )

                                TabView(selection: activeIndexBinding) {
                                    ScrollView {
                                        MasonryGrid(
                                            items: searchFilteredItems,
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

                                    ForEach(Array(spaces.enumerated()), id: \.element.id) { index, space in
                                        ScrollView {
                                            MasonryGrid(
                                                items: itemsForSpace(space),
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
                    .toolbarColorScheme(.dark, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                Button(role: .destructive) {
                                    fileSystem.disconnect()
                                } label: {
                                    Label("Disconnect Folder", systemImage: "folder.badge.minus")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search patterns, context...")
                }

                // Full-screen overlay — above NavigationStack
                if showOverlay, let startIndex = selectedIndex {
                    FullScreenImageOverlay(
                        items: currentVisibleItems,
                        startIndex: startIndex,
                        sourceRect: sourceRect,
                        screenSize: geo.size,
                        thumbnailImage: thumbnailImage,
                        onClose: {
                            showOverlay = false
                            selectedIndex = nil
                            selectedItemId = nil
                            thumbnailImage = nil
                        }
                    )
                }
            }
        }
        .task {
            await loadContent()
        }
    }

    // MARK: - Item Selection

    private func handleItemSelected(_ item: SnapGridItem, _ rect: CGRect, _ thumb: UIImage?) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let visibleItems = currentVisibleItems
        selectedIndex = visibleItems.firstIndex(where: { $0.id == item.id }) ?? 0
        selectedItemId = item.id
        sourceRect = rect
        thumbnailImage = thumb
        showOverlay = true
    }

    // MARK: - Data Loading

    private func loadContent() async {
        let isInitialLoad = items.isEmpty
        isLoading = isInitialLoad
        error = nil

        guard let metadataDir = fileSystem.metadataDir,
              let imagesDir = fileSystem.imagesDir,
              let thumbnailsDir = fileSystem.thumbnailsDir,
              let rootURL = fileSystem.rootURL else {
            self.error = "No access to SnapGrid folder"
            self.isLoading = false
            return
        }

        #if DEBUG
        print("[MainView] Loading content... rootURL=\(rootURL.path)")
        #endif

        let loader = MetadataLoader(metadataDir: metadataDir, imagesDir: imagesDir, thumbnailsDir: thumbnailsDir)
        let spacesManager = SpacesManager(rootURL: rootURL)

        // Load spaces early so tabs appear alongside the first items
        let loadedSpaces = (try? spacesManager.loadSpaces()) ?? []
        self.spaces = loadedSpaces

        var lastUpdate: LoadUpdate?

        do {
            for try await update in loader.loadItemsProgressively() {
                lastUpdate = update
                // On initial load, show items progressively as they're decoded.
                // On refresh, keep existing items visible until fully loaded.
                if isInitialLoad {
                    self.items = update.items
                    self.isLoading = false
                }
            }

            // Apply final result (handles both initial load and refresh)
            if let final_ = lastUpdate {
                self.items = final_.items
                self.isLoading = false
                // Prefetch all thumbnails in the background at grid size
                let screenWidth = await MainActor.run { UIScreen.main.bounds.width }
                let columnWidth = (screenWidth - 24 - 8) / 2 // 12pt padding each side, 8pt spacing
                ThumbnailCache.shared.prefetchThumbnails(for: final_.items, targetPixelWidth: columnWidth * 2)
            }

            #if DEBUG
            print("[MainView] Loaded \(items.count) items, \(loadedSpaces.count) spaces")
            #endif

            // If some metadata files were still downloading from iCloud, re-scan once after a delay
            if let skipped = lastUpdate?.skippedCount, skipped > 0, !hasAttemptedRescan {
                hasAttemptedRescan = true
                #if DEBUG
                print("[MainView] \(skipped) metadata files pending iCloud download, will re-scan in 15s")
                #endif
                Task {
                    try? await Task.sleep(for: .seconds(15))
                    await loadContent()
                }
            }
        } catch {
            #if DEBUG
            print("[MainView] Error loading: \(error)")
            #endif
            self.error = error.localizedDescription
            self.isLoading = false
        }
    }
}
