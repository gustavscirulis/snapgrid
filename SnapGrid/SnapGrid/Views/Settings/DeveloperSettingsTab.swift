import SwiftUI
import SwiftData

struct DeveloperSettingsTab: View {
    @State private var showConfirmReset = false
    @State private var trashEmptied = false
    @State private var trashCount = 0

    var body: some View {
        Form {
            Section("Trash") {
                LabeledContent("Items in trash") {
                    Text("\(trashCount)")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Empty Trash Now") {
                        MediaStorageService.shared.emptyTrash()
                        trashCount = 0
                        trashEmptied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { trashEmptied = false }
                    }
                    .disabled(trashCount == 0)

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
                    Text("This will delete all media, analysis results, and spaces. This cannot be undone. The app will restart.")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { trashCount = countTrashItems() }
    }

    private func countTrashItems() -> Int {
        let fm = FileManager.default
        let dir = MediaStorageService.shared.trashMediaDir
        return (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?.count ?? 0
    }

    private func resetAllData() {
        _ = DataCleanupService.deleteCorruptedStore()

        let fm = FileManager.default
        let storage = MediaStorageService.shared
        for dir in [storage.mediaDir, storage.thumbnailDir, storage.trashMediaDir, storage.trashThumbnailDir] {
            if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for file in files {
                    try? fm.removeItem(at: file)
                }
            }
        }

        ImageCacheService.shared.clearAll()

        let url = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", url.path]
        try? task.run()

        NSApplication.shared.terminate(nil)
    }
}
