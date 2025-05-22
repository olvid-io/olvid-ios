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
    
    case cryptoIdentityIsNotOwned // 0
    case cryptoIdentityIsNotContact // 1
    case contextIsNil // 2
    case invalidPhotoServerKeyEncodedRaw // 3
    case cannotDecodeEncodedEncryptionKey // 4
    case tryingToCreateContactGroupThatAlreadyExists // 5
    case inappropriateGroupInformation // 6
    case groupDoesNotExist // 7
    case contextMismatch // 8
    case pendingGroupMemberDoesNotExist // 9
    case anIdentityAppearsBothWithinPendingMembersAndGroupMembers // 10
    case contactCreationFailed // 11
    case groupIsNotOwned // 12
    case invalidGroupDetailsVersion // 13
    case ownedContactGroupStillHasMembersOrPendingMembers // 14
    case ownedIdentityNotFound // 15
    case ownedIdentityIsNotKeycloakManaged
    case diversificationDataCannotBeEmpty
    case failedToTurnRandomIntoSeed
    case delegateManagerIsNotSet
    case groupIsNotJoined
    case wrongSyncAtomRecipient
    case couldNotDecodeGroupIdentifier
    case contextCreatorIsNil
    case keycloakServerSignatureVerificationKeyIsNil
    case signatureVerificationFailed
    case parsingFailed
    case signaturePayloadVerificationFailed
    case keycloakUserIdIsNil
    case unbindIsRestricted
    case ownedIdentityIsInactive
    case unexpectedSyncSnapshotNode
    case unexpectedOwnedIdentity
    case ownedIdentityAlreadyExists
    
}
