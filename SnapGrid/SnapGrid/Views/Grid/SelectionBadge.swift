import SwiftUI

struct SelectionBadge: View {
    let count: Int

    var body: some View {
        Text("\(count) selected")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.blue)  // ImageGrid.tsx:728 — bg-blue-500 (always blue, not adaptive accent)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }
}
