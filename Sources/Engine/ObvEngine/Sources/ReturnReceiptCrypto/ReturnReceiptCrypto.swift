/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvTypes
import OlvidUtils


/// The crypto of the return receipts owed to us: minting the elements when we send a message, and decrypting a
/// receipt a contact sends back about it.
///
/// The receipts we owe to others are in `ObvReturnReceiptSendManager`, upload included.
final class ReturnReceiptCrypto: ObvErrorMaker {

    static let errorDomain = String(describing: ReturnReceiptCrypto.self)

    private let prng: PRNGService

    init(prng: PRNGService) {
        self.prng = prng
    }


    /// This method returns a 16 bytes nonce and a serialized encryption key. This is called when sending a message, in order to make it
    /// possible to have a return receipt back.
    func generateReturnReceiptElements() -> ObvReturnReceiptElements {
        let nonce = prng.genBytes(count: 16)
        let authenticatedEncryptionKey = ObvCryptoSuite.sharedInstance.authenticatedEncryption().generateKey(with: prng)
        let key = authenticatedEncryptionKey.obvEncode().rawData
        return ObvReturnReceiptElements(nonce: nonce, key: key)
    }


    func decryptPayloadOfObvReturnReceipt(_ obvReturnReceipt: ObvEncryptedReceivedReturnReceipt, decryptionKeyCandidates: Set<Data>) throws -> ObvDecryptedReceivedReturnReceipt? {
        
        for decryptionKeyCandidate in decryptionKeyCandidates {
            
            guard let encodedKey = ObvEncoded(withRawData: decryptionKeyCandidate) else {
                throw ReturnReceiptCrypto.makeError(message: "Could not decode key in elements")
            }
            let authenticatedEncryptionKey = try AuthenticatedEncryptionKeyDecoder.decode(encodedKey)
            guard let payload = try? ObvCryptoSuite.sharedInstance.authenticatedEncryption().decrypt(obvReturnReceipt.encryptedPayload, with: authenticatedEncryptionKey) else {
                continue
            }
            guard let payloadAsEncoded = ObvEncoded(withRawData: payload) else {
                throw ReturnReceiptCrypto.makeError(message: "Could not parse decrypted payload")
            }
            // `ObvReturnReceiptPayload` owns the encoding, and writes the receipts we owe as well as reading these.
            guard let returnReceiptPayload = ObvReturnReceiptPayload(payloadAsEncoded) else {
                throw ReturnReceiptCrypto.makeError(message: "Could not parse decrypted payload")
            }
            
            return .init(contactCryptoId: returnReceiptPayload.author,
                         status: returnReceiptPayload.status,
                         attachmentNumber: returnReceiptPayload.attachmentNumber,
                         encryptedReceivedReturnReceipt: obvReturnReceipt)
            
        }
        
        // No key allowed to decrypt
        
        return nil
        
    }
    
}
