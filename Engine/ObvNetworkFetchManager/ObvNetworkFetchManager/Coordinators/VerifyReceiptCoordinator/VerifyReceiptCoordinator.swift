/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import ObvCrypto
import ObvTypes
import ObvMetaManager
import OlvidUtils

final class VerifyReceiptCoordinator: NSObject {
    
    fileprivate let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    fileprivate let logCategory = "VerifyReceiptCoordinator"

    var delegateManager: ObvNetworkFetchDelegateManager?

    private let localQueue = DispatchQueue(label: "VerifyReceiptCoordinatorQueue")
    private let queueForNotifications = OperationQueue()

    private var internalOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Queue for VerifyReceiptCoordinator operations"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private var currentTransactions = Set<String>()
    private var receiptToVerifyWhenNewSessionIsAvailable = [(ownedIdentity: ObvCryptoIdentity, receiptData: String, transactionIdentifier: String, flowId: FlowIdentifier)]()

}

// MARK: - Implementing VerifyReceiptDelegate

extension VerifyReceiptCoordinator: VerifyReceiptDelegate {
    
    func verifyReceipt(ownedIdentity: ObvCryptoIdentity, receiptData: String, transactionIdentifier: String, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        os_log("💰🌊 Call to verifyReceipt within flow %{public}@ for transaction identifier %{public}@", log: log, type: .info, flowId.debugDescription, transactionIdentifier)
            
        localQueue.async { [weak self] in

            guard let _self = self else { return }
            
            guard !_self.currentTransactions.contains(transactionIdentifier) else {
                assertionFailure()
                return
            }
            
            _self.currentTransactions.insert(transactionIdentifier)
            
            let op = VerifyReceiptOperation(identity: ownedIdentity,
                                            receiptData: receiptData,
                                            transactionIdentifier: transactionIdentifier,
                                            log: log,
                                            flowId: flowId,
                                            delegateManager: delegateManager,
                                            delegate: _self)
            _self.internalOperationQueue.addOperation(op)
            _self.internalOperationQueue.waitUntilAllOperationsAreFinished()
            os_log("💰 VerifyReceiptOperation is finished", log: log, type: .info)
            op.logReasonIfCancelled(log: log)
            
        }
        
    }
    
    
    func verifyReceiptsExpectingNewSesssion() {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("💰 The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        os_log("💰 Trying to verify receipts expecting a new server session...", log: log, type: .info)
        
        var receipts = [(ownedIdentity: ObvCryptoIdentity, receiptData: String, transactionIdentifier: String, flowId: FlowIdentifier)]()
        localQueue.sync { [weak self] in
            guard let _self = self else { return }
            receipts = _self.receiptToVerifyWhenNewSessionIsAvailable
            _self.receiptToVerifyWhenNewSessionIsAvailable.removeAll()
        }
        
        os_log("💰 We very the %d receipt(s) that were exepecting a new server session", log: log, type: .info, receipts.count)
        
        for receipt in receipts {
            verifyReceipt(ownedIdentity: receipt.ownedIdentity,
                          receiptData: receipt.receiptData,
                          transactionIdentifier: receipt.transactionIdentifier,
                          flowId: receipt.flowId)
        }
    }
}


// MARK: - Implementing VerifyReceiptOperationDelegate

extension VerifyReceiptCoordinator: VerifyReceiptOperationDelegate {
    
