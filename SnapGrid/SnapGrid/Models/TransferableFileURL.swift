import SwiftUI
import UniformTypeIdentifiers

/// Wraps a file URL for drag-to-Finder export via Transferable protocol
struct TransferableFileURL: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .fileURL) { item in
            SentTransferredFile(item.url)
        }
    }
}
