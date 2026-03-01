# StoreKit 2 Patterns and Best Practices

## StoreKit 2 vs StoreKit 1

| Feature | StoreKit 1 | StoreKit 2 |
|---------|------------|------------|
| API Style | Delegate-based | Async/await |
| Transaction Verification | Manual | Built-in JWS |
| Subscription Status | Complex polling | Simple async |
| Testing | Limited | StoreKit Testing in Xcode |
| Minimum iOS | iOS 3+ | iOS 15+ |

## Core Concepts

### Products

```swift
// Load products
let productIDs = ["com.app.monthly", "com.app.yearly"]
let products = try await Product.products(for: productIDs)

// Product properties
for product in products {
    print(product.displayName)       // "Monthly Pro"
    print(product.displayPrice)      // "$4.99"
    print(product.subscription?.subscriptionPeriod)  // 1 month
}
```

### Transactions

```swift
// Purchase
let result = try await product.purchase()

switch result {
case .success(let verification):
    let transaction = try checkVerified(verification)
    await transaction.finish()  // Important!

case .userCancelled:
    break

case .pending:
    // Waiting for approval (Ask to Buy)
    break

@unknown default:
    break
}
```

### Transaction Verification

```swift
func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
    switch result {
    case .verified(let safe):
        return safe
    case .unverified(_, let error):
        throw StoreError.verificationFailed(error)
    }
}
```

## Subscription Status (iOS 18.4+)

### Using subscriptionStatusTask

```swift
@main
struct MyApp: App {
    @State private var status: SubscriptionStatus = .unknown

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.subscriptionStatus, status)
                .subscriptionStatusTask(for: "your.group.id") { statuses in
                    status = determineStatus(from: statuses)
                }
        }
    }
}

func determineStatus(from statuses: [Product.SubscriptionInfo.Status]) -> SubscriptionStatus {
    for status in statuses {
        switch status.state {
        case .subscribed:
            return .subscribed
        case .inGracePeriod:
            return .subscribed  // Still has access
        case .inBillingRetryPeriod:
            return .subscribed  // Still has access
        case .expired:
            continue  // Check other statuses
        case .revoked:
            continue
        default:
            continue
        }
    }
    return .notSubscribed
}
```

### Transaction.currentEntitlements (iOS 18.4+)

```swift
// New API for checking entitlements
for await result in Transaction.currentEntitlements(for: productID) {
    if case .verified(let transaction) = result {
        // User is entitled to this product
        print("Entitled via transaction: \(transaction.id)")
    }
}
```

## SubscriptionOfferView (iOS 18.4+)

### Basic Usage

```swift
// Simple subscription merchandising
SubscriptionOfferView(productID: "com.app.monthly")

// With custom icon
SubscriptionOfferView(productID: "com.app.monthly") {
    Image("premium_icon")
        .resizable()
        .frame(width: 40, height: 40)
}

// With detail action
SubscriptionOfferView(productID: "com.app.monthly")
    .subscriptionOfferViewDetailAction {
        showFullPaywall = true
    }
```

### Visible Relationship

```swift
// Show upgrade options for current subscribers
SubscriptionOfferView(groupID: "your.group.id", visibleRelationship: .upgrade)

// Options:
// .upgrade - Higher tier than current
// .downgrade - Lower tier
// .crossgrade - Equivalent tier
// .current - Current plan
// .all - All plans
```

## RenewalInfo (iOS 18.4+)

### Expiration Reasons

```swift
if let renewalInfo = status.renewalInfo,
   let reason = renewalInfo.expirationReason {
    switch reason {
    case .autoRenewDisabled:
        // User turned off auto-renew
        showWinBackOffer()

    case .billingError:
        // Payment failed
        promptToUpdatePaymentMethod()

    case .didNotConsentToPriceIncrease:
        // User declined price increase
        showSpecialOffer()

    case .productUnavailable:
        // Product no longer available
        break

    default:
        break
    }
}
```

## Paywall Design Patterns

### Subscription Comparison

