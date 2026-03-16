import SwiftUI

struct ToastOverlay: View {
    let toasts: [ToastMessage]

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            ForEach(toasts) { toast in
                Text(toast.message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.75))
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 24)
        .allowsHitTesting(false)
    }
}
