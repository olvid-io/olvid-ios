/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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


final class ReturnReceiptSender: NSObject, ObvErrorMaker {
    
    private let prng: PRNGService
    
    weak var identityDelegate: ObvIdentityDelegate?
    
    public var logSubsystem: String = ObvEngine.defaultLogSubsystem
    public func prependLogSubsystem(with prefix: String) {
        logSubsystem = "\(prefix).\(logSubsystem)"
    }
    private lazy var log = OSLog(subsystem: logSubsystem, category: String(describing: ReturnReceiptSender.self))
    private lazy var logger = Logger(subsystem: logSubsystem, category: String(describing: ReturnReceiptSender.self))
    
    init(prng: PRNGService) {
        self.prng = prng
        super.init()
    }
    
    
    static let errorDomain = String(describing: ReturnReceiptSender.self)


    /// This method returns a 16 bytes nonce and a serialized encryption key. This is called when sending a message, in order to make it
    /// possible to have a return receipt back.
    func generateReturnReceiptElements() -> ObvReturnReceiptElements {
        let nonce = prng.genBytes(count: 16)
        let authenticatedEncryptionKey = ObvCryptoSuite.sharedInstance.authenticatedEncryption().generateKey(with: prng)
        let key = authenticatedEncryptionKey.obvEncode().rawData
        return ObvReturnReceiptElements(nonce: nonce, key: key)
    }

    
    func postReturnReceiptsWithElements(returnReceiptsToSend: [ObvReturnReceiptToSend], flowId: FlowIdentifier) async throws {
        
        guard let identityDelegate = self.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            assertionFailure()
            throw ReturnReceiptSender.makeError(message: "The identity delegate is not set")
        }
        
        let log = self.log

        let returnReceiptsToSend = returnReceiptsToSend.filter({ !$0.contactDeviceUIDs.isEmpty })

        let returnReceipts: [ObvServerUploadReturnReceipt.ReturnReceipt] = returnReceiptsToSend.compactMap { returnReceiptToSend in
            guard !returnReceiptToSend.contactDeviceUIDs.isEmpty else { assertionFailure(); return nil }
            let ownedIdentity = returnReceiptToSend.contactIdentifier.ownedCryptoId.getIdentity()
            let status = returnReceiptToSend.status
            var payloadElements: [ObvEncodable] = [ownedIdentity, status]
            if let attachmentNumber = returnReceiptToSend.attachmentNumber {
                payloadElements += [attachmentNumber]
            }
            let payload = payloadElements.obvEncode().rawData
            guard let encodedKey = ObvEncoded(withRawData: returnReceiptToSend.elements.key) else {
                assertionFailure("Could not decode key in elements")
                return nil
            }
            let encryptedPayload: EncryptedData
            do {
                let authenticatedEncryptionKey = try AuthenticatedEncryptionKeyDecoder.decode(encodedKey)
                encryptedPayload = try ObvCryptoSuite.sharedInstance.authenticatedEncryption().encrypt(payload, with: authenticatedEncryptionKey, and: self.prng)
            } catch {
                assertionFailure()
                return nil
            }
            let toIdentity = returnReceiptToSend.contactIdentifier.contactCryptoId.cryptoIdentity
            let returnReceipt = ObvServerUploadReturnReceipt.ReturnReceipt(
                toIdentity: toIdentity,
                deviceUids: Array(returnReceiptToSend.contactDeviceUIDs),
                nonce: returnReceiptToSend.elements.nonce,
                encryptedPayload: encryptedPayload)
            return returnReceipt
        }
        
        // Split the return receipts per server
        
        let returnReceiptsForServer: [URL : [ObvServerUploadReturnReceipt.ReturnReceipt]] = Dictionary(grouping: returnReceipts, by: { $0.toIdentity.serverURL })
        
        // Send a batch per server
                
