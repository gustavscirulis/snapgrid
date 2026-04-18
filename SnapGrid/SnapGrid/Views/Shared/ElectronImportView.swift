import SwiftUI
import SwiftData

struct ElectronImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool

    @State private var importService = ElectronImportService()
    var initialLibraryURL: URL

    var body: some View {
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
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            Task {
                await importService.importLibrary(from: initialLibraryURL, into: modelContext)
                isPresented = false
            }
        }
    }
}
