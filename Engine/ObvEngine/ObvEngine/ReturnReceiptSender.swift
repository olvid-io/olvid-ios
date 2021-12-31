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
import ObvCrypto
import ObvEncoder
import ObvServerInterface
import os.log
import ObvMetaManager
import ObvTypes
import OlvidUtils


final class ReturnReceiptSender: NSObject {
    
    private static let backgroundURLSessionIdentifierPrefix = "io.olvid.post-return-receipt-"
    private let sharedContainerIdentifier: String
    private let sessionIdentifier: String
    private let prng: PRNGService
    private var data = Data()
    private let delegateQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "ReturnReceiptSender delegate queue"
        return queue
    }()
    
    weak var identityDelegate: ObvIdentityDelegate?
    
    private lazy var session: URLSession = ReturnReceiptSender.backgroundURLSessionWithIdentifier(self.sessionIdentifier, urlSessionDelegate: self, sharedContainerIdentifier: self.sharedContainerIdentifier, delegateQueue: self.delegateQueue)

    
    /// Used to store the completion handler sent by UIKit
    private var completionHandler: (() -> Void)?

    public var logSubsystem: String = ObvEngine.defaultLogSubsystem
    public func prependLogSubsystem(with prefix: String) {
        logSubsystem = "\(prefix).\(logSubsystem)"
    }
    private lazy var log = OSLog(subsystem: logSubsystem, category: String(describing: ReturnReceiptSender.self))
    
    private var receivedDataForTask = [URLSessionTask: Data]()
    
    init(sharedContainerIdentifier: String, prng: PRNGService) {
        self.sharedContainerIdentifier = sharedContainerIdentifier
        self.sessionIdentifier = ReturnReceiptSender.generateSessionIdentifier()
        self.prng = prng
        super.init()
    }
    
    
    private static func generateSessionIdentifier() -> String {
        return [backgroundURLSessionIdentifierPrefix, UUID().uuidString].joined(separator: "_")
    }

    
    private static let errorDomain = String(describing: ReturnReceiptSender.self)

    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    
    private static func backgroundURLSessionWithIdentifier(_ sessionIdentifier: String, urlSessionDelegate: URLSessionDelegate, sharedContainerIdentifier: String, delegateQueue queue: OperationQueue?) -> URLSession {
        let sc = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        sc.waitsForConnectivity = true
        sc.isDiscretionary = false
        sc.sharedContainerIdentifier = sharedContainerIdentifier
        let session = URLSession(configuration: sc, delegate: urlSessionDelegate, delegateQueue: queue)
        return session
    }


    /// This method returns a 16 bytes nonce and a serialized encryption key. This is called when sending a message, in order to make it
    /// possible to have a return receipt back.
    func generateReturnReceiptElements() -> (nonce: Data, key: Data) {
        let nonce = prng.genBytes(count: 16)
        let authenticatedEncryptionKey = ObvCryptoSuite.sharedInstance.authenticatedEncryption().generateKey(with: prng)
        let key = authenticatedEncryptionKey.encode().rawData
        return (nonce, key)
    }

    
    func postReturnReceiptWithElements(_ elements: (nonce: Data, key: Data), andStatus status: Int, to contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId, withDeviceUids deviceUids: Set<UID>) throws {
        
        guard let identityDelegate = self.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            assertionFailure()
            throw ReturnReceiptSender.makeError(message: "The identity delegate is not set")
        }
        
        let ownedIdentity = ownedCryptoId.cryptoIdentity.getIdentity()
        let payload = [ownedIdentity, status].encode().rawData
        guard let encodedKey = ObvEncoded(withRawData: elements.key) else {
            throw ReturnReceiptSender.makeError(message: "Could not decode key in elements")
        }
        let authenticatedEncryptionKey = try AuthenticatedEncryptionKeyDecoder.decode(encodedKey)
        let encryptedPayload = try ObvCryptoSuite.sharedInstance.authenticatedEncryption().encrypt(payload, with: authenticatedEncryptionKey, and: self.prng)
        
        let flowId = FlowIdentifier()
        let toIdentity = contactCryptoId.cryptoIdentity
        let method = ObvServerUploadReturnReceipt(ownedIdentity: ownedCryptoId.cryptoIdentity,
                                                  nonce: elements.nonce,
                                                  encryptedPayload: encryptedPayload,
                                                  toIdentity: toIdentity,
                                                  deviceUids: Array(deviceUids),
                                                  flowId: flowId)
        method.identityDelegate = identityDelegate
        let urlRequest = try method.getURLRequest()
        
        guard let dataToSend = method.dataToSend else {
            throw ReturnReceiptSender.makeError(message: "Could not get data to send")
        }
        let fileURL = try writeToTempFile(data: dataToSend)
                
        let task = session.uploadTask(with: urlRequest, fromFile: fileURL)
        
        task.resume()
        
    }
    
    
    func decryptPayloadOfObvReturnReceipt(_ obvReturnReceipt: ObvReturnReceipt, usingElements elements: (nonce: Data, key: Data)) throws -> (contactCryptoId: ObvCryptoId, status: Int) {
        guard let encodedKey = ObvEncoded(withRawData: elements.key) else {
            throw ReturnReceiptSender.makeError(message: "Could not decode key in elements")
        }
        let authenticatedEncryptionKey = try AuthenticatedEncryptionKeyDecoder.decode(encodedKey)
        let payload = try ObvCryptoSuite.sharedInstance.authenticatedEncryption().decrypt(obvReturnReceipt.encryptedPayload, with: authenticatedEncryptionKey)
        guard let payloadAsEncoded = ObvEncoded(withRawData: payload) else {
            throw ReturnReceiptSender.makeError(message: "Could not parse decrypted payload (1)")
        }
        guard let listOfEncoded = [ObvEncoded].init(payloadAsEncoded, expectedCount: 2) else {
            throw ReturnReceiptSender.makeError(message: "Could not parse decrypted payload (2)")
        }
        let contactIdentity: Data = try listOfEncoded[0].decode()
        let contactCryptoId = try ObvCryptoId(identity: contactIdentity)
        let status: Int = try listOfEncoded[1].decode()
        
        return (contactCryptoId, status)
    }
    
    
    func backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: String) -> Bool {
        return backgroundURLSessionIdentifier.starts(with: ReturnReceiptSender.backgroundURLSessionIdentifierPrefix)
    }

    
    func storeCompletionHandler(_ completionHandler: @escaping () -> Void, forHandlingEventsForBackgroundURLSessionWithIdentifier identifier: String) {
        guard backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: identifier) else {
            assertionFailure()
            return
        }
        self.completionHandler = completionHandler
        reCreateBackgroundURLSessionWithIdentifier(externalSessionIdentifier: identifier)
    }
    
    
    private func reCreateBackgroundURLSessionWithIdentifier(externalSessionIdentifier: String) {
        _ = ReturnReceiptSender.backgroundURLSessionWithIdentifier(externalSessionIdentifier, urlSessionDelegate: self, sharedContainerIdentifier: self.sharedContainerIdentifier, delegateQueue: self.delegateQueue)
    }

    
    private func writeToTempFile(data: Data) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
        let fileName = UUID().uuidString
        let tempFileUrl = URL(string: fileName, relativeTo: tempURL)!
        try data.write(to: tempFileUrl)
        return tempFileUrl
    }

}


