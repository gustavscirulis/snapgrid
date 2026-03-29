import SwiftUI

struct SelectionBadge: View {
    let count: Int

    var body: some View {
        Text("\(count) selected")
            .font(.callout.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.accentColor)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            .accessibilityLabel("\(count) items selected")
            .accessibilityAddTraits(.updatesFrequently)
    }
}
