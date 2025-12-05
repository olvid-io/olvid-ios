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
import ObvTypes


public struct PersistedContactGroupStructure: Hashable, Equatable, Sendable {
    
    public let groupV1Identifier: GroupV1Identifier
    let groupDisplayName: String
    let category: Category
    public let displayPhotoURL: URL?
    public let contactIdentities: Set<PersistedObvContactIdentityStructure>
    public let ownedIdentity: PersistedObvOwnedIdentityStructure

    public var obvGroupIdentifier: ObvGroupV1Identifier {
        .init(ownedCryptoId: ownedIdentity.cryptoId, groupV1Identifier: groupV1Identifier)
    }
    
    public enum Category: Int, Sendable {
        case owned = 0
        case joined = 1
    }
    
    // Initializer
    
    public init(groupV1Identifier: GroupV1Identifier, groupDisplayName: String, category: Category, displayPhotoURL: URL?, contactIdentities: Set<PersistedObvContactIdentityStructure>, ownedIdentity: PersistedObvOwnedIdentityStructure) {
        self.groupV1Identifier = groupV1Identifier
        self.groupDisplayName = groupDisplayName
        self.category = category
        self.displayPhotoURL = displayPhotoURL
        self.contactIdentities = contactIdentities
        self.ownedIdentity = ownedIdentity
    }
    
    // Hashable and equatable
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(obvGroupIdentifier)
    }
    
    public static func == (lhs: PersistedContactGroupStructure, rhs: PersistedContactGroupStructure) -> Bool {
        lhs.obvGroupIdentifier == rhs.obvGroupIdentifier
    }
    
}