```swift
struct PaywallView: View {
    let products: [Product]

    var body: some View {
        VStack(spacing: 20) {
            // Hero section
            VStack {
                Image(systemName: "crown.fill")
                    .font(.system(size: 60))
                Text("Unlock Premium")
                    .font(.largeTitle.bold())
            }

            // Plans
            ForEach(sortedProducts) { product in
                SubscriptionButton(
                    product: product,
                    isPopular: product.id.contains("yearly")
                )
            }

            // Features list
            FeaturesList()

            // Terms
            TermsAndPrivacyLinks()
        }
    }
}
```

### Popular Badge

```swift
struct SubscriptionButton: View {
    let product: Product
    let isPopular: Bool

    var body: some View {
        VStack {
            if isPopular {
                Text("MOST POPULAR")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange)
                    .cornerRadius(4)
            }

            // Plan details...
        }
    }
}
```

### Savings Calculation

```swift
func calculateSavings(monthly: Product, yearly: Product) -> Int? {
    guard let monthlyPrice = monthly.subscription?.price,
          let yearlyPrice = yearly.subscription?.price else {
        return nil
    }

    let yearlyIfMonthly = monthlyPrice * 12
    let savings = yearlyIfMonthly - yearlyPrice
    let percentage = (savings / yearlyIfMonthly) * 100

    return Int(percentage.rounded())
}
```

## Error Handling

### Purchase Errors

```swift
func purchase(_ product: Product) async {
    do {
        let result = try await product.purchase()
        // Handle result...
    } catch StoreKitError.userCancelled {
        // User cancelled - not an error
    } catch StoreKitError.notAvailableInStorefront {
        showError("Not available in your region")
    } catch StoreKitError.networkError {
        showError("Network error. Please try again.")
    } catch {
        showError("Purchase failed: \(error.localizedDescription)")
    }
}
```

## Restore Purchases

```swift
func restorePurchases() async {
    do {
        try await AppStore.sync()
        // Transactions will be delivered to Transaction.updates
    } catch {
        showError("Failed to restore: \(error.localizedDescription)")
    }
}
```

## Transaction Updates Listener

```swift
// Start on app launch
func listenForTransactions() -> Task<Void, Error> {
    Task.detached {
        for await result in Transaction.updates {
            do {
                let transaction = try self.checkVerified(result)
                await self.updateSubscriptionStatus()
                await transaction.finish()
            } catch {
                // Handle verification failure
            }
        }
    }
}
```

## Testing Best Practices

### StoreKit Configuration

```json
// Products.storekit
{
    "products": [
        {
            "id": "com.app.monthly",
            "type": "auto-renewable",
            "displayName": "Monthly",
            "price": 4.99,
            "subscriptionPeriod": "P1M"
        }
    ]
}
```

### Transaction Manager

- Debug > StoreKit > Transaction Manager
- Create transactions manually
- Test expiration, renewal, cancellation

### Time Acceleration

- StoreKit Testing accelerates time
- 1 month = 5 minutes (default)
- Test renewals quickly

## Anti-Patterns to Avoid

### Don't Forget to Finish Transactions

```swift
// Bad - transaction never finished
let result = try await product.purchase()
if case .success = result {
    unlockFeature()
}

// Good - always finish
let result = try await product.purchase()
if case .success(let verification) = result {
    let transaction = try checkVerified(verification)
    unlockFeature()
    await transaction.finish()  // Important!
}
```

### Don't Rely Only on Receipt

```swift
// Bad - checking receipt locally
if hasReceipt() { unlock() }

// Good - verify transaction
for await result in Transaction.currentEntitlements {
    if case .verified = result {
        unlock()
    }
}
```

### Don't Block UI on Product Load

```swift
// Bad - blocking
let products = try await Product.products(for: ids)
// Show UI

// Good - show loading state
struct PaywallView: View {
    @State private var products: [Product] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else {
                ProductList(products: products)
            }
        }
        .task {
            products = try await loadProducts()
            isLoading = false
        }
    }
}
```
