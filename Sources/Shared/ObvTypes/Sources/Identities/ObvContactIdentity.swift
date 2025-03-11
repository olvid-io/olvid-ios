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
import CoreData
import ObvCrypto
import ObvEncoder
import OlvidUtils


public struct ObvContactIdentity: ObvIdentity {    
    
    public let cryptoId: ObvCryptoId
    public let trustedIdentityDetails: ObvIdentityDetails
    public let publishedIdentityDetails: ObvIdentityDetails?
    public let ownedIdentity: ObvOwnedIdentity
    public let isCertifiedByOwnKeycloak: Bool
    public let isActive: Bool
    public let isRevokedAsCompromised: Bool
    public let isOneToOne: Bool
    public let wasRecentlyOnline: Bool

    public var currentIdentityDetails: ObvIdentityDetails {
        return trustedIdentityDetails
    }
    
    public var contactIdentifier: ObvContactIdentifier {
        ObvContactIdentifier(contactCryptoId: cryptoId, ownedCryptoId: ownedIdentity.cryptoId)
    }

    public init(cryptoIdentity: ObvCryptoIdentity, trustedIdentityDetails: ObvIdentityDetails, publishedIdentityDetails: ObvIdentityDetails?, ownedIdentity: ObvOwnedIdentity, isCertifiedByOwnKeycloak: Bool, isActive: Bool, isRevokedAsCompromised: Bool, isOneToOne: Bool, wasRecentlyOnline: Bool) {
        self.cryptoId = ObvCryptoId(cryptoIdentity: cryptoIdentity)
        self.trustedIdentityDetails = trustedIdentityDetails
        self.publishedIdentityDetails = publishedIdentityDetails
        self.ownedIdentity = ownedIdentity
        self.isCertifiedByOwnKeycloak = isCertifiedByOwnKeycloak
        self.isActive = isActive
        self.isRevokedAsCompromised = isRevokedAsCompromised
        self.isOneToOne = isOneToOne
        self.wasRecentlyOnline = wasRecentlyOnline
    }
    
    public func getGenericIdentityWithPublishedOrTrustedDetails() -> ObvGenericIdentity {
        let details = publishedIdentityDetails ?? trustedIdentityDetails
        return ObvGenericIdentity.init(cryptoId: cryptoId, currentIdentityDetails: details)
    }
}


// MARK: Implementing CustomStringConvertible

extension ObvContactIdentity: CustomStringConvertible {
    public var description: String {
        return "ObvContactIdentity<\(currentIdentityDetails.coreDetails.getFullDisplayName())>"
    }
}
