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

public enum ObvIdentityManagerError: Error {
    
    case cryptoIdentityIsNotOwned
    case cryptoIdentityIsNotContact
    case contextIsNil
    case invalidPhotoServerKeyEncodedRaw
    case cannotDecodeEncodedEncryptionKey
    case tryingToCreateContactGroupThatAlreadyExists
    case inappropriateGroupInformation
    case groupDoesNotExist
    case contextMismatch
    case pendingGroupMemberDoesNotExist
    case anIdentityAppearsBothWithinPendingMembersAndGroupMembers
    case contactCreationFailed
    case groupIsNotOwned
    case invalidGroupDetailsVersion
    case ownedContactGroupStillHasMembersOrPendingMembers
    case ownedIdentityNotFound
    case ownedIdentityIsNotKeycloakManaged
    case diversificationDataCannotBeEmpty
    case failedToTurnRandomIntoSeed
    case delegateManagerIsNotSet
    case groupIsNotJoined
    case wrongSyncAtomRecipient
    case couldNotDecodeGroupIdentifier
    case contextCreatorIsNil

    
    var localizedDescription: String {
        let message: String
        switch self {
        case .ownedIdentityIsNotKeycloakManaged:
            message = "Owned identity is not keycloak managed"
        case .cryptoIdentityIsNotOwned:
            message = "The crypto identity is not owned"
        case .cryptoIdentityIsNotContact:
            message = "The crypto identity is not a contact of the owned identity"
        case .contextIsNil:
            message = "Cannot find ObvContext"
        case .invalidPhotoServerKeyEncodedRaw:
            message = "The raw encoded server key is not a proper encoded value"
        case .cannotDecodeEncodedEncryptionKey:
            message = "The encoded AuthenticatedEncryptionKey failed to decode"
        case .tryingToCreateContactGroupThatAlreadyExists:
            message = "Trying to create a ContactGroup that already exists"
        case .inappropriateGroupInformation:
            message = "Inappropriate Group Information"
        case .groupDoesNotExist:
            message = "The group does not exist"
        case .contextMismatch:
            message = "Mismatch between two ObvContext that should be equal"
        case .pendingGroupMemberDoesNotExist:
            message = "Pending group member cannot be found"
        case .anIdentityAppearsBothWithinPendingMembersAndGroupMembers:
            message = "An identity appears both within the pending members and the group members"
        case .contactCreationFailed:
            message = "The contact creation failed"
        case .groupIsNotOwned:
            message = "Group is not one we own"
        case .invalidGroupDetailsVersion:
            message = "The version of the group details is inappropriate"
        case .ownedContactGroupStillHasMembersOrPendingMembers:
            message = "The owned contact group still has members or pending members"
        case .ownedIdentityNotFound:
            message = "Could not find owned identity"
        case .diversificationDataCannotBeEmpty:
            message = "Diversification data cannot be an empty array"
        case .failedToTurnRandomIntoSeed:
            message = "Failed to turn a random into a Seed instance"
        case .delegateManagerIsNotSet:
            message = "Delegate manager is not set"
        case .groupIsNotJoined:
            message = "Group is not one we joined"
        case .wrongSyncAtomRecipient:
            message = "Wrong sync atom recipient"
        case .couldNotDecodeGroupIdentifier:
            message = "Could not decode group identifier"
        case .contextCreatorIsNil:
            message = "Context creator is nil"
        }
        return message
    }
}
