import SwiftUI
import SwiftData

struct StorageSettingsTab: View {
    @Query private var allItems: [MediaItem]
    @AppStorage("keepFilesLocal") private var keepFilesLocal: Bool = false

    var body: some View {
        Form {
            if MediaStorageService.shared.isUsingiCloud {
                iCloudSection
            }

            Section("Location") {
                LabeledContent("Path") {
                    HStack {
                        Text(MediaStorageService.shared.baseURL.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Show in Finder") {
                            NSWorkspace.shared.open(MediaStorageService.shared.baseURL)
                        }
                        .controlSize(.small)
                    }
                }

                LabeledContent("Items") {
                    Text("\(allItems.count)")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Sync") {
                    Text(MediaStorageService.shared.isUsingiCloud ? "iCloud Drive" : "Local only")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - iCloud Section

    @ViewBuilder
    private var iCloudSection: some View {
        let manager = iCloudDownloadManager.shared

        Section("iCloud") {
            Toggle("Keep files downloaded", isOn: $keepFilesLocal)
                .onChange(of: keepFilesLocal) { _, enabled in
                    if enabled {
                        manager.downloadAll()
                    } else {
                        manager.stop()
                    }
                }

            if manager.isDownloading {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(
                        value: Double(manager.downloadedFiles),
                        total: Double(max(manager.totalFiles, 1))
                    )
                    Text("Downloading \(manager.downloadedFiles) of \(manager.totalFiles) files…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if keepFilesLocal {
                let evicted = manager.countEvicted()
                if evicted == 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text("All files are stored locally")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 4) {
                        Text("\(evicted) files in iCloud only")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Download Now") {
                            manager.downloadAll()
                        }
                        .controlSize(.small)
                    }
                }
            }

        }
    }
}
