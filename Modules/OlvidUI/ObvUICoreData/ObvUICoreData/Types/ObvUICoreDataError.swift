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


public enum ObvUICoreDataError: Error {
    
    case inconsistentOneToOneDiscussionIdentifier
    case cannotInsertMessageInOneToOneDiscussionFromNonOneToOneContact
    case couldNotFindDiscussion
    case couldNotFindDiscussionWithId(discussionId: DiscussionIdentifier)
    case couldNotFindOwnedIdentity
    case couldNotFindGroupV1InDatabase(groupIdentifier: GroupV1Identifier)
    case couldNotFindGroupV2InDatabase(groupIdentifier: GroupV2Identifier)
    case couldNotDetemineGroupV1
    case couldNotDetemineGroupV2
    case couldNotFindPersistedMessage
    case couldNotFindPersistedMessageReceived
    case couldNotFindPersistedMessageSent
    case noContext
    case inappropriateContext
    case unexpectedFromContactIdentity
    case cannotUpdateConfigurationOfOneToOneDiscussionFromNonOneToOneContact
    case atLeastOneOfOneToOneIdentifierAndGroupIdentifierIsExpectedToBeNil
    case contactNeitherGroupOwnerNorPartOfGroupMembers
    case contactIsNotPartOfTheGroup
    case contactIsNotOneToOne
    case unexpectedOwnedCryptoId
    case ownedDeviceNotFound
    case couldNotDetermineTheOneToOneDiscussion
    case couldNotFindOneToOneContact
    case couldNotFindContact
    case couldNotFindContactWithId(contactIdentifier: ObvContactIdentifier)
    case couldNotFindDraft
    case couldNotDetermineContactCryptoId

    public var errorDescription: String? {
        switch self {
        case .couldNotDetemineGroupV1:
            return "Could not determine group V1"
        case .couldNotDetemineGroupV2:
            return "Could not determine group V2"
        case .inconsistentOneToOneDiscussionIdentifier:
            return "Inconsistent OneToOne discussion identifier"
        case .cannotInsertMessageInOneToOneDiscussionFromNonOneToOneContact:
            return "Cannot insert a message in a OneToOne discussion from a contact that is not OneToOne"
        case .couldNotFindDiscussion:
            return "Could not find discussion"
        case .couldNotFindDiscussionWithId:
            return "Could not find discussion given for the identifier"
        case .couldNotFindOwnedIdentity:
            return "Could not find the owned identity corresponding to this contact"
        case .couldNotFindGroupV1InDatabase:
            return "Could not find group V1 in database"
        case .couldNotFindGroupV2InDatabase:
            return "Could not find group V2 in database"
        case .noContext:
            return "No context available"
        case .couldNotFindPersistedMessageReceived:
            return "Could not find PersistedMessageReceived"
        case .unexpectedFromContactIdentity:
            return "UnexpectedFromContactIdentity"
        case .cannotUpdateConfigurationOfOneToOneDiscussionFromNonOneToOneContact:
            return "Cannot update OneToOne discussion shared settings sent by a contact that is not OneToOne"
        case .atLeastOneOfOneToOneIdentifierAndGroupIdentifierIsExpectedToBeNil:
            return "We expect at least one of OneOfOneToOneIdentifier and GroupIdentifier to be nil"
        case .contactNeitherGroupOwnerNorPartOfGroupMembers:
            return "This contact is not the group owner nor part of the group members"
        case .contactIsNotPartOfTheGroup:
            return "The contact is not part of the group"
        case .contactIsNotOneToOne:
            return "Contact is not OneToOne"
        case .inappropriateContext:
            return "Inappropriate context"
        case .unexpectedOwnedCryptoId:
            return "Unexpected owned cryptoId"
        case .ownedDeviceNotFound:
            return "Owned device not found"
        case .couldNotDetermineTheOneToOneDiscussion:
            return "Could not determine the OneToOne discussion"
        case .couldNotFindPersistedMessageSent:
            return "Could not find persisted message sent"
        case .couldNotFindPersistedMessage:
            return "Could not find persisted message"
        case .couldNotFindOneToOneContact:
            return "Could not find one2one contact"
        case .couldNotFindContact:
            return "Could not find contact"
        case .couldNotFindContactWithId:
            return "Could not find contact with Id"
        case .couldNotFindDraft:
            return "Could not find draft"
        case .couldNotDetermineContactCryptoId:
            return "Could not determine contact crypto id"
        }
    }

}