// MARK: - URLSessionDelegate

extension ReturnReceiptSender: URLSessionDelegate {
    
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        debugPrint("[DEBUG] urlSession didBecomeInvalidWithError")
        self.session = ReturnReceiptSender.backgroundURLSessionWithIdentifier(self.sessionIdentifier, urlSessionDelegate: self, sharedContainerIdentifier: self.sharedContainerIdentifier, delegateQueue: self.delegateQueue)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        debugPrint("[DEBUG] urlSessionDidFinishEvents forBackgroundURLSession")
        self.completionHandler?()
        self.completionHandler = nil
    }

    
}


// MARK: - URLSessionTaskDelegate

extension ReturnReceiptSender: URLSessionTaskDelegate {
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {

        guard error == nil else {
            os_log("Failed to send the return receipt. Session task did complete with error: %{public}@", log: log, type: .fault, error!.localizedDescription)
            return
        }

        guard let data = receivedDataForTask.removeValue(forKey: task) else {
            os_log("We could not find the data returned by the server", log: log, type: .error)
            return
        }
        
        guard let status = ObvServerUploadReturnReceipt.parseObvServerResponse(responseData: data, using: log) else {
            os_log("We could not recover the status returned by the server", log: log, type: .fault)
            assert(false)
            return
        }
        
        switch status {
        case .generalError:
            os_log("Failed to send the return receipt. The server returned a General Error.", log: log, type: .fault)
        case .ok:
            os_log("Return receipt sent successfully", log: log, type: .info)
        }
        
    }

}


// MARK: - URLSessionDataDelegate

extension ReturnReceiptSender: URLSessionDataDelegate {
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if var previousData = receivedDataForTask[dataTask] {
            previousData.append(data)
            receivedDataForTask[dataTask] = previousData
        } else {
            receivedDataForTask[dataTask] = data
        }
    }
    
}
