/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
 *
 *  This file is part of Olvid for iOS.
 *
 *  Olvid is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License, version 3,
 *  as published by the Free Software Foundation.
 *
 *  Olvid is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with Olvid.  If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation
import Combine
import OSLog
import ObvEngine
import StoreKit
import ObvTypes
import ObvUICoreData
import ObvAppCoreConstants
import ObvSubscription
import ObvAppTypes


final class SubscriptionManager: NSObject, StoreKitDelegate {
    
    /// The order of the enum elements impacts the order they are displayed on the `OlvidShop` interface.
    enum ProductIdentifier: String, CaseIterable {
        case individualMonthly = "io.olvid.premium_2020_monthly"
        case familyMonthly = "io.olvid.subscription.family.monthly"
        case individualYearly = "io.olvid.subscription.individual.yearly"
        case familyYearly = "io.olvid.subscription.family.yearly"
        static var allProductIDs: [Product.ID] {
            Self.allCases.map { $0.rawValue }
        }
    }
            
    private let obvEngine: ObvEngine
    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: SubscriptionManager.self))
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: SubscriptionManager.self))
    
    private var updates: Task<Void, Never>? = nil

    init(obvEngine: ObvEngine) {
        self.obvEngine = obvEngine
        super.init()
    }
    
    deinit {
        updates?.cancel()
    }
    
    
    /// The currently active subscription for the user.
    ///
    /// This property holds the active `Product` representing the user's subscription.
    /// It is **not** set during app startup, but only after an explicit request to validate subscriptions.
    /// Specifically, it is populated **only if** the Olvid server returns `succeededAndSubscriptionIsValid`
    /// for all owned identities, which requires a network request.
    ///
    /// The value is updated dynamically in response to:
    /// - A successful subscription purchase by the user.
    /// - Validation of a subscription transaction (e.g., by a parent or guardian).
    ///
    /// Since all subscriptions currently belong to the same group, a single value is sufficient.
    /// If no active subscription exists or validation has not been requested, this property is `nil`.
    @Published var currentActiveSubscription: Product? = nil
    
    // Called at an appropriate time by the AppManagersHolder
    func listenToSKPaymentTransactions() {
        guard self.updates == nil else { return }
        Self.logger.info("💰 Will listen for transactions")
        self.updates = listenForTransactions()
    }
    
    
    private func listenForTransactions() -> Task<Void, Never> {
        return Task.detached {
            for await verificationResult in Transaction.updates {
                do {
                    Self.logger.info("💰 Will handle a transaction")
                    _ = try await self.handle(updatedTransaction: verificationResult, refreshSubscriptionStatusIfNecessary: false)
                    Self.logger.info("💰 The transaction was handled successfully.")
                } catch {
                    assertionFailure()
                    Self.logger.fault("💰 Could not handle the updated transaction: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
        
}


// MARK: - StoreKitDelegate

extension SubscriptionManager {
    
    /// Refreshes the user's subscription status by querying StoreKit for current entitlements, then Olvid's server.
    ///
    /// This method:
    /// 1. Fetches the latest entitlements from StoreKit.
    /// 2. If a valid subscription is found, contacts the server to validate it for all non-Keycloak-managed owned identities.
    ///
    /// This function is called:
    /// - When the user taps the refresh button.
    /// - When presenting the `OlvidShop` view, to ensure `currentActiveSubscription` is up-to-date
    ///   and the UI accurately reflects the user's current subscription.
    func refreshSubscriptionStatus() async throws -> [ObvAppTypes.StoreKitDelegatePurchaseResult] {
        
        Self.logger.debug("💰 Call to refreshSubscriptionStatus()")
        
        await checkForUnfinishedTransactions()
        
        /// We perform a finite "snapshot" of Transaction.currentEntitlements:
        /// - Collection runs inside a cancellable child Task.
        /// - After 5 seconds, we cancel that Task to avoid hanging indefinitely on devices where StoreKit
        ///   keeps the AsyncSequence open without yielding initial elements.
        /// - We then return whatever results were collected in that window.
        /// - If no items arrived before cancellation, we clear `currentActiveSubscription` and return [].
        let task = Task {
            var results = [StoreKitDelegatePurchaseResult]()
            Self.logger.debug("💰 Will loop over Transaction.currentEntitlements")
            for await verificationResult in Transaction.currentEntitlements {
                Self.logger.debug("💰 A verification result was returned")
                let result = try await handle(updatedTransaction: verificationResult, refreshSubscriptionStatusIfNecessary: false)
                results.append(result)
            }
            guard !Task.isCancelled else {
                Self.logger.warning("💰 The collector task of refreshSubscriptionStatus() was cancelled. Returning the \(results.count) results found so far.")
                return results
            }
            if results.isEmpty {
                await setCurrentActiveSubscription(productID: nil)
            }
            Self.logger.debug("💰 Returning the collected verification results. \(results.count) results returned.")
            return results
        }
        
        /// Enforce a 5-second timeout by cancelling the collector Task afterward.
        Task {
            try await Task.sleep(seconds: 5)
            task.cancel()
        }
        
        let results = try await task.value
        return results
        
    }
    
        
    func userRequestedListOfSKProducts() async throws -> [Product] {

        os_log("💰 User requested a list of available SKProducts", log: log, type: .info)
        
        guard SKPaymentQueue.canMakePayments() else {
            os_log("💰 User is *not* allowed to make payments, returning an empty list of SKProducts", log: log, type: .error)
            throw ObvError.userCannotMakePayments
        }
        
        let storeProducts = try await Product.products(for: ProductIdentifier.allProductIDs)
        
        return storeProducts

    }
    
    
    func userWantsToKnowIfMultideviceSubscriptionIsActive() async throws -> Bool {
        
        let storeProducts = try await userRequestedListOfSKProducts()
        
        for product in storeProducts {
            guard let subscription = product.subscription else { continue }
            guard productIncludesMultiDeviceSubScription(product) else { continue }
            let statuses = try await subscription.status
            for status in statuses {
                switch status.state {
                case .subscribed, .inBillingRetryPeriod, .inGracePeriod:
                    return true
                case .expired, .revoked:
                    continue
                default:
                    assertionFailure()
                    continue
                }
            }
        }
        
        return false
        
    }
    
    
    private func productIncludesMultiDeviceSubScription(_ product: Product) -> Bool {
        guard let productIdentifier = ProductIdentifier(rawValue: product.id) else {
            assertionFailure()
            return false
        }
        switch productIdentifier {
        case .individualMonthly,
                .individualYearly,
                .familyMonthly,
                .familyYearly:
            return true
        }
    }

    
    func userWantsToBuy(_ product: Product) async throws -> StoreKitDelegatePurchaseResult {

        Self.logger.info("💰 User requested purchase of the SKProduct with identifier \(product.id, privacy: .public)")
        
        // 2025-02-25: we used to make sure that the user had at least on active non-keycloak, non-hidden identity.
        // We don't do that anymore, since this method may be called during the first onboarding, while restoring a backup.
        
        // Proceed with the purchase
        
        Self.logger.info("💰 Will purchase product")
        let result = try await product.purchase()

        switch result {
            
        case .success(let verificationResult):
            
            Self.logger.info("💰 The result was .success. Will handle the transaction \(verificationResult.debugDescription, privacy: .public)")
            return try await handle(updatedTransaction: verificationResult, refreshSubscriptionStatusIfNecessary: true)
            
        case .userCancelled:
            // No need to throw
            Self.logger.info("💰 The user cancelled")
            return .userCancelled
            
        case .pending:
            // The purchase requires action from the customer (e.g., parents approval).
            // If the transaction completes, it's available through Transaction.updates.
            // To listen to these updates, we iterate over `SubscriptionManager.listenForTransactions()`.
            Self.logger.info("💰 The transaction is pending")
            return .pending
            
        @unknown default:
            Self.logger.info("💰 The transaction result is unknown")
            assertionFailure()
            return .userCancelled
        }
        
    }
    
    
    /// Called either when the user makes a purchase in the app, or when a transaction is obtained in `SubscriptionManager.listenForTransactions()`.
    private func handle(updatedTransaction verificationResult: VerificationResult<Transaction>, refreshSubscriptionStatusIfNecessary: Bool) async throws -> StoreKitDelegatePurchaseResult {
         
        Self.logger.info("💰 Will handle the updated transaction. We start by checking the transaction \(verificationResult.debugDescription, privacy: .public).")

        let (transaction, signedAppStoreTransactionAsJWS, state) = try await Self.checkVerified(verificationResult)
                
        Self.logger.info("💰 [\(transaction.id)] We did verify the transaction \(verificationResult.debugDescription, privacy: .public)")

        
        // Whatever happens, we always want to finish the transaction
        defer { Task {
            await transaction.finish()
        } }
        
        switch state {
        case .subscribed:
            Self.logger.info("💰 [\(transaction.id)] Transaction is subscribed")
            // We will process the purchase at the server level
            break
        case .expired:
            Self.logger.info("💰 [\(transaction.id)] Transaction is expired")
            // If a user resubscribes to a product they previously purchased, the transaction verification
            // may incorrectly return an expired state. To resolve this, we refresh the subscription status
            // during the purchase. If the refresh confirms a successful purchase (`purchaseSucceeded`),
            // we return that result; otherwise, we default to `.expired`.
            if refreshSubscriptionStatusIfNecessary {
                Self.logger.info("💰 [\(transaction.id)] Refresh the subscription status")
                let results = try await refreshSubscriptionStatus()
                for result in results {
                    switch result {
                    case .purchaseSucceeded:
                        return result
                    default:
                        continue
                    }
                }
            }
            return .expired
        case .inBillingRetryPeriod:
            Self.logger.info("💰 [\(transaction.id)] Transaction is inBillingRetryPeriod")
            // We will process the purchase at the server level
            break
        case .inGracePeriod:
            Self.logger.info("💰 [\(transaction.id)] Transaction is inGracePeriod")
            // We will process the purchase at the server level
            break
        case .revoked:
            Self.logger.info("💰 [\(transaction.id)] Transaction is revoked")
            return .revoked
        default:
            Self.logger.error("💰 [\(transaction.id)] Transaction is not dealt with state")
            assertionFailure("Add the missing case")
            // We will process the purchase at the server level
            break
        }
        
        // Make sure the transaction hasn't been refounded
        // (this check is probably unnecessary, has we already checked the state)
        
        guard transaction.revocationDate == nil else {
            Self.logger.info("💰 [\(transaction.id)] Transaction is revoked")
            return .revoked
        }
        
        // If the customer upgraded to a higher level of service (e.g., by subscribing to family plan),
        // we ignore the transaction
        
        guard !transaction.isUpgraded else {
            Self.logger.info("💰 [\(transaction.id)] Transaction is upgraded")
            return .isUpgraded
        }
        
        // In production and in sandbox, the server validates the signature
        
        Self.logger.info("💰 [\(transaction.id)] Will process the purchase at the engine level")
        let results = try await obvEngine.processAppStorePurchase(signedAppStoreTransactionAsJWS: signedAppStoreTransactionAsJWS, transactionIdentifier: transaction.id, environment: .init(environment: transaction.environment))
        Self.logger.info("💰 [\(transaction.id)] Did process the purchase at the engine level")

        // Since the same receipt data was used for all appropriate owned identities, we expect all results to be the same. Yet, we have to take into account exceptional circumstances ;-)
        // So we globally fail if any of the results is distinct from `.succeededAndSubscriptionIsValid`.
        
        if results.values.allSatisfy({ $0 == .succeededAndSubscriptionIsValid }) {
            
            Self.logger.info("💰 [\(transaction.id)] The AppStore receipt was successfully verified by Olvid's server")
            await setCurrentActiveSubscription(productID: transaction.productID)
            return .purchaseSucceeded(serverVerificationResult: .succeededAndSubscriptionIsValid)
            
        } else if results.values.first(where: { $0 == .succeededButSubscriptionIsExpired }) != nil {
            
            Self.logger.info("💰 [\(transaction.id)] The AppStore receipt verification succeeded but the subscription has expired")
            return .purchaseSucceeded(serverVerificationResult: .succeededButSubscriptionIsExpired)
            
        } else {
            
            Self.logger.info("💰 [\(transaction.id)] The AppStore receipt verification failed")
            return .purchaseSucceeded(serverVerificationResult: .failed)
            
        }


    }

    
    /// Part of the process allowing to determine whether the user should be notified about a recent Olvid+ subscription.
    ///
    /// This method checks for the presence of a valid, recent subscription to Olvid+. If such a subscription exists,
    /// it returns a value indicating the subscription's origin:
    ///
    /// - **`purchased`**: The subscription was made by the current user.
    /// - **`familyShared`**: The subscription is available due to a purchase by another family member (e.g., via Family Sharing).
    func getOwnershipTypeForTipNotificationOfJustMadeSubscription() async throws -> ObvOwnershipType? {
        var ownershipType: ObvOwnershipType?
        let storeProducts = try await Product.products(for: ProductIdentifier.allProductIDs)
        for product in storeProducts {
            let latestTransaction = await product.latestTransaction
            guard case .verified(let transaction) = latestTransaction else {
                // Ignore unverified transactions.
                continue
            }
            guard let subscriptionStatus: Product.SubscriptionInfo.Status = await transaction.subscriptionStatus else {
                continue
            }
            guard .subscribed == subscriptionStatus.state else {
                continue
            }
            assert(ownershipType == nil)
            switch transaction.ownershipType {
            case .purchased:
                ownershipType = product.isFamilyShareable ? .purchasedAndFamilyShareable : .purchasedButNotFamilyShareable
            case .familyShared:
                ownershipType = .familyShared
            default:
                assertionFailure()
                continue
            }
        }
        return ownershipType
    }
    
    
    func userWantsToRestorePurchases() async throws {
        try await AppStore.sync()
    }
    
    
    func getCurrentActiveSubscriptionPublisher() throws -> Published<Product?>.Publisher {
        return $currentActiveSubscription
    }
    
    func getCurrentActiveSubscription() throws -> Product? {
        return self.currentActiveSubscription
    }
    
}


// MARK: - Helpers

extension SubscriptionManager {
        
    private static func checkVerified(_ result: VerificationResult<Transaction>) async throws -> (transaction: Transaction, jwsRepresentation: String, state: Product.SubscriptionInfo.RenewalState?) {
        switch result {
        case .unverified:
            throw ObvError.failedVerification
        case .verified(let transaction):
            let jwsRepresentation = result.jwsRepresentation
            let state = await transaction.subscriptionStatus?.state
            return (transaction, jwsRepresentation, state)
        }
    }

    
    enum ObvError: LocalizedError {
        case transactionHasNoIdentifier
        case couldNotRetrieveAppStoreReceiptURL
        case thereIsNoFileAtTheURLIndicatedInTheTransaction
        case couldReadDataAtTheURLIndicatedInTheTransaction
        case userHasNoActiveIdentity
        case failedVerification
        case userCannotMakePayments
    }
    
    
    /// Adds the currently valid subscription to the `currentActiveSubscriptions` list.
    ///
    /// The `currentActiveSubscriptions` list is used by the UI to highlight which subscription is currently active.
    /// As all available subscriptions belong to the same group, this list is expected to contain at most one product.
    @MainActor
    private func setCurrentActiveSubscription(productID: Product.ID?) async {
        if let productID {
            do {
                guard let product = try await Product.products(for: [productID]).first else { assertionFailure(); return }
                self.currentActiveSubscription = product
            } catch {
                assertionFailure()
            }
        } else {
            self.currentActiveSubscription = nil
        }
    }

    
    private func checkForUnfinishedTransactions() async {
        Self.logger.debug("Checking for unfinished transactions")
        for await transaction in Transaction.unfinished {
            _ = try? await handle(updatedTransaction: transaction, refreshSubscriptionStatusIfNecessary: false)
        }
        Self.logger.debug("Finished checking for unfinished transactions")
    }

}


// MARK: - Private helper

private extension ObvTypes.ObvAppStoreEnvironment {
    
    init(environment: AppStore.Environment) {
        switch environment {
        case .production:
            self = .production
        case .xcode:
            self = .xcode
        case .sandbox:
            self = .sandbox
        default:
            assertionFailure()
            self = .production
        }
    }
    
}
