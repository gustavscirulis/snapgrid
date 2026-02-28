import SwiftUI

struct MainView: View {
    @EnvironmentObject var fileSystem: FileSystemManager
    @State private var selectedItem: SnapGridItem?
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
                                    selectedItemId: showOverlay ? selectedItem?.id : nil,
                                    onItemSelected: handleItemSelected
                                )
                                .padding(.horizontal, 12)
                            }
                            .refreshable {
                                hasAttemptedRescan = false
                                await loadContent()
                            }
                        } else {
                            VStack(spacing: 0) {
                                SpaceTabBar(
                                    spaces: spaces,
                                    activeSpaceId: $activeSpaceId
                                )

                                TabView(selection: activeIndexBinding) {
                                    ScrollView {
                                        MasonryGrid(
                                            items: searchFilteredItems,
                                            availableWidth: gridWidth,
                                            selectedItemId: showOverlay ? selectedItem?.id : nil,
                                            onItemSelected: handleItemSelected
                                        )
                                        .padding(.horizontal, 12)
                                        .padding(.top, 12)
                                    }
                                    .refreshable { await loadContent() }
                                    .tag(0)

                                    ForEach(Array(spaces.enumerated()), id: \.element.id) { index, space in
                                        ScrollView {
                                            MasonryGrid(
                                                items: itemsForSpace(space),
                                                availableWidth: gridWidth,
                                                selectedItemId: showOverlay ? selectedItem?.id : nil,
                                                onItemSelected: handleItemSelected
                                            )
                                            .padding(.horizontal, 12)
                                            .padding(.top, 12)
                                        }
                                        .refreshable { await loadContent() }
                                        .tag(index + 1)
                                    }
                                }
                                .tabViewStyle(.page(indexDisplayMode: .never))
                            }
                        }
                    }
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
                if showOverlay, let item = selectedItem {
                    FullScreenImageOverlay(
                        item: item,
                        sourceRect: sourceRect,
                        screenSize: geo.size,
                        thumbnailImage: thumbnailImage,
                        onClose: {
                            showOverlay = false
                            selectedItem = nil
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
        selectedItem = item
        sourceRect = rect
        thumbnailImage = thumb
        showOverlay = true
    }

    // MARK: - Data Loading

    private func loadContent() async {
        isLoading = items.isEmpty
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

        do {
            let result = try await loader.loadAllItems()
            #if DEBUG
            print("[MainView] Loaded \(result.items.count) items")
            #endif

            let loadedSpaces = (try? spacesManager.loadSpaces()) ?? []
            #if DEBUG
            print("[MainView] Loaded \(loadedSpaces.count) spaces")
            #endif

            self.items = result.items
            self.spaces = loadedSpaces
            self.isLoading = false

            // If some metadata files were still downloading from iCloud, re-scan once after a delay
            if result.skippedCount > 0 && !hasAttemptedRescan {
                hasAttemptedRescan = true
                #if DEBUG
                print("[MainView] \(result.skippedCount) metadata files pending iCloud download, will re-scan in 15s")
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
