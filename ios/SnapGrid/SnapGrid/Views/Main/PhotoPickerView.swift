import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Photos Library Picker

struct PhotosPickerWrapper: UIViewControllerRepresentable {
    let onImagesPicked: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 0
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotosPickerWrapper

        init(_ parent: PhotosPickerWrapper) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard !results.isEmpty else {
                parent.onImagesPicked([])
                return
            }

            let providers = results.map(\.itemProvider)
            let lock = NSLock()
            var images: [UIImage] = []
            let group = DispatchGroup()

            for provider in providers {
                guard provider.canLoadObject(ofClass: UIImage.self) else { continue }
                group.enter()
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    if let image = object as? UIImage {
                        lock.lock()
                        images.append(image)
                        lock.unlock()
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) { [parent] in
                parent.onImagesPicked(images)
            }
        }
    }
}

// MARK: - Files Picker

struct DocumentPickerWrapper: UIViewControllerRepresentable {
    let onImagesPicked: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image])
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerWrapper

        init(_ parent: DocumentPickerWrapper) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            var images: [UIImage] = []

            for url in urls {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }

                guard let data = try? Data(contentsOf: url),
                      let image = UIImage(data: data) else { continue }
                images.append(image)
            }

            parent.onImagesPicked(images)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onImagesPicked([])
        }
    }
}
