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
import ObvUICoreDataStructs


// MARK: - Thread safe struct for PersistedDiscussion

extension PersistedDiscussion {
    
    public func toStructureKind() throws -> PersistedDiscussionAbstractStructure.StructureKind {
        switch try kind {
        case .oneToOne:
            guard let oneToOneDiscussion = self as? PersistedOneToOneDiscussion else {
                throw ObvUICoreDataError.unexpectedDiscussionKind
            }
            let structure = try oneToOneDiscussion.toStructure()
            return .oneToOneDiscussion(structure: structure)
        case .groupV1:
            guard let groupDiscussion = self as? PersistedGroupDiscussion else {
                throw ObvUICoreDataError.unexpectedDiscussionKind
            }
            let structure = try groupDiscussion.toStructure()
            return .groupDiscussion(structure: structure)
        case .groupV2:
            guard let groupV2Discussion = self as? PersistedGroupV2Discussion else {
                throw ObvUICoreDataError.unexpectedDiscussionKind
            }
            let structure = try groupV2Discussion.toStructure()
            return .groupV2Discussion(structure: structure)
        }
    }
    
    
    public func toAbstractStructure() throws -> PersistedDiscussionAbstractStructure {
        guard let ownedIdentityStruct = try ownedIdentity?.toStructure() else { assertionFailure(); throw ObvUICoreDataError.ownedIdentityIsNil }
        return .init(ownedIdentity: ownedIdentityStruct,
                     title: self.title,
                     localConfiguration: self.localConfiguration.toStructure())
    }

}


// MARK: - Thread safe struct for PersistedOneToOneDiscussion

extension PersistedOneToOneDiscussion {
    
    public func toStructure() throws -> PersistedOneToOneDiscussionStructure {
        guard let contactIdentity = self.contactIdentity else {
            assertionFailure()
            throw ObvUICoreDataError.contactIdentityIsNil
        }
        let discussionStruct = try toAbstractStructure()
        return .init(contactIdentity: try contactIdentity.toStructure(),
                     discussionStruct: discussionStruct)

    }
    
}


// MARK: - Thread safe struct for PersistedGroupDiscussion

public extension PersistedGroupDiscussion {
    
    func toStructure() throws -> PersistedGroupDiscussionStructure {
        guard let groupUID = self.rawGroupUID else {
            assertionFailure()
            throw ObvUICoreDataError.couldNotExtractRequiredAttributes
        }
        guard let contactGroup = self.contactGroup,
              let ownerIdentity = self.ownedIdentity else {
            assertionFailure()
            throw ObvUICoreDataError.couldNotExtractRequiredRelationships
        }
        let discussionStruct = try toAbstractStructure()
        return .init(groupUID: groupUID,
                     ownerIdentity: try ownerIdentity.toStructure(),
                     contactGroup: try contactGroup.toStructure(),
                     discussionStruct: discussionStruct)
    }

}


// MARK: - Thread safe struct for PersistedGroupV2Discussion

public extension PersistedGroupV2Discussion {
    
    func toStructure() throws -> PersistedGroupV2DiscussionStructure {
        guard let group = self.group else {
            assertionFailure()
            throw ObvUICoreDataError.groupV2IsNil
        }
        guard let ownerIdentity = self.ownedIdentity else {
            assertionFailure()
            throw ObvUICoreDataError.ownedIdentityIsNil
        }
        let discussionStruct = try toAbstractStructure()
        return .init(groupIdentifier: self.groupIdentifier,
                     ownerIdentity: try ownerIdentity.toStructure(),
                     group: try group.toStructure(),
                     discussionStruct: discussionStruct)
    }

}
