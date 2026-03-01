import Foundation
import StoreKit

/// Manages StoreKit products and purchases.
///
/// Usage:
/// ```swift
/// let manager = StoreKitManager.shared
///
/// // Load products
/// await manager.loadProducts()
///
/// // Purchase
/// try await manager.purchase(product)
/// ```
@MainActor
@Observable
final class StoreKitManager {

    // MARK: - Singleton

    static let shared = StoreKitManager()

    // MARK: - State

    /// Available products loaded from App Store.
    private(set) var products: [Product] = []

    /// Currently purchased product IDs.
    private(set) var purchasedProductIDs: Set<String> = []

    /// Whether products are loading.
    private(set) var isLoading = false

    /// Any error that occurred.
    private(set) var error: StoreError?

    // MARK: - Transaction Listener

    private var transactionListener: Task<Void, Error>?

    // MARK: - Initialization

    private init() {
        transactionListener = listenForTransactions()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products

    /// Load products from the App Store.
    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            products = try await Product.products(for: Products.allProductIDs)
                .sorted { $0.price < $1.price }
            error = nil
        } catch {
            self.error = .productLoadFailed(error)
        }
    }

    // MARK: - Purchase

    /// Purchase a product.
    @discardableResult
    func purchase(_ product: Product) async throws -> Transaction? {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await updatePurchasedProducts()
            return transaction

        case .userCancelled:
            return nil

        case .pending:
            // Ask to Buy - transaction pending approval
            return nil

        @unknown default:
            return nil
        }
    }

    // MARK: - Restore Purchases

    /// Restore previous purchases.
    func restorePurchases() async throws {
        try await AppStore.sync()
        await updatePurchasedProducts()
    }

    // MARK: - Update Purchased Products

    /// Update the set of purchased product IDs.
    func updatePurchasedProducts() async {
        var purchased: Set<String> = []

        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.revocationDate == nil {
                    purchased.insert(transaction.productID)
                }
            }
        }

        purchasedProductIDs = purchased
    }

    // MARK: - Check if Purchased

    /// Check if a product is purchased.
    func isPurchased(_ productID: String) -> Bool {
        purchasedProductIDs.contains(productID)
    }

    /// Check if user has any active subscription.
    func hasActiveSubscription() -> Bool {
        !purchasedProductIDs.isEmpty
    }

    // MARK: - Private

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    await self.updatePurchasedProducts()
                    await transaction.finish()
                } catch {
                    // Transaction verification failed
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified(_, let error):
            throw StoreError.verificationFailed(error)
        }
    }
}

// MARK: - Convenience Properties

extension StoreKitManager {

    /// Monthly subscription product (if available).
    var monthlyProduct: Product? {
        products.first { $0.id == Products.monthlySubscription }
    }

    /// Yearly subscription product (if available).
    var yearlyProduct: Product? {
        products.first { $0.id == Products.yearlySubscription }
    }

    /// Lifetime purchase product (if available).
    var lifetimeProduct: Product? {
        products.first { $0.id == Products.lifetimePurchase }
    }

    /// Calculate savings percentage of yearly vs monthly.
    var yearlySavingsPercent: Int? {
        guard let monthly = monthlyProduct,
              let yearly = yearlyProduct else {
            return nil
        }

        let yearlyIfMonthly = monthly.price * 12
        let savings = yearlyIfMonthly - yearly.price
        let percent = (savings / yearlyIfMonthly) * 100

        return Int(percent.rounded())
    }
}

// MARK: - Errors

enum StoreError: Error, LocalizedError {
    case productLoadFailed(Error)
    case purchaseFailed(Error)
    case verificationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .productLoadFailed(let error):
            return "Failed to load products: \(error.localizedDescription)"
        case .purchaseFailed(let error):
            return "Purchase failed: \(error.localizedDescription)"
        case .verificationFailed(let error):
            return "Verification failed: \(error.localizedDescription)"
        }
    }
}
