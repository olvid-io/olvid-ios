/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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


final class SubscriptionCoordinator: NSObject, SKPaymentTransactionObserver, SKProductsRequestDelegate {
    
    private static let allProductIdentifiers = Set(["io.olvid.premium_2020_monthly"])
            
    private let obvEngine: ObvEngine
    private var notificationTokens = [NSObjectProtocol]()
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: SubscriptionCoordinator.self))
    private var observationTokens = [NSObjectProtocol]()
    private var currentProductRequest: SKProductsRequest?
    private var currentPurchaseTransactionsSentToEngine = [String: SKPaymentTransaction]()
    private var numberOfTransactionsToRestore = 0
    private let internalQueue: OperationQueue = {
       let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "SubscriptionCoordinator internal queue"
        return queue
    }()
    
    init(obvEngine: ObvEngine) {
        self.obvEngine = obvEngine
        super.init()
        observeNotifications()
    }

    private func observeNotifications() {
        notificationTokens.append(ObvMessengerInternalNotification.observeUserRequestedAPIKeyStatus(queue: internalQueue, block: { [weak self] (ownedCryptoId, apiKey) in
            self?.obvEngine.queryAPIKeyStatus(for: ownedCryptoId, apiKey: apiKey)
        }))
        notificationTokens.append(ObvMessengerInternalNotification.observeUserRequestedNewAPIKeyActivation(queue: internalQueue) { [weak self] (ownedCryptoId, apiKey) in
            try? self?.obvEngine.setAPIKey(for: ownedCryptoId, apiKey: apiKey)
        })
        notificationTokens.append(SubscriptionNotification.observeUserRequestedListOfSKProducts { [weak self] in
            self?.processUserRequestedListOfSKProducts()
        })
        notificationTokens.append(SubscriptionNotification.observeUserRequestedToBuySKProduct { [weak self] (product) in
            self?.processUserRequestedToBuySKProduct(product: product)
        })
        notificationTokens.append(ObvEngineNotificationNew.observeAppStoreReceiptVerificationSucceededAndSubscriptionIsValid(within: NotificationCenter.default, queue: internalQueue) { [weak self] (ownedIdentity, transactionIdentifier) in
            self?.processAppStoreReceiptVerificationSucceededAndSubscriptionIsValidNotification(ownedIdentity: ownedIdentity, transactionIdentifier: transactionIdentifier)
        })
        notificationTokens.append(ObvEngineNotificationNew.observeAppStoreReceiptVerificationFailed(within: NotificationCenter.default, queue: internalQueue) { [weak self] (ownedIdentity, transactionIdentifier) in
            self?.processAppStoreReceiptVerificationFailedNotification(ownedIdentity: ownedIdentity, transactionIdentifier: transactionIdentifier)
        })
        notificationTokens.append(ObvEngineNotificationNew.observeAppStoreReceiptVerificationSucceededButSubscriptionIsExpired(within: NotificationCenter.default, queue: internalQueue) { [weak self] (ownedIdentity, transactionIdentifier) in
            self?.processAppStoreReceiptVerificationSucceededButSubscriptionIsExpiredNotification(ownedIdentity: ownedIdentity, transactionIdentifier: transactionIdentifier)
        })
        notificationTokens.append(SubscriptionNotification.observeUserRequestedToRestoreAppStorePurchases { [weak self] in
            self?.processUserRequestedToRestoreAppStorePurchasesNotification()
        })
    }
    
    // Called at an appropriate time by the MetaFlowController
    func listenToSKPaymentTransactions() {
        guard SKPaymentQueue.canMakePayments() else { return }
        SKPaymentQueue.default().add(self)
        observationTokens.append(NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: OperationQueue.main, using: { (_) in
            SKPaymentQueue.default().remove(self)
        }))
        
    }
    
    enum RequestedListOfSKProductsError: Error {
        case userCannotMakePayments
    }

    
    private func processUserRequestedListOfSKProducts() {
        
        os_log("💰 User requested a list of available SKProducts", log: log, type: .info)
        
        guard SKPaymentQueue.canMakePayments() else {
            os_log("💰 User is *not* allowed to make payments, returning an empty list of SKProducts", log: log, type: .error)
            SubscriptionNotification.newListOfSKProducts(result: .failure(.userCannotMakePayments))
                .postOnDispatchQueue()
            return
        }
        
        internalQueue.addOperation { [weak self] in
            guard self?.currentProductRequest == nil else { return }
            self?.currentProductRequest = SKProductsRequest(productIdentifiers: SubscriptionCoordinator.allProductIdentifiers)
            self?.currentProductRequest?.delegate = self
            self?.currentProductRequest?.start()
        }
        
    }
    
    
    private func processUserRequestedToBuySKProduct(product: SKProduct) {
        
        let log = self.log
        os_log("💰 User requested purchase of the SKProduct with identifier %{public}@", log: log, type: .info, product.productIdentifier)

        // We make sure there is only one owned identity for now
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            let ownedIdentities: [PersistedObvOwnedIdentity]
            do {
                ownedIdentities = try PersistedObvOwnedIdentity.getAll(within: context)
            } catch {
                assertionFailure(error.localizedDescription)
                return
            }
            guard ownedIdentities.count == 1 else { assertionFailure(); return }
            internalQueue.addOperation {
                let payment = SKMutablePayment(product: product)
                payment.quantity = 1
                os_log("💰 Adding the payment for SKProduct with identifier %{public}@ to the payment queue", log: log, type: .info, product.productIdentifier)
                SKPaymentQueue.default().add(payment)
            }
        }
    }
    
    
    private func processUserRequestedToRestoreAppStorePurchasesNotification() {
        os_log("💰 User requested to restore AppStore purchases", log: log, type: .info)
        internalQueue.addOperation { [weak self] in
            self?.numberOfTransactionsToRestore = 0
            let refresh = SKReceiptRefreshRequest()
            refresh.delegate = self
            refresh.start()
        }
    }
}


