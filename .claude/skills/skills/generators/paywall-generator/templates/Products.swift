import Foundation

/// Product identifiers for in-app purchases.
///
/// Update these to match your App Store Connect configuration.
enum Products {

    // MARK: - Subscription Products

    /// Monthly subscription product ID.
    static let monthlySubscription = "com.yourapp.subscription.monthly"

    /// Yearly subscription product ID.
    static let yearlySubscription = "com.yourapp.subscription.yearly"

    /// Lifetime purchase product ID.
    static let lifetimePurchase = "com.yourapp.lifetime"

    // MARK: - Subscription Group

    /// The subscription group identifier.
    static let subscriptionGroupID = "your_subscription_group_id"

    // MARK: - All Products

    /// All product IDs to load.
    static let allProductIDs: Set<String> = [
        monthlySubscription,
        yearlySubscription,
        lifetimePurchase
    ]

    /// Only subscription product IDs.
    static let subscriptionProductIDs: Set<String> = [
        monthlySubscription,
        yearlySubscription
    ]
}

// MARK: - Product Display Names

extension Products {

    /// Display name for product ID.
    static func displayName(for productID: String) -> String {
        switch productID {
        case monthlySubscription:
            return "Monthly"
        case yearlySubscription:
            return "Yearly"
        case lifetimePurchase:
            return "Lifetime"
        default:
            return "Unknown"
        }
    }
}
