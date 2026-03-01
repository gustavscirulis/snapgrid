import SwiftUI
import StoreKit

/// Button for selecting a subscription plan.
///
/// Usage:
/// ```swift
/// SubscriptionButton(
///     product: monthlyProduct,
///     isSelected: selectedID == monthlyProduct.id,
///     isPopular: false
/// ) {
///     selectedID = monthlyProduct.id
/// }
/// ```
struct SubscriptionButton: View {

    let product: Product
    let isSelected: Bool
    let isPopular: Bool
    let savingsPercent: Int?
    let action: () -> Void

    init(
        product: Product,
        isSelected: Bool,
        isPopular: Bool = false,
        savingsPercent: Int? = nil,
        action: @escaping () -> Void
    ) {
        self.product = product
        self.isSelected = isSelected
        self.isPopular = isPopular
        self.savingsPercent = savingsPercent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .accentColor : .secondary)
                    .font(.title2)

                // Plan details
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(product.displayName)
                            .font(.headline)

                        if isPopular {
                            Text("POPULAR")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange)
                                .cornerRadius(4)
                        }
                    }

                    if let description = product.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Price
                VStack(alignment: .trailing, spacing: 2) {
                    Text(product.displayPrice)
                        .font(.headline)

                    if let period = periodText {
                        Text(period)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let savings = savingsPercent, savings > 0 {
                        Text("Save \(savings)%")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var periodText: String? {
        guard let subscription = product.subscription else {
            // Lifetime or one-time purchase
            return "one-time"
        }

        let period = subscription.subscriptionPeriod

        switch period.unit {
        case .day:
            return period.value == 1 ? "per day" : "per \(period.value) days"
        case .week:
            return period.value == 1 ? "per week" : "per \(period.value) weeks"
        case .month:
            return period.value == 1 ? "per month" : "per \(period.value) months"
        case .year:
            return period.value == 1 ? "per year" : "per \(period.value) years"
        @unknown default:
            return nil
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        // Mock products for preview
        Text("Subscription Options")
            .font(.headline)

        // In real usage, use actual Product objects
    }
    .padding()
}
