import SwiftUI

struct ToastOverlay: View {
    let toasts: [ToastMessage]

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            ForEach(toasts) { toast in
                let base = Text(toast.message)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                if #available(macOS 26, *) {
                    base
                        .glassEffect(.regular, in: .capsule)
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .accessibilityLabel(toast.message)
                        .accessibilityAddTraits(.updatesFrequently)
                } else {
                    base
                        .background(.ultraThinMaterial.opacity(0.9))
                        .background(.black.opacity(0.6))
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .accessibilityLabel(toast.message)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
        }
        .padding(.bottom, 24)
        .allowsHitTesting(false)
    }
}