// MARK: - Implementing SKPaymentTransactionObserver

extension SubscriptionCoordinator {
    
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        
        os_log("💰 Receiving an updated transactions callback with %d transactions", log: log, type: .info, transactions.count)
        
        var originalTransactionsToRestore = [String: SKPaymentTransaction]()
        
        for transaction in transactions {

            os_log("💰 Updated transaction state is %{public}@", log: log, type: .info, transaction.transactionState.debugDescription)

            switch transaction.transactionState {
            case .purchasing:
                // Nothing to do
                break
            case .purchased:
                let op = ProcessPurchasedOperation(transaction: transaction, delegate: self)
                internalQueue.addOperation(op)
                internalQueue.waitUntilAllOperationsAreFinished()
                op.logReasonIfCancelled(log: log)
            case .restored:
                numberOfTransactionsToRestore += 1
                os_log("💰 Transaction to restore identified by %{public}@, transactionDate: %{public}@", log: log, type: .info, transaction.transactionIdentifier ?? "None", transaction.transactionDate?.debugDescription ?? "None")
                os_log("💰 Transaction to restore identified by %{public}@, original: %{public}@", log: log, type: .info, transaction.transactionIdentifier ?? "None", transaction.original?.debugDescription ?? "None")
                if let original = transaction.original, let transactionIdentifier = original.transactionIdentifier {
                    os_log("💰 Transaction to restore identified by %{public}@, original.transactionDate: %{public}@", log: log, type: .info, original.transactionIdentifier ?? "None", original.transactionDate?.debugDescription ?? "None")
                    originalTransactionsToRestore[transactionIdentifier] = original
                } else {
                    os_log("💰 Could not find the original transaction!")
                }
                queue.finishTransaction(transaction)
            case .failed:
                guard let error = transaction.error as? SKError else { assertionFailure(); return }
                switch error.code {
                case .paymentCancelled:
                    SubscriptionNotification.userDecidedToCancelToTheSKProductPurchase
                        .postOnDispatchQueue()
                default:
                    SubscriptionNotification.skProductPurchaseFailed(error: error)
                        .postOnDispatchQueue()
                }
            case .deferred:
                SubscriptionNotification.skProductPurchaseWasDeferred
                    .postOnDispatchQueue()
            @unknown default:
                assertionFailure()
            }
            
        }
        
