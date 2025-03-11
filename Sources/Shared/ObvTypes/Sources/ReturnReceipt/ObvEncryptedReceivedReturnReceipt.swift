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


public struct ObvEncryptedReceivedReturnReceipt {
    
    let identity: ObvCryptoIdentity
    public let serverUid: UID
    public let nonce: Data
    public let encryptedPayload: EncryptedData
    public let timestamp: Date
    
    public var ownedCryptoId: ObvCryptoId {
        ObvCryptoId(cryptoIdentity: self.identity)
    }
    
}


// MARK: - Decoding an encrypted return receipt received by the websocket

extension ObvEncryptedReceivedReturnReceipt: Decodable {
        
    private static let errorDomain = String(describing: ObvEncryptedReceivedReturnReceipt.self)

    enum CodingKeys: String, CodingKey {
        case action = "action"
        case identity = "identity"
        case serverUid = "serverUid"
        case nonce = "nonce"
        case encryptedPayload = "encryptedPayload"
        case timestamp = "timestamp"
    }

    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let action = try values.decode(String.self, forKey: .action)
        guard action == "return_receipt" else {
            let message = "The received JSON is not a return receipt"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: Self.errorDomain, code: 0, userInfo: userInfo)
        }
        let identityAsString = try values.decode(String.self, forKey: .identity)
        guard let identityAsData = Data(base64Encoded: identityAsString) else {
            let message = "Could not parse the received identity"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: Self.errorDomain, code: 0, userInfo: userInfo)
        }
        guard let identity = ObvCryptoIdentity(from: identityAsData) else {
            let message = "Could not parse the received JSON"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: Self.errorDomain, code: 0, userInfo: userInfo)
        }
        let serverUidInBase64 = try values.decode(String.self, forKey: .serverUid)
        guard let serverUidAsData = Data(base64Encoded: serverUidInBase64) else {
            let message = "Could not parse the server uid in the received JSON (1)"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: Self.errorDomain, code: 0, userInfo: userInfo)
        }
        guard let serverUid = UID(uid: serverUidAsData) else {
            let message = "Could not parse the server uid in the received JSON (2)"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: Self.errorDomain, code: 0, userInfo: userInfo)
        }
        let nonceInBase64 = try values.decode(String.self, forKey: .nonce)
        guard let nonce = Data(base64Encoded: nonceInBase64) else {
            let message = "Could not parse the nonce in the received JSON"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: Self.errorDomain, code: 0, userInfo: userInfo)
        }
        let encryptedPayloadInBase64 = try values.decode(String.self, forKey: .encryptedPayload)
        guard let encryptedPayloadAsData = Data(base64Encoded: encryptedPayloadInBase64) else {
            let message = "Could not parse the encrypted payload"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: Self.errorDomain, code: 0, userInfo: userInfo)
        }
        let encryptedPayload = EncryptedData(data: encryptedPayloadAsData)
        let timestampInMilliseconds = try values.decode(Int.self, forKey: .timestamp)
        let timestamp = Date(timeIntervalSince1970: Double(timestampInMilliseconds)/1000.0)
        self.init(identity: identity, serverUid: serverUid, nonce: nonce, encryptedPayload: encryptedPayload, timestamp: timestamp)
    }
    
    
    public init(string: String) throws {
        guard let data = string.data(using: .utf8) else {
            let message = "The received JSON is not UTF8 encoded"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: Self.errorDomain, code: 0, userInfo: userInfo)
        }
        let decoder = JSONDecoder()
        self = try decoder.decode(ObvEncryptedReceivedReturnReceipt.self, from: data)
    }
    
}
