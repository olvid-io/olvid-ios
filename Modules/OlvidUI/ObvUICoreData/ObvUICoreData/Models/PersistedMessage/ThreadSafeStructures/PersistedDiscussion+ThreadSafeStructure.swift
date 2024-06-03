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


// MARK: - Thread safe struct for PersistedDiscussion

extension PersistedDiscussion {
    
    public struct AbstractStructure {
        let ownedIdentity: PersistedObvOwnedIdentity.Structure
        let objectPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>
        let title: String
        let localConfiguration: PersistedDiscussionLocalConfiguration.Structure
        var ownedCryptoId: ObvCryptoId { ownedIdentity.cryptoId }
    }
    
    public func toAbstractStruct() throws -> AbstractStructure {
        guard let ownedIdentityStruct = try ownedIdentity?.toStruct() else { assertionFailure(); throw Self.makeError(message: "Could not determine owned identity") }
        return AbstractStructure(ownedIdentity: ownedIdentityStruct,
                                 objectPermanentID: self.discussionPermanentID,
                                 title: self.title,
                                 localConfiguration: self.localConfiguration.toStruct())
    }
    
    public func toStructKind() throws -> StructureKind {
        switch try kind {
        case .oneToOne:
            guard let oneToOneDiscussion = self as? PersistedOneToOneDiscussion else {
                throw Self.makeError(message: "Internal error")
            }
            let structure = try oneToOneDiscussion.toStruct()
            return .oneToOneDiscussion(structure: structure)
        case .groupV1:
            guard let groupDiscussion = self as? PersistedGroupDiscussion else {
                throw Self.makeError(message: "Internal error")
            }
            let structure = try groupDiscussion.toStruct()
            return .groupDiscussion(structure: structure)
        case .groupV2:
            guard let groupV2Discussion = self as? PersistedGroupV2Discussion else {
                throw Self.makeError(message: "Internal error")
            }
            let structure = try groupV2Discussion.toStruct()
            return .groupV2Discussion(structure: structure)
        }
    }

    public enum StructureKind {
        case oneToOneDiscussion(structure: PersistedOneToOneDiscussion.Structure)
        case groupDiscussion(structure: PersistedGroupDiscussion.Structure)
        case groupV2Discussion(structure: PersistedGroupV2Discussion.Structure)

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
        public var localConfiguration: PersistedDiscussionLocalConfiguration.Structure {
            switch self {
            case .groupDiscussion(let structure):
                return structure.localConfiguration
            case .oneToOneDiscussion(let structure):
                return structure.localConfiguration
            case .groupV2Discussion(let structure):
                return structure.localConfiguration
            }
        }
        public var discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion> {
            switch self {
            case .groupDiscussion(let structure):
                return structure.objectPermanentID.downcast
            case .oneToOneDiscussion(let structure):
                return structure.objectPermanentID.downcast
            case .groupV2Discussion(let structure):
                return structure.objectPermanentID.downcast
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
        
        public var ownedIdentity: PersistedObvOwnedIdentity.Structure {
            switch self {
            case .groupDiscussion(let structure):
                return structure.ownedIdentity
            case .oneToOneDiscussion(let structure):
                return structure.ownedIdentity
            case .groupV2Discussion(let structure):
                return structure.ownedIdentity
            }
        }
    }

}


// MARK: - Thread safe struct for PersistedOneToOneDiscussion

extension PersistedOneToOneDiscussion {
    
    public struct Structure {
        let objectPermanentID: ObvManagedObjectPermanentID<PersistedOneToOneDiscussion>
        public let contactIdentity: PersistedObvContactIdentity.Structure
        fileprivate let discussionStruct: PersistedDiscussion.AbstractStructure
        var title: String { discussionStruct.title }
        var localConfiguration: PersistedDiscussionLocalConfiguration.Structure { discussionStruct.localConfiguration }
        var ownedCryptoId: ObvCryptoId { discussionStruct.ownedCryptoId }
        var ownedIdentity: PersistedObvOwnedIdentity.Structure { discussionStruct.ownedIdentity }
        
        public init(objectPermanentID: ObvManagedObjectPermanentID<PersistedOneToOneDiscussion>, contactIdentity: PersistedObvContactIdentity.Structure, discussionStruct: PersistedDiscussion.AbstractStructure) {
            self.objectPermanentID = objectPermanentID
            self.contactIdentity = contactIdentity
            self.discussionStruct = discussionStruct
        }
    }
    
