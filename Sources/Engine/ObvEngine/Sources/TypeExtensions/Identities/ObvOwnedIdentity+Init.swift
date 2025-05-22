/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvTypes
import OlvidUtils
import ObvMetaManager


internal extension ObvOwnedIdentity {

    init?(ownedCryptoIdentity: ObvCryptoIdentity, identityDelegate: ObvIdentityDelegate, within obvContext: ObvContext) {
        do {
            guard try !identityDelegate.isOwnedIdentityDeletedOrDeletionIsInProgress(ownedCryptoIdentity, within: obvContext) else {
                return nil
            }
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
