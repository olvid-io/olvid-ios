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
import OlvidUtils


struct JsonKeycloakRevocation: Decodable {
    
    let cryptoIdentity: ObvCryptoIdentity
    let revocationTimestamp: Date
    let revocationType: KeycloakRevokedIdentity.RevocationType
    
    private static let errorDomain = "JsonKeycloakRevocation"
    private static func makeError(message: String) -> Error { NSError(domain: JsonKeycloakRevocation.errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    enum CodingKeys: String, CodingKey {
        case identity = "identity"
        case revocationTimestamp = "timestamp"
        case revocationType = "type"
    }

    private init(cryptoIdentity: ObvCryptoIdentity, revocationTimestamp: Date, revocationType: KeycloakRevokedIdentity.RevocationType) {
        self.cryptoIdentity = cryptoIdentity
        self.revocationTimestamp = revocationTimestamp
        self.revocationType = revocationType
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let identity = try values.decode(Data.self, forKey: .identity)
        guard let cryptoIdentity = ObvCryptoIdentity(from: identity) else { throw JsonKeycloakRevocation.makeError(message: "Could not parse identity into an ObvCryptoIdentity") }
        let epochInMs = Int64(try values.decode(Int.self, forKey: .revocationTimestamp))
        let revocationTimestamp = Date(epochInMs: epochInMs)
        let rawRevocationType = try values.decode(Int.self, forKey: .revocationType)
        guard let revocationType = KeycloakRevokedIdentity.RevocationType(rawValue: rawRevocationType) else { throw JsonKeycloakRevocation.makeError(message: "Could not parse revocation type") }
        self.init(cryptoIdentity: cryptoIdentity, revocationTimestamp: revocationTimestamp, revocationType: revocationType)
    }
    
    static func decode(data: Data) throws -> Self {
        let decoder = JSONDecoder()
        return try decoder.decode(Self.self, from: data)
    }

}
