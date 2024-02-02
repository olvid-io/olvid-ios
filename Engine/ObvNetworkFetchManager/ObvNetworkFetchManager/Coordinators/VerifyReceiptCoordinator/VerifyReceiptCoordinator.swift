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
import ObvCrypto
import ObvTypes
import ObvMetaManager
import OlvidUtils
import ObvServerInterface


actor VerifyReceiptCoordinator {
    
    private static let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    private static let logCategory = "VerifyReceiptCoordinator"
    private static var log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)

    weak var delegateManager: ObvNetworkFetchDelegateManager?

    init(logPrefix: String) {
        let logSubsystem = "\(logPrefix).\(Self.defaultLogSubsystem)"
        Self.log = OSLog(subsystem: logSubsystem, category: Self.logCategory)
    }

    private enum VerificationTask {
        case inProgress(Task<[ObvCryptoIdentity : ObvAppStoreReceipt.VerificationStatus], Never>)
    }

    private var cache = [ObvAppStoreReceipt: VerificationTask]()

}

// MARK: - Implementing VerifyReceiptDelegate

extension VerifyReceiptCoordinator: VerifyReceiptDelegate {
    
    func verifyReceipt(appStoreReceiptElements: ObvAppStoreReceipt, flowId: FlowIdentifier) async throws -> [ObvCryptoIdentity : ObvAppStoreReceipt.VerificationStatus] {
        
        let requestUUID = UUID()

        os_log("💰[%{public}@] Call to verifyReceipt", log: Self.log, type: .info, requestUUID.debugDescription)

        let result = try await verifyReceipt(appStoreReceiptElements: appStoreReceiptElements, flowId: flowId, requestUUID: requestUUID)
        
        os_log("💰[%{public}@] End if call to verifyReceipt", log: Self.log, type: .info, requestUUID.debugDescription)

        return result
        
    }
    
    
    private func verifyReceipt(appStoreReceiptElements: ObvAppStoreReceipt, flowId: FlowIdentifier, requestUUID: UUID) async throws -> [ObvCryptoIdentity : ObvAppStoreReceipt.VerificationStatus] {
        
        return try await requestAppStoreReceiptVerificationFromServer(
            appStoreReceiptElements: appStoreReceiptElements,
            flowId: flowId,
            requestUUID: requestUUID)

    }

    
    private func requestAppStoreReceiptVerificationFromServer(appStoreReceiptElements: ObvAppStoreReceipt, flowId: FlowIdentifier, requestUUID: UUID) async throws -> [ObvCryptoIdentity : ObvAppStoreReceipt.VerificationStatus] {
        
        if let cached = cache[appStoreReceiptElements] {
            switch cached {
            case .inProgress(let task):
                os_log("💰[%{public}@] Cache hit: in progress", log: Self.log, type: .info, requestUUID.debugDescription)
                return await task.value
            }
        }
        
        os_log("💰[%{public}@] Not in cache", log: Self.log, type: .info, requestUUID.debugDescription)

        let task = try createTaskAllowingToVerifyReceiptForAllIdentities(appStoreReceiptElements: appStoreReceiptElements, flowId: flowId)
        
        cache[appStoreReceiptElements] = .inProgress(task)

        os_log("💰[%{public}@] In progress", log: Self.log, type: .info, requestUUID.debugDescription)
        
        let results = await task.value
        cache.removeValue(forKey: appStoreReceiptElements)
        return results

    }
    
    
    /// Returns a task that, on execution, performs one `VerifyReceiptServerMethod` for each owned identity indicated in the receipt elements.
    /// All the verifications are performed in parallel, and the same receipt is used for each owned identity.
    /// The task never throws, and returns a dictionary mapping each owned identity to a Boolean indicating whether the receipt verification was successful (`true`) or not (`false`).
    private func createTaskAllowingToVerifyReceiptForAllIdentities(appStoreReceiptElements: ObvAppStoreReceipt, flowId: FlowIdentifier) throws -> Task<[ObvCryptoIdentity : ObvAppStoreReceipt.VerificationStatus], Never> {
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.theIdentityDelegateIsNotSet
        }

        let ownedCryptoIdentities = appStoreReceiptElements.ownedCryptoIdentities
        let signedAppStoreTransactionAsJWS = appStoreReceiptElements.signedAppStoreTransactionAsJWS