    func receiptVerificationFailed(ownedIdentity: ObvCryptoIdentity, transactionIdentifier: String, error: Error, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
            os_log("💰 The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        os_log("💰 Receipt verification failed for transaction with identifier %{public}@", log: log, type: .error, transactionIdentifier)

        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notificationDelegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        localQueue.async { [weak self] in
            guard let _self = self else { return }
            _ = _self.currentTransactions.remove(transactionIdentifier)
            os_log("💰 Receipt verification failed for transaction %{public}@: %{public}@", log: log, type: .error, transactionIdentifier, error.localizedDescription)
            ObvNetworkFetchNotificationNew.appStoreReceiptVerificationFailed(ownedIdentity: ownedIdentity, transactionIdentifier: transactionIdentifier, flowId: flowId)
                .postOnOperationQueue(operationQueue: _self.queueForNotifications, within: notificationDelegate)
        }
    }
    
    func receiptVerificationSucceededAndSubscriptionIsValid(ownedIdentity: ObvCryptoIdentity, transactionIdentifier: String, apiKey: UUID, flowId: FlowIdentifier) {

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
            os_log("💰 The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        os_log("💰 Receipt verification succeeded for transaction with identifier %{public}@ and the subscription is valid", log: log, type: .info, transactionIdentifier)

        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notificationDelegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        localQueue.async { [weak self] in
            guard let _self = self else { return }
            _ = _self.currentTransactions.remove(transactionIdentifier)
            os_log("💰 Receipt verification succeed for transaction %{public}@", log: log, type: .info, transactionIdentifier)
            ObvNetworkFetchNotificationNew.appStoreReceiptVerificationSucceededAndSubscriptionIsValid(ownedIdentity: ownedIdentity, transactionIdentifier: transactionIdentifier, apiKey: apiKey, flowId: flowId)
                .postOnOperationQueue(operationQueue: _self.queueForNotifications, within: notificationDelegate)
        }
    }
    
    
    func receiptVerificationSucceededButSubscriptionIsExpired(ownedIdentity: ObvCryptoIdentity, transactionIdentifier: String, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
            os_log("💰 The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        os_log("💰 Receipt verification succeeded for transaction with identifier %{public}@ but the subscription is expired", log: log, type: .error, transactionIdentifier)

        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notificationDelegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        localQueue.async { [weak self] in
            guard let _self = self else { return }
            _ = _self.currentTransactions.remove(transactionIdentifier)
            os_log("💰 Receipt verification succeed for transaction %{public}@ but the subscription is expired", log: log, type: .error, transactionIdentifier)
            ObvNetworkFetchNotificationNew.appStoreReceiptVerificationSucceededButSubscriptionIsExpired(ownedIdentity: ownedIdentity, transactionIdentifier: transactionIdentifier, flowId: flowId)
                .postOnOperationQueue(operationQueue: _self.queueForNotifications, within: notificationDelegate)
        }
    }
    
    func invalidSession(ownedIdentity: ObvCryptoIdentity, transactionIdentifier: String, receiptData: String, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
            os_log("💰 The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        localQueue.async { [weak self] in
            guard let _self = self else { return }
            _ = _self.currentTransactions.remove(transactionIdentifier)
            _self.receiptToVerifyWhenNewSessionIsAvailable.append((ownedIdentity, receiptData, transactionIdentifier, flowId))
            _self.queueForNotifications.addOperation { [weak self] in
                self?.createNewServerSession(ownedIdentity: ownedIdentity, delegateManager: delegateManager, flowId: flowId, log: log)
            }
        }
    }
    
    
    private func createNewServerSession(ownedIdentity: ObvCryptoIdentity, delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier, log: OSLog) {
        guard let contextCreator = delegateManager.contextCreator else { assertionFailure(); return }
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            guard let serverSession = try? ServerSession.get(within: obvContext, withIdentity: ownedIdentity) else {
                do {
                    try delegateManager.networkFetchFlowDelegate.serverSessionRequired(for: ownedIdentity, flowId: flowId)
                } catch {
                    os_log("Call to serverSessionRequired did fail", log: log, type: .fault)
                    assertionFailure()
                }
                return
            }
            
            guard let token = serverSession.token else {
                do {
                    try delegateManager.networkFetchFlowDelegate.serverSessionRequired(for: ownedIdentity, flowId: flowId)
                } catch {
                    os_log("Call to serverSessionRequired did fail", log: log, type: .fault)
                    assertionFailure()
                }
                return
            }
            
            do {
                try delegateManager.networkFetchFlowDelegate.serverSession(of: ownedIdentity, hasInvalidToken: token, flowId: flowId)
            } catch {
                os_log("Call to to serverSession(of: ObvCryptoIdentity, hasInvalidToken: Data, flowId: FlowIdentifier) did fail", log: log, type: .fault)
                assertionFailure()
            }
        }

    }

    
}
