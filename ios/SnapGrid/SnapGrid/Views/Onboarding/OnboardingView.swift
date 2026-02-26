import SwiftUI
import UniformTypeIdentifiers

struct OnboardingView: View {
    @EnvironmentObject var fileSystem: FileSystemManager
    @State private var showPicker = false

    var body: some View {
        ZStack {
            Color.snapDarkBackground
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(.white.opacity(0.9))

                    Text("SnapGrid")
                        .font(.system(size: 34, weight: .bold, design: .default))
                        .foregroundStyle(.white)

                    Text("Browse your SnapGrid library\non this device")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }

                Spacer()

                VStack(spacing: 16) {
                    Button {
                        showPicker = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "folder")
                                .font(.system(size: 17, weight: .medium))
                            Text("Select SnapGrid Folder")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 24)

                    Text("Open the Files app location:\niCloud Drive → Documents → SnapGrid")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)

                    if let error = fileSystem.error {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(.red.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }

                Spacer()
                    .frame(height: 40)
            }
        }
        .sheet(isPresented: $showPicker) {
            FolderPicker { url in
                if let url {
                    fileSystem.grantAccess(to: url)
                }
            }
        }
    }
}

struct FolderPicker: UIViewControllerRepresentable {
    let onPick: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void

        init(onPick: @escaping (URL?) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(nil)
        }
    }
}
