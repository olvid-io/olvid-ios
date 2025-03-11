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


public struct PersistedGroupV2Structure {
    
    public let groupIdentifier: ObvGroupV2.Identifier
    let displayName: String
    public let displayPhotoURL: URL?
    public let contactIdentities: Set<PersistedObvContactIdentityStructure>
    public let ownedIdentity: PersistedObvOwnedIdentityStructure

    public var obvGroupIdentifier: ObvGroupV2Identifier {
        .init(ownedCryptoId: ownedIdentity.cryptoId, identifier: groupIdentifier)
    }
    
    
    public init(groupIdentifier: ObvGroupV2.Identifier, displayName: String, displayPhotoURL: URL?, contactIdentities: Set<PersistedObvContactIdentityStructure>, ownedIdentity: PersistedObvOwnedIdentityStructure) {
        self.groupIdentifier = groupIdentifier
        self.displayName = displayName
        self.displayPhotoURL = displayPhotoURL
        self.contactIdentities = contactIdentities
        self.ownedIdentity = ownedIdentity
    }
    
}
