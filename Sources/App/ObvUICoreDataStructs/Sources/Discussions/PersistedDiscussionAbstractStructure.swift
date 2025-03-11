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
import ObvAppTypes


public struct PersistedDiscussionAbstractStructure {
    
    let ownedIdentity: PersistedObvOwnedIdentityStructure
    let title: String
    let localConfiguration: PersistedDiscussionLocalConfigurationStructure
    var ownedCryptoId: ObvCryptoId { ownedIdentity.cryptoId }
    
    
    public init(ownedIdentity: PersistedObvOwnedIdentityStructure, title: String, localConfiguration: PersistedDiscussionLocalConfigurationStructure) {
        self.ownedIdentity = ownedIdentity
        self.title = title
        self.localConfiguration = localConfiguration
    }
    
    
    public enum StructureKind {
        case oneToOneDiscussion(structure: PersistedOneToOneDiscussionStructure)
        case groupDiscussion(structure: PersistedGroupDiscussionStructure)
        case groupV2Discussion(structure: PersistedGroupV2DiscussionStructure)

        public var title: String {
            switch self {
            case .groupDiscussion(let structure):
                return structure.title
            case .oneToOneDiscussion(let structure):
                return structure.title
            case .groupV2Discussion(let structure):
                return structure.title
            }
        }
        public var localConfiguration: PersistedDiscussionLocalConfigurationStructure {
            switch self {
            case .groupDiscussion(let structure):
                return structure.localConfiguration
            case .oneToOneDiscussion(let structure):
                return structure.localConfiguration
            case .groupV2Discussion(let structure):
                return structure.localConfiguration
            }
        }
        public var ownedCryptoId: ObvCryptoId {
            switch self {
            case .groupDiscussion(let structure):
                return structure.ownedCryptoId
            case .oneToOneDiscussion(let structure):
                return structure.ownedCryptoId
            case .groupV2Discussion(let structure):
                return structure.ownedCryptoId
            }
        }
        
        public var ownedIdentity: PersistedObvOwnedIdentityStructure {
            switch self {
            case .groupDiscussion(let structure):
                return structure.ownedIdentity
            case .oneToOneDiscussion(let structure):
                return structure.ownedIdentity
            case .groupV2Discussion(let structure):
                return structure.ownedIdentity
            }
        }
        
        public var conversationIdentifier: String {
            return self.discussionIdentifier.description
        }
        
        public var discussionIdentifier: ObvDiscussionIdentifier {
            switch self {
            case .oneToOneDiscussion(let structure):
                return structure.identifier
            case .groupDiscussion(let structure):
                return structure.identifier
            case .groupV2Discussion(let structure):
                return structure.identifier
            }
        }
        
    }

}
