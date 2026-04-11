import SwiftUI
import UIKit

enum DetailChrome {
    static let navigationBarHeight: CGFloat = 44
    static let mediaTopPadding: CGFloat = 12

    static func toolbarTitle(currentItemId: String?, items: [MediaItem], fallback: String) -> String {
        guard
            let currentItemId,
            let item = items.first(where: { $0.id == currentItemId }),
            let summary = item.analysisResult?.imageSummary
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !summary.isEmpty
        else {
            return fallback
        }

        return summary
    }

    static func showsTopBarActions(isDetailPresented: Bool) -> Bool {
        !isDetailPresented
    }

    static func hidesTabBar(isDetailPresented: Bool) -> Bool {
        isDetailPresented
    }

    static func reservedTopInset(safeAreaTop: CGFloat) -> CGFloat {
        safeAreaTop + navigationBarHeight + mediaTopPadding
    }
}

struct MediaDetailModal: View {
    let items: [MediaItem]
    let title: String
    @Binding var showOverlay: Bool
    @Binding var selectedItemId: String?
    @Binding var selectedIndex: Int?
    let sourceRect: CGRect
    @Binding var thumbnailImage: UIImage?
    @Binding var gridItemRects: [String: CGRect]
    let onSearchPattern: (String) -> Void
    let onDelete: (MediaItem) -> Void
    let onOverlayClosed: () -> Void

    @State private var closeRequestID = 0
    @State private var shareRequestID = 0
    @State private var deleteRequestID = 0
    @State private var showsDetailChrome = false
    @State private var showDeleteConfirmation = false

    private var detailTitle: String {
        DetailChrome.toolbarTitle(
            currentItemId: selectedItemId,
            items: items,
            fallback: title
        )
    }

    private var currentItem: MediaItem? {
        if let selectedItemId {
            return items.first(where: { $0.id == selectedItemId })
        }

        guard let selectedIndex, items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    private var resolvedStartIndex: Int? {
        if let selectedItemId,
           let matchedIndex = items.firstIndex(where: { $0.id == selectedItemId }) {
            return matchedIndex
        }

        guard let selectedIndex, !items.isEmpty else { return nil }
        return min(max(selectedIndex, 0), items.count - 1)
    }

    var body: some View {
        GeometryReader { geo in
            let overlaySize = CGSize(
                width: geo.size.width,
                height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            )
            let topReservedInset = DetailChrome.reservedTopInset(safeAreaTop: geo.safeAreaInsets.top)

            if let startIndex = resolvedStartIndex {
                NavigationStack {
                    Color.clear
                        .background(TransparentNavigationContainer())
                        .ignoresSafeArea()
                        .overlay {
                            FullScreenImageOverlay(
                                items: items,
                                startIndex: startIndex,
                                sourceRect: sourceRect,
                                screenSize: overlaySize,
                                thumbnailImage: thumbnailImage,
                                gridItemRects: $gridItemRects,
                                closeRequestID: closeRequestID,
                                shareRequestID: shareRequestID,
                                deleteRequestID: deleteRequestID,
                                topReservedInset: topReservedInset,
                                onCurrentItemChanged: { itemId in
                                    selectedItemId = itemId
                                },
                                onHeroSettledChanged: { settled in
                                    withAnimation(.easeInOut(duration: 0.22)) {
                                        showsDetailChrome = settled
                                    }
                                },
                                onClose: handleOverlayClosed,
                                onSearchPattern: onSearchPattern,
                                onDelete: onDelete
                            )
                        }
                        .navigationTitle(detailTitle)
                        .navigationBarTitleDisplayMode(.inline)
                        .navigationBarBackButtonHidden(true)
                        .toolbar(showsDetailChrome ? .visible : .hidden, for: .navigationBar)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    closeRequestID += 1
                                } label: {
                                    Label("Back", systemImage: "chevron.left")
                                }
                            }

                            ToolbarItemGroup(placement: .topBarTrailing) {
                                Button {
                                    shareRequestID += 1
                                } label: {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                                .disabled(currentItem?.mediaURL == nil)

                                Button(role: .destructive) {
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .disabled(currentItem == nil)
                            }
                        }
                        .toolbarColorScheme(.dark, for: .navigationBar)
                        .confirmationDialog("Delete this item?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                            Button("Delete", role: .destructive) {
                                deleteRequestID += 1
                            }
                        }
                }
            }
        }
    }

    private func handleOverlayClosed() {
        showsDetailChrome = false
        showOverlay = false
        selectedIndex = nil
        selectedItemId = nil
        thumbnailImage = nil
        onOverlayClosed()
    }
}

private struct TransparentNavigationContainer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.applyTransparency()
    }

    final class Controller: UIViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
            view.isOpaque = false
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            applyTransparency()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyTransparency()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            applyTransparency()
        }

        func applyTransparency() {
            view.backgroundColor = .clear
            view.isOpaque = false

            var ancestor: UIView? = view
            while let current = ancestor {
                current.backgroundColor = .clear
                current.isOpaque = false
                ancestor = current.superview
            }

            parent?.view.backgroundColor = .clear
            parent?.view.isOpaque = false

            navigationController?.view.backgroundColor = .clear
            navigationController?.view.isOpaque = false
            navigationController?.topViewController?.view.backgroundColor = .clear
            navigationController?.topViewController?.view.isOpaque = false
        }
    }
}
