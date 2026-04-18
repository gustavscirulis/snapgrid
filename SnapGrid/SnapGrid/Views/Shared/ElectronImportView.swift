import SwiftUI
import SwiftData

struct ElectronImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool

    @State private var importService = ElectronImportService()
    var initialLibraryURL: URL
    @State private var libraryURL: URL?
    @State private var itemCount = 0

    private enum Phase {
        case ready, importing, done
    }

    @State private var phase: Phase = .ready

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .ready:
                readyView
            case .importing:
                importingView
            case .done:
                doneView
            }
        }
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            libraryURL = initialLibraryURL
            itemCount = importService.countItems(in: initialLibraryURL)
        }
    }

    // MARK: - Phases

    private var readyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.snapAccent)

            VStack(spacing: 6) {
                Text("Import from SnapGrid 1")
                    .font(.headline)
                Text("Found \(itemCount) items at:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(libraryURL?.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~") ?? "")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text("Your screenshots, spaces, and analysis results will be copied over. Nothing in your original library will be changed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            HStack(spacing: 12) {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Choose Folder...") { pickFolder() }
                Button("Import") { startImport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(itemCount == 0)
            }
        }
        .padding(32)
    }

    private var importingView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Importing...")
                    .font(.headline)

                ProgressView(value: Double(importService.importedCount), total: Double(max(importService.totalItems, 1)))
                    .frame(width: 280)

                Text("\(importService.importedCount) of \(importService.totalItems)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Text(importService.currentFilename)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 280)
            }

            Button("Cancel") {
                importService.cancel()
            }
        }
        .padding(32)
    }

    private var doneView: some View {
        VStack(spacing: 20) {
            let result = importService.importResult

            Image(systemName: "checkmark.circle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.green)

            VStack(spacing: 6) {
                Text("Import Complete")
                    .font(.headline)

                if let result {
                    VStack(spacing: 2) {
                        Text("\(result.itemsImported) items imported")
                        if result.spacesImported > 0 {
                            Text("\(result.spacesImported) spaces created")
                        }
                        if result.duplicatesSkipped > 0 {
                            Text("\(result.duplicatesSkipped) duplicates skipped")
                        }
                        if result.errors > 0 {
                            Text("\(result.errors) errors")
                                .foregroundStyle(.red)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }

            Button("Done") { isPresented = false }
                .keyboardShortcut(.defaultAction)
        }
        .padding(32)
    }

    // MARK: - Actions

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select your SnapGrid 1 library folder"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents")

        let response = panel.runModal()
        if response == .OK, let url = panel.url {
            if importService.validateLibraryFolder(url) {
                libraryURL = url
                itemCount = importService.countItems(in: url)
                phase = .ready
            }
        }
    }

    private func startImport() {
        guard let url = libraryURL else { return }
        phase = .importing
        Task {
            await importService.importLibrary(from: url, into: modelContext)
            phase = .done
        }
    }
}
