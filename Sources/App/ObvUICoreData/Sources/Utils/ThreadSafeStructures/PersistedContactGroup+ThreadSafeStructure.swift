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
import ObvCrypto
import os.log
import ObvSettings
import ObvUICoreDataStructs
import ObvTypes


// MARK: - Thread safe struct

extension PersistedContactGroup {

    public func toStructure() throws -> PersistedContactGroupStructure {
        guard let ownedIdentity else { assertionFailure(); throw ObvUICoreDataError.ownedIdentityIsNil }
        let contactIdentities = Set(try self.contactIdentities.map { try $0.toStructure() })
        let groupOwner: ObvCryptoId = try ObvCryptoId(identity: self.ownerIdentity)
        let groupV1Identifier = GroupV1Identifier(groupUid: self.groupUid, groupOwner: groupOwner)
        return .init(groupV1Identifier: groupV1Identifier,
                     groupName: self.groupName,
                     category: self.category.structureCategory,
                     displayPhotoURL: self.displayPhotoURL,
                     contactIdentities: contactIdentities,
                     ownedIdentity: try ownedIdentity.toStructure())
    }

}


fileprivate extension PersistedContactGroup.Category {
    
    var structureCategory: PersistedContactGroupStructure.Category {
        switch self {
        case .owned: return .owned
        case .joined: return .joined
        }
    }
    
}
