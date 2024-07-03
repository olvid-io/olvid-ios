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
import ObvEncoder

/// A KeyId represents a 32 bytes (not necessarily unique) identifier for an authenticated encryption key. This is typically used within wrapped keys.
public struct CryptoKeyId: Hashable, Equatable {
    
    public static let length = 32
    
    public let raw: Data
    
    public init?(_ rawKeyId: Data) {
        guard rawKeyId.count == CryptoKeyId.length else { assertionFailure(); return nil }
        self.raw = rawKeyId
    }
}


// MARK: Concat/Parse a CryptoKeyId and an encrypted message key

extension CryptoKeyId {
    
    public func concat(with encryptedMessageKey: EncryptedData) -> EncryptedData {
        let rawWrappedMessageKey = self.raw + encryptedMessageKey
        let wrappedMessageKey = EncryptedData(data: rawWrappedMessageKey)
        return wrappedMessageKey
    }
    
    
    /// Used both by ``ObvObliviousChannel`` and by ``PreKeyChannel``.
    public static func parse(_ wrappedMessageKey: EncryptedData) -> (EncryptedData, CryptoKeyId)? {
        // Construct the key id
        guard wrappedMessageKey.count >= CryptoKeyId.length else { return nil }
        let keyIdRange = wrappedMessageKey.startIndex..<wrappedMessageKey.startIndex+CryptoKeyId.length
        let rawKeyId = wrappedMessageKey[keyIdRange].raw
        let keyId = CryptoKeyId(rawKeyId)!
        // Construct the encryptedMessageToSendKey
        let encryptedMessageToSendKeyRange = wrappedMessageKey.startIndex+CryptoKeyId.length..<wrappedMessageKey.endIndex
        let encryptedMessageKey = wrappedMessageKey[encryptedMessageToSendKeyRange]
        return (encryptedMessageKey, keyId)
    }

}


// MARL: ObvCodable

extension CryptoKeyId: ObvCodable {

    public func obvEncode() -> ObvEncoder.ObvEncoded {
        self.raw.obvEncode()
    }

    public init?(_ obvEncoded: ObvEncoder.ObvEncoded) {
        guard let raw: Data = try? obvEncoded.obvDecode() else { assertionFailure(); return nil }
        self.init(raw)
    }
    
}


// MARK: - CustomStringConvertible

extension CryptoKeyId: CustomStringConvertible {
    
    public var description: String {
        return "\(raw.hexString())"
    }
    
}
