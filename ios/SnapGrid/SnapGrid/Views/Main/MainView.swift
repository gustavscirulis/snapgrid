import SwiftUI

struct MainView: View {
    @EnvironmentObject var fileSystem: FileSystemManager
    @State private var items: [SnapGridItem] = []
    @State private var spaces: [Space] = []
    @State private var activeSpaceId: String? = nil
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var error: String?
    @State private var hasAttemptedRescan = false

    private var filteredItems: [SnapGridItem] {
        var result = items

        // Filter by space
        if let spaceId = activeSpaceId {
            result = result.filter { $0.spaceId == spaceId }
        }

        // Filter by search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { item in
                // Search patterns
                if let patterns = item.patterns,
                   patterns.contains(where: { $0.name.lowercased().contains(query) }) {
                    return true
                }
                // Search image context
                if let context = item.imageContext?.lowercased(), context.contains(query) {
                    return true
                }
                // Search title
                if let title = item.title?.lowercased(), title.contains(query) {
                    return true
                }
                // Type filter
                if query == "vid" && item.isVideo { return true }
                if query == "img" && !item.isVideo { return true }
                return false
            }
        }

        return result
    }

    var body: some View {
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
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            if !spaces.isEmpty {
                                SpaceTabBar(
                                    spaces: spaces,
                                    activeSpaceId: $activeSpaceId
                                )
                                .padding(.bottom, 12)
                            }

                            MasonryGrid(items: filteredItems)
                                .padding(.horizontal, 12)
                        }
                    }
                    .refreshable {
                        hasAttemptedRescan = false
                        await loadContent()
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
        .task {
            await loadContent()
        }
    }

    private func loadContent() async {
        isLoading = items.isEmpty
        error = nil

        print("[MainView] Loading content... rootURL=\(fileSystem.rootURL?.path ?? "nil")")

        let loader = MetadataLoader(fileSystem: fileSystem)
        let spacesManager = SpacesManager(fileSystem: fileSystem)

        do {
            let result = try await loader.loadAllItems()
            print("[MainView] Loaded \(result.items.count) items")

            // Load spaces from spaces.json (synced by desktop app)
            let loadedSpaces = (try? spacesManager.loadSpaces()) ?? []
            print("[MainView] Loaded \(loadedSpaces.count) spaces")

            self.items = result.items
            self.spaces = loadedSpaces
            self.isLoading = false

            // If some metadata files were still downloading from iCloud, re-scan once after a delay
            if result.skippedCount > 0 && !hasAttemptedRescan {
                hasAttemptedRescan = true
                print("[MainView] \(result.skippedCount) metadata files pending iCloud download, will re-scan in 15s")
                Task {
                    try? await Task.sleep(for: .seconds(15))
                    await loadContent()
                }
            }
        } catch {
            print("[MainView] Error loading: \(error)")
            self.error = error.localizedDescription
            self.isLoading = false
        }
    }
}
