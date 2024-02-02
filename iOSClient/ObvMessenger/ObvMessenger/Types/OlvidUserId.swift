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
import ObvTypes
import ObvUICoreData


enum OlvidUserId: Hashable {
    case known(contactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, ownCryptoId: ObvCryptoId, remoteCryptoId: ObvCryptoId, displayName: String)
    case unknown(ownCryptoId: ObvCryptoId, remoteCryptoId: ObvCryptoId, displayName: String)
    case ownedIdentity(ownedCryptoId: ObvCryptoId)

    var contactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>? {
        if case .known(contactObjectID: let contactObjectID, ownCryptoId: _, remoteCryptoId: _, displayName: _) = self { return contactObjectID } else { return nil }
    }
    
    var isOwnedIdentity: Bool {
        switch self {
        case .known, .unknown:
            return false
        case .ownedIdentity:
            return true
        }
    }
    
    
    /// Non-nil iff we are in the `known` case
    var contactIdentifier: ObvContactIdentifier? {
        switch self {
        case .known(_, ownCryptoId: let ownCryptoId, remoteCryptoId: let remoteCryptoId, _):
            return .init(contactCryptoId: remoteCryptoId, ownedCryptoId: ownCryptoId)
        case .unknown, .ownedIdentity:
            return nil
        }
    }
    
    
    var ownCryptoId: ObvCryptoId {
        switch self {
        case .known(contactObjectID: _, ownCryptoId: let ownCryptoId, remoteCryptoId: _, displayName: _),
                .unknown(ownCryptoId: let ownCryptoId, remoteCryptoId: _, displayName: _):
            return ownCryptoId
        case .ownedIdentity(ownedCryptoId: let ownedCryptoId):
            return ownedCryptoId
        }
    }
    
    var remoteCryptoId: ObvCryptoId {
        switch self {
        case .known(contactObjectID: _, ownCryptoId: _, remoteCryptoId: let remoteIdentity, displayName: _),
                .unknown(ownCryptoId: _, remoteCryptoId: let remoteIdentity, displayName: _):
            return remoteIdentity
        case .ownedIdentity(ownedCryptoId: let ownedCryptoId):
            return ownedCryptoId
        }
    }
    
    var displayName: String {
        switch self {
        case .known(contactObjectID: _, ownCryptoId: _, remoteCryptoId: _, displayName: let displayName),
                .unknown(ownCryptoId: _, remoteCryptoId: _, displayName: let displayName):
            return displayName
        case .ownedIdentity:
            assertionFailure()
            return ""
        }
    }

}


extension OlvidUserId: CustomDebugStringConvertible {
    
    var debugDescription: String {
        switch self {
        case .known(contactObjectID: _, ownCryptoId: _, remoteCryptoId: let remoteCryptoId, displayName: _):
            return "known (\(remoteCryptoId.getIdentity().debugDescription))"
        case .unknown(ownCryptoId: _, remoteCryptoId: let remoteCryptoId, displayName: _):
            return "unknown (\(remoteCryptoId.getIdentity().debugDescription))"
        case .ownedIdentity:
            return "ownedIdentity"
        }
    }
    
}
