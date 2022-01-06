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

    let cryptoIdentity: ObvCryptoIdentity
    
    private static let errorDomain = String(describing: ObvCryptoId.self)
    
    init(cryptoIdentity: ObvCryptoIdentity) {
        self.cryptoIdentity = cryptoIdentity
    }
    
    public func belongsTo(serverURL: URL) -> Bool {
        return cryptoIdentity.serverURL == serverURL
    }
}


extension ObvCryptoId {

    static func decode(_ data: Data) throws -> ObvCryptoId {
        guard let obvEncoded = ObvEncoded(withRawData: data),
            let cryptoIdentity = ObvCryptoIdentity(obvEncoded) else {
            let message = "Data is not an encoded ObvCryptoId"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: ObvCryptoId.errorDomain, code: 0, userInfo: userInfo)
        }
        return self.init(cryptoIdentity: cryptoIdentity)
    }
    
    
    public func encode() -> Data {
        return self.cryptoIdentity.encode().rawData
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
        guard let cryptoIdentity = ObvCryptoIdentity(from: identity) else { throw NSError() }
        self.cryptoIdentity = cryptoIdentity
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