        if !originalTransactionsToRestore.isEmpty {
            os_log("💰 We have found %d candidate(s) for the restore process. We Process it now", log: log, type: .info, originalTransactionsToRestore.count)
            for original in originalTransactionsToRestore.values {
                let op = ProcessPurchasedOperation(transaction: original, delegate: self)
                internalQueue.addOperation(op)
                internalQueue.waitUntilAllOperationsAreFinished()
                op.logReasonIfCancelled(log: log)
            }
        }
    }
    

    private func processAppStoreReceiptVerificationSucceededAndSubscriptionIsValidNotification(ownedIdentity: ObvCryptoId, transactionIdentifier: String) {
        assert(OperationQueue.current == internalQueue)
        assert(currentPurchaseTransactionsSentToEngine.keys.contains(transactionIdentifier))
        os_log("💰 The AppStore receipt was successfully verified by Olvid's server for the transaction identifier by %{public}@", log: log, type: .info, transactionIdentifier)
        if let transaction = currentPurchaseTransactionsSentToEngine.removeValue(forKey: transactionIdentifier) {
            os_log("💰 Finishing the transaction with identifier %{public}@", log: log, type: .info, transactionIdentifier)
            SKPaymentQueue.default().finishTransaction(transaction)
        } else {
            os_log("💰 Could not find the transaction with identifier %{public}@", log: log, type: .fault, transactionIdentifier)
        }
        if currentPurchaseTransactionsSentToEngine.isEmpty {
            SubscriptionNotification.allPurchaseTransactionsSentToEngineWereProcessed
                .postOnDispatchQueue()
        }
    }

    
    /// This happens when the server fails to process the receipt (most probably because it is invalid, or because of a bug).
    /// We do *not* finish the transaction in this case, but display an error message to the user, inviting her to cancel her subscription
    /// if the problem persists.
    private func processAppStoreReceiptVerificationFailedNotification(ownedIdentity: ObvCryptoId, transactionIdentifier: String) {
        assert(OperationQueue.current == internalQueue)
        assert(currentPurchaseTransactionsSentToEngine.keys.contains(transactionIdentifier))
        os_log("💰 The AppStore receipt with identifier by %{public}@ verification failed", log: log, type: .info, transactionIdentifier)
        _ = currentPurchaseTransactionsSentToEngine.removeValue(forKey: transactionIdentifier)
        if currentPurchaseTransactionsSentToEngine.isEmpty {
            SubscriptionNotification.allPurchaseTransactionsSentToEngineWereProcessed
                .postOnDispatchQueue()
        }
    }
    
    
    private func  processAppStoreReceiptVerificationSucceededButSubscriptionIsExpiredNotification(ownedIdentity: ObvCryptoId, transactionIdentifier: String) {
        os_log("💰 The AppStore receipt with identifier by %{public}@ verification succeed but the subscription has expired", log: log, type: .info, transactionIdentifier)
        if let transaction = currentPurchaseTransactionsSentToEngine.removeValue(forKey: transactionIdentifier) {
            os_log("💰 Finishing the transaction with identifier %{public}@", log: log, type: .info, transactionIdentifier)
            SKPaymentQueue.default().finishTransaction(transaction)
        } else {
            os_log("💰 Could not find the transaction with identifier %{public}@", log: log, type: .fault, transactionIdentifier)
        }
        if currentPurchaseTransactionsSentToEngine.isEmpty {
            SubscriptionNotification.allPurchaseTransactionsSentToEngineWereProcessed
                .postOnDispatchQueue()
        }
    }

}

// MARK: - PaymentOperationsDelegate and its implementation

protocol PaymentOperationsDelegate: AnyObject {
    func processAppStorePurchase(receiptData: String, transactionIdentifier: String, transaction: SKPaymentTransaction)
}


extension SubscriptionCoordinator: PaymentOperationsDelegate {
    
    func processAppStorePurchase(receiptData: String, transactionIdentifier: String, transaction: SKPaymentTransaction) {
        assert(OperationQueue.current == internalQueue)
        assert(!currentPurchaseTransactionsSentToEngine.keys.contains(transactionIdentifier))
        os_log("💰 Processing AppStore purchase transaction with identifier %{public}@", log: log, type: .info, transactionIdentifier)
        currentPurchaseTransactionsSentToEngine[transactionIdentifier] = transaction
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            let ownedIdentities: [PersistedObvOwnedIdentity]
            do {
                ownedIdentities = try PersistedObvOwnedIdentity.getAll(within: context)
            } catch {
                assertionFailure(error.localizedDescription)
                return
            }
            guard ownedIdentities.count == 1 else { assertionFailure(); return }
            os_log("💰 Sending the receipt data to the engine for verification. Transaction identifier is %{public}@", log: log, type: .info, transactionIdentifier, transactionIdentifier)
            obvEngine.processAppStorePurchase(for: ownedIdentities.first!.cryptoId, receiptData: receiptData, transactionIdentifier: transactionIdentifier)
        }
    }
}

// MARK: - Implementing SKProductsRequestDelegate

extension SubscriptionCoordinator {
    
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        internalQueue.addOperation { [weak self] in
            guard let _self = self else { return }
            guard _self.currentProductRequest != nil else { assertionFailure(); return }
            _self.currentProductRequest = nil
            assert(response.invalidProductIdentifiers.isEmpty)
            let products = response.products
            os_log("💰 New list of SKProduct is available with %d products.", log: _self.log, type: .info, products.count)
            SubscriptionNotification.newListOfSKProducts(result: .success(products))
                .postOnDispatchQueue()
        }
    }
    
    func requestDidFinish(_ request: SKRequest) {
        if request is SKReceiptRefreshRequest {
            // The only case when we perform an SKReceiptRefreshRequest is when we want to restore purhcases. We do this now.
            SKPaymentQueue.default().restoreCompletedTransactions()
        }
    }
    
    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        os_log("💰 Payment queue restore completed transactions finished", log: log, type: .info)
        if numberOfTransactionsToRestore == 0 {
            SubscriptionNotification.thereWasNoAppStorePurchaseToRestore
                .postOnDispatchQueue()
        }
    }
    
}


extension SKPaymentTransactionState: CustomDebugStringConvertible {
    
    public var debugDescription: String {
        switch self {
        case .deferred: return "deferred"
        case .failed: return "failed"
        case .purchased: return "purchased"
        case .purchasing: return "purchasing"
        case .restored: return "restored"
        @unknown default:
            return "unknown default"
        }
    }
    
}
