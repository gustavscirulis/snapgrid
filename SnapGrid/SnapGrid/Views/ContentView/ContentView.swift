import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MediaItem.createdAt, order: .reverse) private var allItems: [MediaItem]
    @Query(sort: \Space.order) private var spaces: [Space]
    @State private var appState = AppState()
    @State private var importService = ImportService()
    @State private var isDragTargeted = false

    private var filteredItems: [MediaItem] {
        var items = allItems

        if let spaceId = appState.activeSpaceId {
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

    var body: some View {
        ZStack {
            Color.snapBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Space tab bar
                SpaceTabBar(
                    spaces: spaces,
                    activeSpaceId: $appState.activeSpaceId,
                    onCreateSpace: createSpace,
                    onDeleteSpace: deleteSpace,
                    onRenameSpace: renameSpace
                )
                .padding(.top, 8)

                // Main content
                if allItems.isEmpty {
                    EmptyStateView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredItems.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("No results found")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    MasonryGridView(
                        items: filteredItems,
                        thumbnailSize: appState.thumbnailSize,
                        selectedIds: appState.selectedIds,
                        onSelect: { id in appState.detailItem = id },
                        onToggleSelect: { id in appState.toggleSelection(id) },
                        onDelete: deleteItems,
                        onAssignToSpace: assignToSpace
                    )
                }
            }

            // Detail overlay
            if let detailId = appState.detailItem,
               let item = allItems.first(where: { $0.id == detailId }) {
                MediaDetailView(
                    item: item,
                    allItems: filteredItems,
                    onClose: { appState.detailItem = nil },
                    onNavigate: { appState.detailItem = $0 }
                )
                .transition(.opacity)
            }

            // Drag overlay
            if isDragTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.snapAccent, lineWidth: 3)
                    .background(Color.snapAccent.opacity(0.1))
                    .ignoresSafeArea()
            }
        }
        .searchable(text: $appState.searchText, prompt: "Search patterns, descriptions...")
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .onReceive(NotificationCenter.default.publisher(for: .importFiles)) { _ in
            openImportPanel()
        }
        .onDeleteCommand {
            deleteSelectedItems()
        }
        .environment(appState)
        .environment(importService)
        .preferredColorScheme(.dark)
    }

    // MARK: - Actions

    private func handleDrop(_ providers: [NSItemProvider]) {
        Task {
            var urls: [URL] = []
            for provider in providers {
                if let item = try? await provider.loadItem(forTypeIdentifier: "public.file-url"),
                   let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
            if !urls.isEmpty {
                await importService.importFiles(urls, into: modelContext, spaceId: appState.activeSpaceId)
            }
        }
    }

    private func openImportPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .gif, .mpeg4Movie, .movie]

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
        let batch = items.map { (id: $0.id, filename: $0.filename) }
        appState.pushDeleteBatch(batch)

        for item in items {
            try? MediaStorageService.shared.deleteMedia(filename: item.filename)
            try? MediaStorageService.shared.deleteThumbnail(id: item.id)
            modelContext.delete(item)
        }
        try? modelContext.save()
        appState.clearSelection()
    }

    private func deleteSelectedItems() {
        guard !appState.selectedIds.isEmpty else { return }
        deleteItems(appState.selectedIds)
    }

    private func createSpace() {
        let space = Space(name: "New Space", order: spaces.count)
        modelContext.insert(space)
        try? modelContext.save()
    }

    private func deleteSpace(_ id: String) {
        if let space = spaces.first(where: { $0.id == id }) {
            modelContext.delete(space)
            try? modelContext.save()
            if appState.activeSpaceId == id {
                appState.activeSpaceId = nil
            }
        }
    }

    private func renameSpace(_ id: String, _ newName: String) {
        if let space = spaces.first(where: { $0.id == id }) {
            space.name = newName
            try? modelContext.save()
        }
    }

    private func assignToSpace(itemIds: Set<String>, spaceId: String?) {
        let space = spaceId.flatMap { sid in spaces.first(where: { $0.id == sid }) }
        for item in allItems where itemIds.contains(item.id) {
            item.space = space
        }
        try? modelContext.save()
    }
}
