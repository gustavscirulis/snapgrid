import SwiftUI
import SwiftData

struct ElectronImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool

    @State private var importService = ElectronImportService()
    var initialLibraryURL: URL

    private enum Phase {
        case importing, done
    }

    @State private var phase: Phase = .importing

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .importing:
                importingView
            case .done:
                doneView
            }
        }
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            startImport()
        }
    }

    // MARK: - Phases

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

    private func startImport() {
        phase = .importing
        Task {
            await importService.importLibrary(from: initialLibraryURL, into: modelContext)
            phase = .done
        }
    }
}
