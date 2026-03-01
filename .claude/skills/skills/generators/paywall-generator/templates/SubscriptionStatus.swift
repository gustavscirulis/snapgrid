import Foundation
import StoreKit
import SwiftUI

/// Subscription status for the current user.
enum SubscriptionStatus: Sendable {
    case unknown
    case notSubscribed
    case subscribed
    case expired
    case inGracePeriod
    case inBillingRetry

    /// Whether user currently has access to premium features.
    var hasAccess: Bool {
        switch self {
        case .subscribed, .inGracePeriod, .inBillingRetry:
            return true
        case .unknown, .notSubscribed, .expired:
            return false
        }
    }
}

// MARK: - From StoreKit Status

extension SubscriptionStatus {

    /// Create from StoreKit subscription statuses.
    static func from(_ statuses: [Product.SubscriptionInfo.Status]) -> SubscriptionStatus {
        // Check each status in the group
        for status in statuses {
            switch status.state {
            case .subscribed:
                return .subscribed
            case .inGracePeriod:
                return .inGracePeriod
            case .inBillingRetryPeriod:
                return .inBillingRetry
            case .expired:
                continue  // Check other subscriptions
            case .revoked:
                continue
            default:
                continue
            }
        }

        // No active subscription found
        if statuses.contains(where: { $0.state == .expired }) {
            return .expired
        }

        return .notSubscribed
    }
}

// MARK: - Environment Key

private struct SubscriptionStatusKey: EnvironmentKey {
    static let defaultValue: SubscriptionStatus = .unknown
}

extension EnvironmentValues {
    /// Current subscription status.
    var subscriptionStatus: SubscriptionStatus {
        get { self[SubscriptionStatusKey.self] }
        set { self[SubscriptionStatusKey.self] = newValue }
    }
}

// MARK: - SwiftUI Usage Example

/*

 // In App.swift
 @main
 struct MyApp: App {
     @State private var subscriptionStatus: SubscriptionStatus = .unknown

     var body: some Scene {
         WindowGroup {
             ContentView()
                 .environment(\.subscriptionStatus, subscriptionStatus)
                 .subscriptionStatusTask(for: Products.subscriptionGroupID) { statuses in
                     subscriptionStatus = SubscriptionStatus.from(statuses)
                 }
         }
     }
 }

 // In any View
 struct FeatureView: View {
     @Environment(\.subscriptionStatus) var status

     var body: some View {
         if status.hasAccess {
             PremiumContent()
         } else {
             UpgradePrompt()
         }
     }
 }

 */
