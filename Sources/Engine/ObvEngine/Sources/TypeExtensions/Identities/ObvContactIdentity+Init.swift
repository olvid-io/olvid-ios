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
import ObvTypes
import ObvMetaManager
import OlvidUtils
import ObvCrypto


extension ObvContactIdentity {
    
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
            let contactStatus = try identityDelegate.getOneToOneStatusOfContactIdentity(ownedIdentity: ownedCryptoIdentity, contactIdentity: contactCryptoIdentity, within: obvContext)
            isOneToOne = (contactStatus == .oneToOne)
        } catch {
            return nil
        }
        let wasRecentlyOnline: Bool
        do {
            wasRecentlyOnline = try identityDelegate.checkIfContactWasRecentlyOnline(ownedIdentity: ownedCryptoIdentity, contactIdentity: contactCryptoIdentity, within: obvContext)
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
                  isOneToOne: isOneToOne,
                  wasRecentlyOnline: wasRecentlyOnline)
    }
    
}
