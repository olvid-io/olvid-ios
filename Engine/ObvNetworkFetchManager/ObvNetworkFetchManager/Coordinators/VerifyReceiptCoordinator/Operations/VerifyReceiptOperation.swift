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
import ObvServerInterface
import OlvidUtils


protocol VerifyReceiptOperationDelegate: AnyObject {
    func receiptVerificationFailed(ownedIdentity: ObvCryptoIdentity, transactionIdentifier: String, error: Error, flowId: FlowIdentifier)
    func receiptVerificationSucceededAndSubscriptionIsValid(ownedIdentity: ObvCryptoIdentity, transactionIdentifier: String, apiKey: UUID, flowId: FlowIdentifier)
    func receiptVerificationSucceededButSubscriptionIsExpired(ownedIdentity: ObvCryptoIdentity, transactionIdentifier: String, flowId: FlowIdentifier)
    func invalidSession(ownedIdentity: ObvCryptoIdentity, transactionIdentifier: String, receiptData: String, flowId: FlowIdentifier)
}


final class VerifyReceiptOperation: Operation {
    
    enum ReasonForCancel: LocalizedError {
        case dependencyCancelled
        case delegateManagerIsNotSet
        case delegateIsNotSet
        case contextCreatorIsNotSet
        case serverSessionRequired
        case failedToCreateTask(error: Error)
        
        var logType: OSLogType {
            switch self {
            case .dependencyCancelled, .serverSessionRequired:
                return .error
            case .delegateManagerIsNotSet, .delegateIsNotSet, .contextCreatorIsNotSet, .failedToCreateTask:
                return .fault
            }
        }
        
        var errorDescription: String? {
            switch self {
            case .dependencyCancelled: return "A dependency cancelled"
            case .delegateManagerIsNotSet: return "The delegate manager is not set"
            case .delegateIsNotSet: return "The delegate is not set"
            case .contextCreatorIsNotSet: return "The context creator is not set"
            case .serverSessionRequired: return "A new server session is required"
            case .failedToCreateTask(error: let error): return "Could not create task: \(error.localizedDescription)"
            }
        }

    }
    
    func logReasonIfCancelled(log: OSLog) {
        assert(isFinished)
        guard isCancelled else { return }
        guard let reason = self.reasonForCancel else {
            os_log("💰 %{public}@ cancelled without providing a reason. This is a bug", log: log, type: .fault, String(describing: self))
            assertionFailure()
            return
        }
        os_log("💰 %{public}@ cancelled: %{public}@", log: log, type: reason.logType, String(describing: self), reason.localizedDescription)
        assertionFailure()
    }

    private(set) var reasonForCancel: ReasonForCancel?
    
    private func cancel(withReason reason: ReasonForCancel) {
        assert(self.reasonForCancel == nil)
        self.reasonForCancel = reason
        self.cancel()
    }

    let identity: ObvCryptoIdentity
    let flowId: FlowIdentifier
    let receiptData: String
    let transactionIdentifier: String
    let log: OSLog
    weak var delegateManager: ObvNetworkFetchDelegateManager?
    weak var delegate: VerifyReceiptOperationDelegate?
    
    init(identity: ObvCryptoIdentity, receiptData: String, transactionIdentifier: String, log: OSLog, flowId: FlowIdentifier, delegateManager: ObvNetworkFetchDelegateManager, delegate: VerifyReceiptOperationDelegate) {
        self.delegateManager = delegateManager
        self.flowId = flowId
        self.identity = identity
        self.receiptData = receiptData
        self.transactionIdentifier = transactionIdentifier
        self.delegate = delegate
        self.log = log
        super.init()
    }
    
    override func main() {
        
        guard dependencies.filter({ $0.isCancelled }).isEmpty else {
            return cancel(withReason: .dependencyCancelled)
        }
        
        guard let delegateManager = delegateManager else {
            return cancel(withReason: .delegateManagerIsNotSet)
        }
        
        guard let delegate = delegate else {
            return cancel(withReason: .delegateIsNotSet)
        }

        guard let contextCreator = delegateManager.contextCreator else {
            return cancel(withReason: .contextCreatorIsNotSet)
        }
        
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
            guard let serverSession = try? ServerSession.get(within: obvContext, withIdentity: identity) else {
                return cancel(withReason: .serverSessionRequired)
            }
            
            guard let token = serverSession.token else {
                return cancel(withReason: .serverSessionRequired)
            }

            let verifyReceiptResult = VerifyReceiptResult(ownedIdentity: identity,
                                                          transactionIdentifier: transactionIdentifier,
                                                          receiptData: receiptData,
                                                          flowId: flowId,
                                                          delegate: delegate,
                                                          log: log)
            
            let method = VerifyReceiptMethod(ownedIdentity: identity,
                                             token: token,
                                             receiptData: receiptData,
                                             transactionIdentifier: transactionIdentifier,
                                             flowId: flowId)
            method.identityDelegate = delegateManager.identityDelegate
            
            let sessionConfiguration = URLSessionConfiguration.ephemeral
            let session = URLSession(configuration: sessionConfiguration, delegate: verifyReceiptResult, delegateQueue: nil)
            
            let task: URLSessionDataTask
            do {
                task = try method.dataTask(within: session)
            } catch {
                return cancel(withReason: .failedToCreateTask(error: error))
            }
            
            task.resume()
            
            session.finishTasksAndInvalidate()
            
        }
        
    }
    
}
