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


/// A `VerifyReceiptResult` instance accumulates the data received by a `VerifyReceiptMethod`. It serves as a delegate of the URLSession
/// of the task. When the task is over, it calls an appropriate method on its delegate (which is the `VerifyReceiptCoordinator`)
final class VerifyReceiptResult: NSObject, URLSessionDataDelegate {
    
    let delegateQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "VerifyReceiptSessionDelegate queue"
        return queue
    }()
    
    let transactionIdentifier: String
    let ownedIdentity: ObvCryptoIdentity
    let receiptData: String
    let flowId: FlowIdentifier
    let log: OSLog
    private weak var delegate: VerifyReceiptOperationDelegate?
    
    private var receivedData = Data()
    
    deinit {
        debugPrint("VerifyReceiptResultDelegate deinit")
    }
    
    init(ownedIdentity: ObvCryptoIdentity, transactionIdentifier: String, receiptData: String, flowId: FlowIdentifier, delegate: VerifyReceiptOperationDelegate, log: OSLog) {
        self.ownedIdentity = ownedIdentity
        self.receiptData = receiptData
        self.flowId = flowId
        self.transactionIdentifier = transactionIdentifier
        self.delegate = delegate
        self.log = log
        super.init()
    }
        
    private static func makeError(message: String) -> Error { NSError(domain: "VerifyReceiptResult", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { VerifyReceiptResult.makeError(message: message) }
    
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        receivedData.append(data)
    }

    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        
        os_log("💰 URLSession task for AppStore receipt verification did complete", log: log, type: .info)
        
        guard error == nil else {
            assertionFailure()
            delegate?.receiptVerificationFailed(ownedIdentity: ownedIdentity, transactionIdentifier: transactionIdentifier, error: error!, flowId: flowId)
            return
        }
        
        // If we reach this point, the data task did complete without error
        
        guard let (status, returnedValues) = VerifyReceiptMethod.parseObvServerResponse(responseData: receivedData, using: log) else {
            let error = makeError(message: "Parsing error")
            delegate?.receiptVerificationFailed(ownedIdentity: ownedIdentity, transactionIdentifier: transactionIdentifier, error: error, flowId: flowId)
            assertionFailure()
            return
        }
        
        switch status {
        case .ok:
            os_log("💰 The server reported that the AppStore receipt received with transaction %{public}@ is valid", log: log, type: .info, transactionIdentifier)
            let apiKey = returnedValues!
            delegate?.receiptVerificationSucceededAndSubscriptionIsValid(ownedIdentity: ownedIdentity, transactionIdentifier: transactionIdentifier, apiKey: apiKey, flowId: flowId)
            return
            
        case .invalidSession:
            os_log("💰 The server session is invalid", log: log, type: .error)
            delegate?.invalidSession(ownedIdentity: ownedIdentity, transactionIdentifier: transactionIdentifier, receiptData: receiptData, flowId: flowId)
            return
            
        case .receiptIsExpired:
            os_log("💰 The server reported that the receipt has expired for transaction identifier %{public}@ is invalid", log: log, type: .error, transactionIdentifier)
            delegate?.receiptVerificationSucceededButSubscriptionIsExpired(ownedIdentity: ownedIdentity, transactionIdentifier: transactionIdentifier, flowId: flowId)
            return

        case .generalError:
            os_log("💰 The server reported a general error", log: log, type: .fault)
            let error = makeError(message: "The server reported a general error")
            delegate?.receiptVerificationFailed(ownedIdentity: ownedIdentity, transactionIdentifier: transactionIdentifier, error: error, flowId: flowId)
            return
        }
        
    }
}
