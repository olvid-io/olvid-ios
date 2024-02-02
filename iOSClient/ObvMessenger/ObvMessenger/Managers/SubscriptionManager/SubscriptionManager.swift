/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import os.log
import ObvEngine
import StoreKit
import ObvTypes
import ObvUICoreData


final class SubscriptionManager: NSObject, StoreKitDelegate {
    
    private static let allProductIdentifiers = Set(["io.olvid.premium_2020_monthly"])
            
    private let obvEngine: ObvEngine
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: SubscriptionManager.self))
    
    private var updates: Task<Void, Never>? = nil

    init(obvEngine: ObvEngine) {
        self.obvEngine = obvEngine
        super.init()
    }
    
    deinit {
        updates?.cancel()
    }


    // Called at an appropriate time by the AppManagersHolder
    func listenToSKPaymentTransactions() {
        guard SKPaymentQueue.canMakePayments() else { return }
        self.updates = listenForTransactions()
        
    }
    
    
    private func listenForTransactions() -> Task<Void, Never> {
        return Task(priority: .background) {
            for await verificationResult in Transaction.updates {
                do {
                    _ = try await self.handle(updatedTransaction: verificationResult)
                } catch {
                    assertionFailure()
                    os_log("💰 Could not handle the updated transaction: %{public}@", log: log, type: .fault, error.localizedDescription)
                }
            }
        }
    }
        
}


// MARK: - StoreKitDelegate

extension SubscriptionManager {
    
    func userRequestedListOfSKProducts() async throws -> [Product] {

        os_log("💰 User requested a list of available SKProducts", log: log, type: .info)
        
        guard SKPaymentQueue.canMakePayments() else {
            os_log("💰 User is *not* allowed to make payments, returning an empty list of SKProducts", log: log, type: .error)
            throw ObvError.userCannotMakePayments
        }
        
        let storeProducts = try await Product.products(for: SubscriptionManager.allProductIdentifiers)
        
        return storeProducts

    }

    
    func userWantsToBuy(_ product: Product) async throws -> StoreKitDelegatePurchaseResult {
        
        let log = self.log
        os_log("💰 User requested purchase of the SKProduct with identifier %{public}@", log: log, type: .info, product.id)
        
        // Make sure the user has at least one active (non-hidden) identity
        
        do {
            guard try await userHasAtLeastOneActiveNonKeycloakNonHiddenIdentity() else {
                os_log("💰 User requested a purchase but has no active non-hidden non-keycloak identity. Aborting.", log: log, type: .error)
                throw ObvError.userHasNoActiveIdentity
            }
        } catch {
            assertionFailure()
            os_log("💰 User requested a purchase but we could not check if she has at least one active non-hidden non-keycloak identity. Aborting", log: log, type: .error)
            throw ObvError.userHasNoActiveIdentity
        }
        
        // Proceed with the purchase
        
        let result = try await product.purchase()
        
        switch result {
            
        case .success(let verificationResult):
            
            return try await handle(updatedTransaction: verificationResult)
            
        case .userCancelled:
            // No need to throw
            return .userCancelled
            
        case .pending:
            // The purchase requires action from the customer (e.g., parents approval).
            // If the transaction completes,  it's available through Transaction.updates.
            // To listen to these updates, we iterate over `SubscriptionManager.listenForTransactions()`.
            return .pending
            
        @unknown default:
            assertionFailure()
            return .userCancelled
        }
        
    }
    
    
    /// Called either when the user makes a purchase in the app, or when a transaction is obtained in `SubscriptionManager.listenForTransactions()`.
    private func handle(updatedTransaction verificationResult: VerificationResult<Transaction>) async throws -> StoreKitDelegatePurchaseResult {
        
        let (transaction, signedAppStoreTransactionAsJWS) = try checkVerified(verificationResult)
        
        let results = try await obvEngine.processAppStorePurchase(signedAppStoreTransactionAsJWS: signedAppStoreTransactionAsJWS, transactionIdentifier: transaction.id)
        
        await transaction.finish()
        
        // Since the same receipt data was used for all appropriate owned identities, we expect all results to be the same. Yet, we have to take into account exceptional circumstances ;-)
        // So we globally fail if any of the results is distinct from `.succeededAndSubscriptionIsValid`.
        
        if results.values.allSatisfy({ $0 == .succeededAndSubscriptionIsValid }) {
            
            os_log("💰 The AppStore receipt was successfully verified by Olvid's server", log: log, type: .info)
            return .purchaseSucceeded(serverVerificationResult: .succeededAndSubscriptionIsValid)
            
        } else if results.values.first(where: { $0 == .succeededButSubscriptionIsExpired }) != nil {
            
            os_log("💰 The AppStore receipt verification succeeded but the subscription has expired", log: log, type: .info)
            return .purchaseSucceeded(serverVerificationResult: .succeededButSubscriptionIsExpired)
            
        } else {
            
            os_log("💰 The AppStore receipt verification failed", log: log, type: .error)
            return .purchaseSucceeded(serverVerificationResult: .failed)
            
        }


    }

    
    func userWantsToRestorePurchases() async throws {
        try await AppStore.sync()
    }
    
}


// MARK: - Helpers

extension SubscriptionManager {
        
    private func checkVerified(_ result: VerificationResult<Transaction>) throws -> (transaction: Transaction, jwsRepresentation: String) {
        switch result {
        case .unverified:
            throw ObvError.failedVerification
        case .verified(let signedType):
            let jwsRepresentation = result.jwsRepresentation
            return (signedType, jwsRepresentation)
        }
    }

    
    private func userHasAtLeastOneActiveNonKeycloakNonHiddenIdentity() async throws -> Bool {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    let count = try PersistedObvOwnedIdentity.countCryptoIdsOfAllActiveNonHiddenNonKeycloakOwnedIdentities(within: context)
                    continuation.resume(returning: count > 0)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
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
    
}
