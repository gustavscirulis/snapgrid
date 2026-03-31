import SwiftUI

/// Wraps UIActivityViewController for SwiftUI. Uses a temp file URL
/// (outside iCloud) so iOS shows "Send a Copy" instead of "Collaborate".
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
