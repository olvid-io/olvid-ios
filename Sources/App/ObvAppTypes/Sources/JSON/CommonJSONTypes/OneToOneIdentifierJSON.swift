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
import ObvTypes


public struct OneToOneIdentifierJSON: Codable, Equatable, Hashable, Sendable {
    
    private let identity1: ObvCryptoId
    private let identity2: ObvCryptoId
    
    var identities: Set<ObvCryptoId> {
        return Set([identity1, identity2])
    }
    
    public func getContactIdentity(ownedIdentity: ObvCryptoId) -> ObvCryptoId? {
        if identity1 == ownedIdentity {
            return identity2
        } else if identity2 == ownedIdentity {
            return identity1
        } else {
            assertionFailure()
            return nil
        }
    }
    
    public func getContactIdentifier(ownedCryptoId: ObvCryptoId) -> ObvContactIdentifier? {
        guard identities.contains(ownedCryptoId) else { assertionFailure(); return nil }
        guard let contactCryptoId: ObvCryptoId = getContactIdentity(ownedIdentity: ownedCryptoId) else { assertionFailure(); return nil }
        return ObvContactIdentifier(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
    }

    public init(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId) {
        self.identity1 = ownedCryptoId
        self.identity2 = contactCryptoId
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.identity1.getIdentity())
        try container.encode(self.identity2.getIdentity())
    }
    
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let rawIdentity1 = try container.decode(Data.self)
        let rawIdentity2 = try container.decode(Data.self)
        self.identity1 = try ObvCryptoId(identity: rawIdentity1)
        self.identity2 = try ObvCryptoId(identity: rawIdentity2)
    }
    
}
