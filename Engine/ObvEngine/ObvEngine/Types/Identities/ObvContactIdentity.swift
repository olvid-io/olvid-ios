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
import CoreData
import ObvTypes
import ObvCrypto
import ObvEncoder
import ObvMetaManager
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

    public var currentIdentityDetails: ObvIdentityDetails {
        return trustedIdentityDetails
    }
    
    public var contactIdentifier: ObvContactIdentifier {
        ObvContactIdentifier(contactCryptoId: cryptoId, ownedCryptoId: ownedIdentity.cryptoId)
    }

    init(cryptoIdentity: ObvCryptoIdentity, trustedIdentityDetails: ObvIdentityDetails, publishedIdentityDetails: ObvIdentityDetails?, ownedIdentity: ObvOwnedIdentity, isCertifiedByOwnKeycloak: Bool, isActive: Bool, isRevokedAsCompromised: Bool, isOneToOne: Bool) {
        self.cryptoId = ObvCryptoId(cryptoIdentity: cryptoIdentity)
        self.trustedIdentityDetails = trustedIdentityDetails
        self.publishedIdentityDetails = publishedIdentityDetails
        self.ownedIdentity = ownedIdentity
        self.isCertifiedByOwnKeycloak = isCertifiedByOwnKeycloak
        self.isActive = isActive
        self.isRevokedAsCompromised = isRevokedAsCompromised
        self.isOneToOne = isOneToOne
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


internal extension ObvContactIdentity {
    
    init?(contactCryptoIdentity: ObvCryptoIdentity, ownedCryptoIdentity: ObvCryptoIdentity, identityDelegate: ObvIdentityDelegate, within obvContext: ObvContext) {
        // The following call allows to make sure that `contactCryptoIdentity` is indeed a contact of `ownedCryptoIdentity` (it also ensures that `ownedCryptoIdentity` is an owned identity).
        guard (try? identityDelegate.isIdentity(contactCryptoIdentity, aContactIdentityOfTheOwnedIdentity: ownedCryptoIdentity, within: obvContext)) == true else { return nil }
        let allIdentityDetails: (publishedIdentityDetails: ObvIdentityDetails?, trustedIdentityDetails: ObvIdentityDetails)
        do {
            allIdentityDetails = try identityDelegate.getIdentityDetailsOfContactIdentity(contactCryptoIdentity, ofOwnedIdentity: ownedCryptoIdentity, within: obvContext)
        } catch {
            return nil
        }
        guard let ownedIdentity = ObvOwnedIdentity(ownedCryptoIdentity: ownedCryptoIdentity, identityDelegate: identityDelegate, within: obvContext) else { return nil }
        let isCertifiedByOwnKeycloak: Bool
        do {
            isCertifiedByOwnKeycloak = try identityDelegate.isContactCertifiedByOwnKeycloak(contactIdentity: contactCryptoIdentity, ofOwnedIdentity: ownedCryptoIdentity, within: obvContext)
        } catch {
            return nil
        }
        let isActive: Bool
        do {
            isActive = try identityDelegate.isContactIdentityActive(ownedIdentity: ownedCryptoIdentity, contactIdentity: contactCryptoIdentity, within: obvContext)
        } catch {
            return nil
        }
        let isRevokedAsCompromised: Bool
        do {
            isRevokedAsCompromised = try identityDelegate.isContactRevokedAsCompromised(ownedIdentity: ownedCryptoIdentity, contactIdentity: contactCryptoIdentity, within: obvContext)
        } catch {
            return nil
        }
        let isOneToOne: Bool
        do {
            isOneToOne = try identityDelegate.isOneToOneContact(ownedIdentity: ownedCryptoIdentity, contactIdentity: contactCryptoIdentity, within: obvContext)
        } catch {
            return nil
        }
        self.init(cryptoIdentity: contactCryptoIdentity,
                  trustedIdentityDetails: allIdentityDetails.trustedIdentityDetails,
                  publishedIdentityDetails: allIdentityDetails.publishedIdentityDetails,
                  ownedIdentity: ownedIdentity,
                  isCertifiedByOwnKeycloak: isCertifiedByOwnKeycloak,
                  isActive: isActive,
                  isRevokedAsCompromised: isRevokedAsCompromised,
                  isOneToOne: isOneToOne)
    }
    
}


// MARK: - Codable

extension ObvContactIdentity: Codable {
    
    /// ObvContactIdentity is codable so as to be able to transfer a message from the notification service to the main app.
    /// This serialization should **not** be used within long term storage since we may change it regularly.
    /// Si also `ObvMessage` and  `ObvAttachment`.

    enum CodingKeys: String, CodingKey {
        case cryptoId = "crypto_id"
        case trustedIdentityDetails = "trusted_details"
        case publishedIdentityDetails = "published_details"
        case ownedIdentity = "owned_identity"
        case isCertifiedByOwnKeycloak = "is_certified_by_own_keycloak"
        case isActive = "is_active"
        case isRevokedAsCompromised = "is_revoked_as_compromised"
        case isOneToOne = "one_to_one"
    }

}