        return Task {
            
            return await withTaskGroup(of: (ObvCryptoIdentity, ObvAppStoreReceipt.VerificationStatus).self) { group in
                
                for ownedCryptoIdentity in ownedCryptoIdentities {
                    
                    group.addTask {
                        
                        let verificationStatus: ObvAppStoreReceipt.VerificationStatus
                        
                        do {
                            
                            let serverSessionToken = try await delegateManager.serverSessionDelegate.getValidServerSessionToken(for: ownedCryptoIdentity, currentInvalidToken: nil, flowId: flowId).serverSessionToken
                            
                            let method = VerifyReceiptServerMethod(
                                ownedIdentity: ownedCryptoIdentity,
                                token: serverSessionToken,
                                signedAppStoreTransactionAsJWS: signedAppStoreTransactionAsJWS,
                                identityDelegate: identityDelegate,
                                flowId: flowId)
                            
                            let (data, response) = try await URLSession.shared.data(for: method.getURLRequest())
                            
                            guard let httpResponse = response as? HTTPURLResponse,
                                  httpResponse.statusCode == 200 else {
                                throw ObvError.invalidServerResponse
                            }
                            
                            let result = VerifyReceiptServerMethod.parseObvServerResponse(responseData: data, using: Self.log)
                            
                            switch result {
                            case .failure:
                                throw ObvError.couldNotParseReturnStatusFromServer
                            case .success(let returnStatus):
                                switch returnStatus {
                                case .ok(apiKey: _):
                                    verificationStatus = .succeededAndSubscriptionIsValid
                                case .invalidSession:
                                    throw ObvError.serverReportedInvalidSession
                                case .receiptIsExpired:
                                    verificationStatus = .succeededButSubscriptionIsExpired
                                case .generalError:
                                    throw ObvError.serverReportedGeneralError
                                }
                            }
                            
                        } catch {
                            assertionFailure(error.localizedDescription)
                            verificationStatus = .failed
                        }
                        
                        return (ownedCryptoIdentity, verificationStatus)
                        
                    } // end of group.addTask
                                        
                } // end of for ownedCryptoIdentity in ownedCryptoIdentities loop
                
                var results = [ObvCryptoIdentity: ObvAppStoreReceipt.VerificationStatus]()
                for await (ownedCryptoIdentity, verificationStatus) in group {
                    results[ownedCryptoIdentity] = verificationStatus
                }
                return results

            }
            
        }
        
    }
    
    
    func setDelegateManager(_ delegateManager: ObvNetworkFetchDelegateManager) {
        self.delegateManager = delegateManager
    }

    
//    func verifyReceipt(ownedCryptoIdentities: [ObvCryptoIdentity], receiptData: String, transactionIdentifier: String, flowId: FlowIdentifier) {
//
//        guard let delegateManager = delegateManager else {
//            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
//            os_log("The Delegate Manager is not set", log: log, type: .fault)
//            assertionFailure()
//            return
//        }
//
//        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
//
//        os_log("💰🌊 Call to verifyReceipt within flow %{public}@ for transaction identifier %{public}@", log: log, type: .info, flowId.debugDescription, transactionIdentifier)
//
//        localQueue.async { [weak self] in
//
//            guard let _self = self else { return }
//
//            guard !_self.currentTransactions.contains(transactionIdentifier) else {
//                assertionFailure()
//                return
//            }
//
//            _self.currentTransactions.insert(transactionIdentifier)
//
//            let ops = ownedCryptoIdentities.map({
//                VerifyReceiptOperation(identity: $0,
//                                       receiptData: receiptData,
//                                       transactionIdentifier: transactionIdentifier,
//                                       log: log,
//                                       flowId: flowId,
//                                       delegateManager: delegateManager,
//                                       delegate: _self)            })
//            _self.internalOperationQueue.addOperations(ops, waitUntilFinished: true)
//            os_log("💰 VerifyReceiptOperation is finished", log: log, type: .info)
//            for op in ops {
//                op.logReasonIfCancelled(log: log)
//            }
//
//        }
//
//    }
    
    
//    func verifyReceiptsExpectingNewSesssion() {
//
//        guard let delegateManager = delegateManager else {
//            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
//            os_log("💰 The Delegate Manager is not set", log: log, type: .fault)
//            assertionFailure()
//            return
//        }
//
//        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
//
//        os_log("💰 Trying to verify receipts expecting a new server session...", log: log, type: .info)
//
//        var receipts = [(ownedIdentity: ObvCryptoIdentity, receiptData: String, transactionIdentifier: String, flowId: FlowIdentifier)]()
//        localQueue.sync { [weak self] in
//            guard let _self = self else { return }
//            receipts = _self.receiptToVerifyWhenNewSessionIsAvailable
//            _self.receiptToVerifyWhenNewSessionIsAvailable.removeAll()
//        }
//
//        os_log("💰 We verify the %d receipt(s) that were exepecting a new server session", log: log, type: .info, receipts.count)
//
//        for receipt in receipts {
//            verifyReceipt(ownedCryptoIdentities: [receipt.ownedIdentity],
//                          receiptData: receipt.receiptData,
//                          transactionIdentifier: receipt.transactionIdentifier,
//                          flowId: receipt.flowId)
//        }
//    }
}


