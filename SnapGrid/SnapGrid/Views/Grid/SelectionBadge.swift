import SwiftUI

struct SelectionBadge: View {
    let count: Int

    var body: some View {
        let base = Text("\(count) selected")
            .font(.callout.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

        #if compiler(>=6.3)
        if #available(macOS 26, *) {
            base
                .glassEffect(.regular.tint(.accentColor), in: .capsule)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                .accessibilityLabel("\(count) items selected")
                .accessibilityAddTraits(.updatesFrequently)
        } else {
            base
                .background(Color.accentColor)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                .accessibilityLabel("\(count) items selected")
                .accessibilityAddTraits(.updatesFrequently)
        }
        #else
        base
            .background(Color.accentColor)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            .accessibilityLabel("\(count) items selected")
            .accessibilityAddTraits(.updatesFrequently)
        #endif
    }
}
