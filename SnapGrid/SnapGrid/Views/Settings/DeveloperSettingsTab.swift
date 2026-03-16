import SwiftUI
import SwiftData

struct DeveloperSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [MediaItem]
    @State private var showConfirmReset = false
    @State private var trashEmptied = false

    var body: some View {
        Form {
            Section("Storage") {
                LabeledContent("Location") {
                    HStack {
                        Text(MediaStorageService.shared.baseURL.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Open") {
                            NSWorkspace.shared.open(MediaStorageService.shared.baseURL)
                        }
                    }
                }

                LabeledContent("Items") {
                    Text("\(allItems.count)")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Trash") {
                HStack {
                    Button("Empty Trash Now") {
                        MediaStorageService.shared.emptyTrash()
                        trashEmptied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { trashEmptied = false }
                    }
                    if trashEmptied {
                        Text("Emptied")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                Text("Trash is automatically emptied after 30 days.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Danger Zone") {
                Button("Reset All Data", role: .destructive) {
                    showConfirmReset = true
                }
                .alert("Reset All Data?", isPresented: $showConfirmReset) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reset", role: .destructive) {
                        resetAllData()
                    }
                } message: {
                    Text("This will delete all imported media, analysis results, and spaces. This cannot be undone.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func resetAllData() {
        // Delete all SwiftData records
        try? modelContext.delete(model: MediaItem.self)
        try? modelContext.delete(model: Space.self)
        try? modelContext.delete(model: AnalysisResult.self)
        try? modelContext.save()

        // Clear file storage
        let fm = FileManager.default
        let storage = MediaStorageService.shared
        for dir in [storage.mediaDir, storage.thumbnailDir, storage.trashMediaDir, storage.trashThumbnailDir] {
            if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for file in files {
                    try? fm.removeItem(at: file)
                }
            }
        }
    }
}
