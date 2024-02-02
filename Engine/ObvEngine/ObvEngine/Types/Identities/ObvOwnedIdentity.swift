/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import ObvTypes
import ObvMetaManager
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
 
    init(cryptoIdentity: ObvCryptoIdentity, publishedIdentityDetails: ObvIdentityDetails, isActive: Bool, isKeycloakManaged: Bool) {
        self.cryptoId = ObvCryptoId(cryptoIdentity: cryptoIdentity)
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


internal extension ObvOwnedIdentity {

    init?(ownedCryptoIdentity: ObvCryptoIdentity, identityDelegate: ObvIdentityDelegate, within obvContext: ObvContext) {
        do {
             guard try identityDelegate.isOwned(ownedCryptoIdentity, within: obvContext) else { return nil }
        } catch {
            return nil
        }
        let allIdentityDetails: (publishedIdentityDetails: ObvIdentityDetails, isActive: Bool)
        do {
            allIdentityDetails = try identityDelegate.getIdentityDetailsOfOwnedIdentity(ownedCryptoIdentity, within: obvContext)
        } catch {
            return nil
        }
        let isKeycloakManaged: Bool
        do {
            isKeycloakManaged = try identityDelegate.isOwnedIdentityKeycloakManaged(ownedIdentity: ownedCryptoIdentity, within: obvContext)
        } catch {
            return nil
        }

        self.init(cryptoIdentity: ownedCryptoIdentity,
                  publishedIdentityDetails: allIdentityDetails.publishedIdentityDetails,
                  isActive: allIdentityDetails.isActive,
                  isKeycloakManaged: isKeycloakManaged)
    }
    
}


// MARK: - Codable

extension ObvOwnedIdentity: Codable {
    
    enum CodingKeys: String, CodingKey {
        case cryptoId = "crypto_id"
        case publishedIdentityDetails = "published_details"
        case isActive = "is_active"
        case isKeycloakManaged = "is_keycloak_managed"
    }

}