        await withTaskGroup(of: Void.self) { taskGroup in
        
            for (serverURL, returnReceiptsForServer) in returnReceiptsForServer {
                
                for sliceOfReturnReceiptsForServer in returnReceiptsForServer.toSlices(ofMaxSize: 50) {
                    
                    taskGroup.addTask {

                        do {
                            
                            let method = ObvServerUploadReturnReceipt(serverURL: serverURL,
                                                                      returnReceipts: sliceOfReturnReceiptsForServer,
                                                                      flowId: flowId)
                            method.identityDelegate = identityDelegate
                            
                            // Since the request of a upload task should not contain a body or a body stream, we use URLSession.upload(for:from:), passing the data to send via the `from` attribute.
                            guard let dataToSend = method.dataToSend else {
                                throw ReturnReceiptSender.makeError(message: "Could not get data to send")
                            }
                            method.dataToSend = nil
                            
                            let urlRequest = try method.getURLRequest()
                            
                            let (responseData, response) = try await URLSession.shared.upload(for: urlRequest, from: dataToSend)
                            
                            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                                assertionFailure()
                                throw Self.makeError(message: "Bad HTTPURLResponse")
                            }
                            
                            guard let status = ObvServerUploadReturnReceipt.parseObvServerResponse(responseData: responseData, using: log) else {
                                self.logger.fault("🧾 We could not recover the status returned by the server")
                                assertionFailure()
                                throw Self.makeError(message: "We could not recover the status returned by the server")
                            }
                            
                            switch status {
                            case .generalError:
                                self.logger.fault("🧾 Failed to send the return receipt. The server returned a General Error.")
                                assertionFailure()
                                throw Self.makeError(message: "Failed to send the return receipt. The server returned a General Error")
                            case .ok:
                                self.logger.info("🧾 \(sliceOfReturnReceiptsForServer.count) return receipts sent successfully")
                            }
                            
                        } catch {
                            self.logger.fault("Failed to send batch of return receipts: \(error.localizedDescription)")
                            assertionFailure()
                        }

                    }

                }
                
            }

        }
        
    }
    
    
    func decryptPayloadOfObvReturnReceipt(_ obvReturnReceipt: ObvEncryptedReceivedReturnReceipt, decryptionKeyCandidates: Set<Data>) throws -> ObvDecryptedReceivedReturnReceipt? {
        
        for decryptionKeyCandidate in decryptionKeyCandidates {
            
            guard let encodedKey = ObvEncoded(withRawData: decryptionKeyCandidate) else {
                throw ReturnReceiptSender.makeError(message: "Could not decode key in elements")
            }
            let authenticatedEncryptionKey = try AuthenticatedEncryptionKeyDecoder.decode(encodedKey)
            guard let payload = try? ObvCryptoSuite.sharedInstance.authenticatedEncryption().decrypt(obvReturnReceipt.encryptedPayload, with: authenticatedEncryptionKey) else {
                continue
            }
            guard let payloadAsEncoded = ObvEncoded(withRawData: payload) else {
                throw ReturnReceiptSender.makeError(message: "Could not parse decrypted payload (1)")
            }
            guard let listOfEncoded = [ObvEncoded](payloadAsEncoded) else {
                throw ReturnReceiptSender.makeError(message: "Could not parse decrypted payload (2)")
            }
            guard [2, 3].contains(listOfEncoded.count) else {
                throw ReturnReceiptSender.makeError(message: "Could not parse decrypted payload (3)")
            }
            let contactIdentity: Data = try listOfEncoded[0].obvDecode()
            let contactCryptoId = try ObvCryptoId(identity: contactIdentity)
            let status: ObvReturnReceiptStatus = try listOfEncoded[1].obvDecode()
            var attachmentNumber: Int?
            if listOfEncoded.count == 3 {
                attachmentNumber = try listOfEncoded[2].obvDecode()
            }
            
            return .init(contactCryptoId: contactCryptoId,
                         status: status,
                         attachmentNumber: attachmentNumber,
                         encryptedReceivedReturnReceipt: obvReturnReceipt)
            
        }
        
        // No key allowed to decrypt
        
        return nil
        
    }
    
}