    public func toStruct() throws -> Structure {
        guard let contactIdentity = self.contactIdentity, let objectPermanentID else {
            assertionFailure()
            throw Self.makeError(message: "Could not extract required relationships")
        }
        let discussionStruct = try toAbstractStruct()
        return Structure(objectPermanentID: objectPermanentID,
                         contactIdentity: try contactIdentity.toStruct(),
                         discussionStruct: discussionStruct)
    }
}


// MARK: - Thread safe struct for PersistedGroupDiscussion

public extension PersistedGroupDiscussion {
    
    struct Structure {
        let objectPermanentID: ObvManagedObjectPermanentID<PersistedGroupDiscussion>
        let groupUID: Data
        let ownerIdentity: PersistedObvOwnedIdentity.Structure
        public let contactGroup: PersistedContactGroup.Structure
        fileprivate let discussionStruct: PersistedDiscussion.AbstractStructure
        public var title: String { discussionStruct.title }
        var localConfiguration: PersistedDiscussionLocalConfiguration.Structure { discussionStruct.localConfiguration }
        var ownedCryptoId: ObvCryptoId { discussionStruct.ownedCryptoId }
        var ownedIdentity: PersistedObvOwnedIdentity.Structure { discussionStruct.ownedIdentity }
        
        public init(objectPermanentID: ObvManagedObjectPermanentID<PersistedGroupDiscussion>, groupUID: Data, ownerIdentity: PersistedObvOwnedIdentity.Structure, contactGroup: PersistedContactGroup.Structure, discussionStruct: PersistedDiscussion.AbstractStructure) {
            self.objectPermanentID = objectPermanentID
            self.groupUID = groupUID
            self.ownerIdentity = ownerIdentity
            self.contactGroup = contactGroup
            self.discussionStruct = discussionStruct
        }
    }
    
    
    func toStruct() throws -> Structure {
        guard let groupUID = self.rawGroupUID, let objectPermanentID else {
            assertionFailure()
            throw Self.makeError(message: "Could not extract required attributes")
        }
        guard let contactGroup = self.contactGroup,
              let ownerIdentity = self.ownedIdentity else {
            assertionFailure()
            throw Self.makeError(message: "Could not extract required relationships")
        }
        let discussionStruct = try toAbstractStruct()
        return Structure(objectPermanentID: objectPermanentID,
                         groupUID: groupUID,
                         ownerIdentity: try ownerIdentity.toStruct(),
                         contactGroup: try contactGroup.toStruct(),
                         discussionStruct: discussionStruct)
    }

}


// MARK: - Thread safe struct for PersistedGroupV2Discussion

public extension PersistedGroupV2Discussion {
    
    struct Structure {
        let objectPermanentID: ObvManagedObjectPermanentID<PersistedGroupV2Discussion>
        let groupIdentifier: Data
        let ownerIdentity: PersistedObvOwnedIdentity.Structure
        public let group: PersistedGroupV2.Structure
        fileprivate let discussionStruct: PersistedDiscussion.AbstractStructure
        public var title: String { discussionStruct.title }
        var localConfiguration: PersistedDiscussionLocalConfiguration.Structure { discussionStruct.localConfiguration }
        var ownedCryptoId: ObvCryptoId { discussionStruct.ownedCryptoId }
        var ownedIdentity: PersistedObvOwnedIdentity.Structure { discussionStruct.ownedIdentity }
        
        public init(objectPermanentID: ObvManagedObjectPermanentID<PersistedGroupV2Discussion>, groupIdentifier: Data, ownerIdentity: PersistedObvOwnedIdentity.Structure, group: PersistedGroupV2.Structure, discussionStruct: PersistedDiscussion.AbstractStructure) {
            self.objectPermanentID = objectPermanentID
            self.groupIdentifier = groupIdentifier
            self.ownerIdentity = ownerIdentity
            self.group = group
            self.discussionStruct = discussionStruct
        }
    }
    
    
    func toStruct() throws -> Structure {
        guard let objectPermanentID else {
            assertionFailure()
            throw Self.makeError(message: "Could not extract value")
        }
        guard let group = self.group else {
            assertionFailure()
            throw Self.makeError(message: "Could not extract required relationships")
        }
        guard let ownerIdentity = self.ownedIdentity else {
            assertionFailure()
            throw Self.makeError(message: "Could not extract required relationships")
        }
        let discussionStruct = try toAbstractStruct()
        return Structure(objectPermanentID: objectPermanentID,
                         groupIdentifier: self.groupIdentifier,
                         ownerIdentity: try ownerIdentity.toStruct(),
                         group: try group.toStruct(),
                         discussionStruct: discussionStruct)
    }

}