// MARK: - Implementing VerifyReceiptOperationDelegate

//extension VerifyReceiptCoordinator: VerifyReceiptOperationDelegate {
//
//    func receiptVerificationFailed(ownedIdentity: ObvCryptoIdentity, transactionIdentifier: String, error: Error, flowId: FlowIdentifier) {
//
//        guard let delegateManager = delegateManager else {
//            let log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
//            os_log("💰 The Delegate Manager is not set", log: log, type: .fault)
//            assertionFailure()
//            return
//        }
//
//        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
//
//        os_log("💰 Receipt verification failed for transaction with identifier %{public}@", log: log, type: .error, transactionIdentifier)
//
//        guard let notificationDelegate = delegateManager.notificationDelegate else {
//            os_log("The notificationDelegate is not set", log: log, type: .fault)
//            assertionFailure()
//            return
//        }
//
//        localQueue.async { [weak self] in
//            guard let _self = self else { return }
//            _ = _self.currentTransactions.remove(transactionIdentifier)
//            os_log("💰 Receipt verification failed for transaction %{public}@: %{public}@", log: log, type: .error, transactionIdentifier, error.localizedDescription)
//            ObvNetworkFetchNotificationNew.appStoreReceiptVerificationFailed(ownedIdentity: ownedIdentity, transactionIdentifier: transactionIdentifier, flowId: flowId)
//                .postOnBackgroundQueue(_self.queueForNotifications, within: notificationDelegate)
//        }
//    }
//
//    func receiptVerificationSucceededAndSubscriptionIsValid(ownedIdentity: ObvCryptoIdentity, transactionIdentifier: String, apiKey: UUID, flowId: FlowIdentifier) {
//
//        guard let delegateManager = delegateManager else {
//            let log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
//            os_log("💰 The Delegate Manager is not set", log: log, type: .fault)
//            return
//        }
//
//        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
//
//        os_log("💰 Receipt verification succeeded for transaction with identifier %{public}@ and the subscription is valid", log: log, type: .info, transactionIdentifier)
//
//        guard let notificationDelegate = delegateManager.notificationDelegate else {
//            os_log("The notificationDelegate is not set", log: log, type: .fault)
//            assertionFailure()
//            return
//        }
//
//        localQueue.async { [weak self] in
//            guard let _self = self else { return }
//            _ = _self.currentTransactions.remove(transactionIdentifier)
//            os_log("💰 Receipt verification succeed for transaction %{public}@", log: log, type: .info, transactionIdentifier)
//            ObvNetworkFetchNotificationNew.appStoreReceiptVerificationSucceededAndSubscriptionIsValid(ownedIdentity: ownedIdentity, transactionIdentifier: transactionIdentifier, apiKey: apiKey, flowId: flowId)
//                .postOnBackgroundQueue(_self.queueForNotifications, within: notificationDelegate)
//        }
//    }
//
//
//    func receiptVerificationSucceededButSubscriptionIsExpired(ownedIdentity: ObvCryptoIdentity, transactionIdentifier: String, flowId: FlowIdentifier) {
//
//        guard let delegateManager = delegateManager else {
//            let log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
//            os_log("💰 The Delegate Manager is not set", log: log, type: .fault)
//            return
//        }
//
//        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
//
//        os_log("💰 Receipt verification succeeded for transaction with identifier %{public}@ but the subscription is expired", log: log, type: .error, transactionIdentifier)
//
//        guard let notificationDelegate = delegateManager.notificationDelegate else {
//            os_log("The notificationDelegate is not set", log: log, type: .fault)
//            assertionFailure()
//            return
//        }
//
//        localQueue.async { [weak self] in
//            guard let _self = self else { return }
//            _ = _self.currentTransactions.remove(transactionIdentifier)
//            os_log("💰 Receipt verification succeed for transaction %{public}@ but the subscription is expired", log: log, type: .error, transactionIdentifier)
//            ObvNetworkFetchNotificationNew.appStoreReceiptVerificationSucceededButSubscriptionIsExpired(ownedIdentity: ownedIdentity, transactionIdentifier: transactionIdentifier, flowId: flowId)
//                .postOnBackgroundQueue(_self.queueForNotifications, within: notificationDelegate)
//        }
//    }
//
//    func invalidSession(ownedIdentity: ObvCryptoIdentity, transactionIdentifier: String, receiptData: String, flowId: FlowIdentifier) {
//
//        guard let delegateManager = delegateManager else {
//            let log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
//            os_log("💰 The Delegate Manager is not set", log: log, type: .fault)
//            return
//        }
//
//        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
//
//        localQueue.async { [weak self] in
//            guard let _self = self else { return }
//            _ = _self.currentTransactions.remove(transactionIdentifier)
//            _self.receiptToVerifyWhenNewSessionIsAvailable.append((ownedIdentity, receiptData, transactionIdentifier, flowId))
//            _self.queueForNotifications.async { [weak self] in
//                self?.createNewServerSession(ownedIdentity: ownedIdentity, delegateManager: delegateManager, flowId: flowId, log: log)
//            }
//        }
//    }
//
//
//    private func createNewServerSession(ownedIdentity: ObvCryptoIdentity, delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier, log: OSLog) {
//        guard let contextCreator = delegateManager.contextCreator else { assertionFailure(); return }
//        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
//            guard let serverSession = try? ServerSession.get(within: obvContext.context, withIdentity: ownedIdentity), let token = serverSession.token else {
//                Task.detached {
//                    do {
//                        _ = try await delegateManager.networkFetchFlowDelegate.getValidServerSessionToken(for: ownedIdentity, currentInvalidToken: nil, flowId: flowId)
//                    } catch {
//                        os_log("Call to getValidServerSessionToken did fail", log: log, type: .fault)
//                        assertionFailure()
//                    }
//                }
//                return
//            }
//
//            Task.detached {
//                do {
//                    _ = try await delegateManager.networkFetchFlowDelegate.getValidServerSessionToken(for: ownedIdentity, currentInvalidToken: token, flowId: flowId)
//                } catch {
//                    os_log("Call to getValidServerSessionToken did fail", log: log, type: .fault)
//                    assertionFailure()
//                }
//            }
//        }
//
//    }
//
//
//
//
//}


// MARK: - Errors

extension VerifyReceiptCoordinator {
    
    enum ObvError: LocalizedError {
        case theDelegateManagerIsNotSet
        case theIdentityDelegateIsNotSet
        case invalidServerResponse
        case couldNotParseReturnStatusFromServer
        case serverReportedInvalidSession
        case serverReportedReceiptIsExpired
        case serverReportedGeneralError
        
        var errorDescription: String? {
            switch self {
            case .theDelegateManagerIsNotSet:
                return "The delegate manager is not set"
            case .invalidServerResponse:
                return "Invalid server response"
            case .couldNotParseReturnStatusFromServer:
                return "Could not parse return status from server"
            case .serverReportedInvalidSession:
                return "Server reported an invalid session"
            case .serverReportedReceiptIsExpired:
                return "Server reported that the receipt expired"
            case .serverReportedGeneralError:
                return "Server reported a general error"
            case .theIdentityDelegateIsNotSet:
                return "The identity delegate is not set"
            }
        }
    }
    
}
