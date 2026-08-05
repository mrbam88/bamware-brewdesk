import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class SubscriptionStore {
    private enum Key {
        static let developmentAccess = "cafe.subscription.development-access"
    }

    private let productIDs: Set<String>
    private(set) var products: [Product] = []
    private(set) var hasProAccess = false
    private(set) var isLoading = true
    private(set) var isPurchasing = false
    private(set) var errorMessage: String?
    private var updatesTask: Task<Void, Never>?

    init(configuration: AppConfiguration) {
        productIDs = [configuration.monthlyProductID, configuration.annualProductID]
        #if DEBUG
        hasProAccess = UserDefaults.standard.bool(forKey: Key.developmentAccess)
        #endif

        updatesTask = Task { [weak self] in
            for await _ in Transaction.updates {
                await self?.refreshEntitlements()
            }
        }
    }

    func prepare() async {
        defer { isLoading = false }
        do {
            products = try await Product.products(for: productIDs)
                .sorted { $0.price < $1.price }
            await refreshEntitlements()
        } catch {
            errorMessage = "Plans are temporarily unavailable."
        }
    }

    func purchase(_ product: Product) async {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verified(verification)
                await transaction.finish()
                await refreshEntitlements()
            case .pending:
                errorMessage = "Your purchase is pending approval."
            case .userCancelled:
                break
            @unknown default:
                errorMessage = "The purchase could not be completed."
            }
        } catch {
            errorMessage = "The purchase could not be completed."
        }
    }

    func restore() async {
        errorMessage = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !hasProAccess { errorMessage = "No active subscription was found." }
        } catch {
            errorMessage = "Purchases could not be restored."
        }
    }

    #if DEBUG
    func grantDevelopmentAccess() {
        UserDefaults.standard.set(true, forKey: Key.developmentAccess)
        hasProAccess = true
    }
    #endif

    private func refreshEntitlements() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? verified(result),
                  productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else {
                continue
            }
            entitled = true
        }
        #if DEBUG
        entitled = entitled || UserDefaults.standard.bool(forKey: Key.developmentAccess)
        #endif
        hasProAccess = entitled
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): value
        case .unverified: throw StoreError.failedVerification
        }
    }
}

private enum StoreError: Error {
    case failedVerification
}
