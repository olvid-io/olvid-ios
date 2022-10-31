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
import ObvCrypto
import ObvEncoder

public struct ObvCryptoId {

    public let cryptoIdentity: ObvCryptoIdentity
    
    private static let errorDomain = String(describing: ObvCryptoId.self)
    
    public init(cryptoIdentity: ObvCryptoIdentity) {
        self.cryptoIdentity = cryptoIdentity
    }
    
    public func belongsTo(serverURL: URL) -> Bool {
        return cryptoIdentity.serverURL == serverURL
    }
    
    private static func makeError(message: String, code: Int = 0) -> Error {
        NSError(domain: "ObvCryptoId", code: code, userInfo: [NSLocalizedFailureReasonErrorKey: message])
    }

}


extension ObvCryptoId: Hashable {
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.cryptoIdentity)
    }
    
}

extension ObvCryptoId: Equatable {
    
    public static func == (lhs: ObvCryptoId, rhs: ObvCryptoId) -> Bool {
        return lhs.getIdentity() == rhs.getIdentity()
    }
    
}

extension ObvCryptoId: Comparable {
    
    public static func < (lhs: ObvCryptoId, rhs: ObvCryptoId) -> Bool {
        return lhs.getIdentity() < rhs.getIdentity()
    }

}

extension ObvCryptoId {
    
    public func getIdentity() -> Data {
        return self.cryptoIdentity.getIdentity()
    }
    
    public init(identity: Data) throws {
        guard let cryptoIdentity = ObvCryptoIdentity(from: identity) else { throw Self.makeError(message: "Could not get ObvCryptoIdentity") }
        self.cryptoIdentity = cryptoIdentity
    }
    
    
}


// MARK: - ObvCodable

extension ObvCryptoId: ObvCodable {
    
    public func obvEncode() -> ObvEncoded {
        return self.cryptoIdentity.obvEncode()
    }
    
    public init?(_ obvEncoded: ObvEncoded) {
        guard let cryptoIdentity = ObvCryptoIdentity(obvEncoded) else { assertionFailure(); return nil }
        self.init(cryptoIdentity: cryptoIdentity)
    }
    
}


// MARK: - Codable

extension ObvCryptoId: Codable {
    
    enum CodingKeys: String, CodingKey {
        case cryptoIdentity = "crypto_identity"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cryptoIdentity.getIdentity(), forKey: .cryptoIdentity)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let identity = try values.decode(Data.self, forKey: .cryptoIdentity)
        guard let cryptoIdentity = ObvCryptoIdentity(from: identity) else {
            let message = "Could not parse identity"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: ObvCryptoId.errorDomain, code: 0, userInfo: userInfo)
        }
        self = ObvCryptoId(cryptoIdentity: cryptoIdentity)
    }
}


extension Data: Comparable {
    
    public static func < (lhs: Data, rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return lhs.count < rhs.count }
        let bytesPair = zip(lhs, rhs)
        for bytes in bytesPair {
            guard bytes.0 != bytes.1 else { continue }
            return bytes.0 < bytes.1
        }
        return false
    }
    
}
