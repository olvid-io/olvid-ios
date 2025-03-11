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

public struct ObvOwnedIdentity: ObvIdentity, CustomStringConvertible {
    
    public let cryptoId: ObvCryptoId
    public let publishedIdentityDetails: ObvIdentityDetails
    public let isActive: Bool
    public let isKeycloakManaged: Bool
    
    public var currentIdentityDetails: ObvIdentityDetails {
        return publishedIdentityDetails
    }
    
    public var signedUserDetails: String? {
        publishedIdentityDetails.coreDetails.signedUserDetails
    }
    
    private static let errorDomain = String(describing: ObvOwnedIdentity.self)
 
    public init(cryptoIdentity: ObvCryptoIdentity, publishedIdentityDetails: ObvIdentityDetails, isActive: Bool, isKeycloakManaged: Bool) {
        self.cryptoId = ObvCryptoId(cryptoIdentity: cryptoIdentity)
        self.publishedIdentityDetails = publishedIdentityDetails
        self.isActive = isActive
        self.isKeycloakManaged = isKeycloakManaged
    }
    
    public init(cryptoId: ObvCryptoId, publishedIdentityDetails: ObvIdentityDetails, isActive: Bool, isKeycloakManaged: Bool) {
        self.cryptoId = cryptoId
        self.publishedIdentityDetails = publishedIdentityDetails
        self.isActive = isActive
        self.isKeycloakManaged = isKeycloakManaged
    }
    
}


// MARK: - Implementing CustomStringConvertible

extension ObvOwnedIdentity {
    public var description: String {
        return "ObvOwnedIdentity<\(currentIdentityDetails.coreDetails.getFullDisplayName())>"
    }
}
