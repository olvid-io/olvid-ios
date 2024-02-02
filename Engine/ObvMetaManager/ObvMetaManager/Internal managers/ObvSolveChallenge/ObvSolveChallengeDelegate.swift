/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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
import OlvidUtils
import ObvTypes
import ObvEncoder

public protocol ObvSolveChallengeDelegate: ObvManager {
    
    func solveChallenge(_ challengeType: ChallengeType, for: ObvCryptoIdentity, using: PRNGService, within obvContext: ObvContext) throws -> Data
    
    // func getApiKeyForOwnedIdentity(_: ObvCryptoIdentity, within obvContext: ObvContext) throws -> UUID?
}


public struct ObvSolveChallengeStruct {
    
    public static func checkResponse(_ response: Data, to challengeType: ChallengeType, from identity: ObvCryptoIdentity) -> Bool {
        let serverAuth = ObvCryptoSuite.sharedInstance.authentication()
        return serverAuth.check(response: response, toChallenge: challengeType.challenge, prefixedWith: challengeType.challengePrefix, using: identity.publicKeyForAuthentication)
    }

    public static func solveChallenge(_ challengeType: ChallengeType, with privateKey: PrivateKeyForAuthentication, using prng: PRNGService) -> Data? {
        let serverAuth = ObvCryptoSuite.sharedInstance.authentication()
        return serverAuth.solve(challengeType.challenge, prefixedWith: challengeType.challengePrefix, with: privateKey, using: prng)
    }

    public static func solveChallenge(_ challengeType: ChallengeType, with privateKey: PrivateKeyForAuthentication, and publicKey: PublicKeyForAuthentication, using prng: PRNGService) -> Data? {
        let serverAuth = ObvCryptoSuite.sharedInstance.authentication()
        return serverAuth.solve(challengeType.challenge, prefixedWith: challengeType.challengePrefix, with: privateKey, and: publicKey, using: prng)
    }

}


// Prefix for challenges
public enum ChallengeType {

    case groupV2AdministratorsChain(rawInnerData: Data)
    case mutualIntroduction(mediatorIdentity: ObvCryptoIdentity, firstIdentity: ObvCryptoIdentity, secondIdentity: ObvCryptoIdentity)
    case mutualScan(firstIdentity: ObvCryptoIdentity, secondIdentity: ObvCryptoIdentity)
    case authentChallenge(challengeFromServer: Data)
    case channelCreation(firstDeviceUid: UID, secondDeviceUid: UID, firstIdentity: ObvCryptoIdentity, secondIdentity: ObvCryptoIdentity)
    case groupBlob(rawEncodedBlob: Data)
    case groupLeaveNonce(groupIdentifier: GroupV2.Identifier, groupInvitationNonce: Data)
    case groupDelete
    case groupJoinNonce(groupIdentifier: GroupV2.Identifier, groupInvitationNonce: Data, recipientIdentity: ObvCryptoIdentity)
    case groupLockNonce(lockNonce: Data)
    case groupUpdate(lockNonce: Data, encryptedBlob: EncryptedData, encodedServerAdminPublicKey: ObvEncoded)
    case groupKick(encryptedAdministratorChain: EncryptedData, groupInvitationNonce: Data)
    case ownedIdentityDeletion(notifiedContactIdentity: ObvCryptoIdentity)

    public var challengePrefix: Data {
        switch self {
        case .groupV2AdministratorsChain:
            return "groupAdministratorsChain".data(using: .utf8)!
        case .mutualIntroduction:
            return "mutualIntroduction".data(using: .utf8)!
        case .mutualScan:
            return "mutualScan".data(using: .utf8)!
        case .authentChallenge:
            return "authentChallenge".data(using: .utf8)!
        case .channelCreation:
            return "channelCreation".data(using: .utf8)!
        case .groupBlob:
            return "groupBlob".data(using: .utf8)!
        case  .groupLeaveNonce:
            return "groupLeave".data(using: .utf8)!
        case .groupDelete:
            return "deleteGroup".data(using: .utf8)!
        case .groupJoinNonce:
            return "joinGroup".data(using: .utf8)!
        case .groupLockNonce:
            return "lockNonce".data(using: .utf8)!
        case .groupUpdate:
            return "updateGroup".data(using: .utf8)!
        case .groupKick:
            return "groupKick".data(using: .utf8)!
        case .ownedIdentityDeletion:
            return "ownedIdentityDeletion".data(using: .utf8)!
        }
    }
    
    public var challenge: Data {
        switch self {
        case .groupV2AdministratorsChain(rawInnerData: let rawInnerData):
            return rawInnerData
        case .mutualIntroduction(mediatorIdentity: let mediatorIdentity, firstIdentity: let firstIdentity, secondIdentity: let secondIdentity):
            return mediatorIdentity.getIdentity() + firstIdentity.getIdentity() + secondIdentity.getIdentity()
        case .mutualScan(firstIdentity: let firstIdentity, secondIdentity: let secondIdentity):
            return firstIdentity.getIdentity() + secondIdentity.getIdentity()
        case .authentChallenge(challengeFromServer: let challengeFromServer):
            return challengeFromServer
        case .channelCreation(firstDeviceUid: let firstDeviceUid, secondDeviceUid: let secondDeviceUid, firstIdentity: let firstIdentity, secondIdentity: let secondIdentity):
            return firstDeviceUid.raw + secondDeviceUid.raw + firstIdentity.getIdentity() + secondIdentity.getIdentity()
        case .groupBlob(rawEncodedBlob: let rawEncodedBlob):
            return rawEncodedBlob
        case .groupLeaveNonce(groupIdentifier: let groupIdentifier, groupInvitationNonce: let groupInvitationNonce):
            return groupIdentifier.obvEncode().rawData + groupInvitationNonce
        case .groupDelete:
            return Data()
        case .groupJoinNonce(groupIdentifier: let groupIdentifier, groupInvitationNonce: let groupInvitationNonce, recipientIdentity: let recipientIdentity):
            return groupIdentifier.obvEncode().rawData + groupInvitationNonce + recipientIdentity.getIdentity()
        case .groupLockNonce(lockNonce: let lockNonce):
            return lockNonce
        case .groupUpdate(lockNonce: let lockNonce, encryptedBlob: let encryptedBlob, encodedServerAdminPublicKey: let encodedServerAdminPublicKey):
            return lockNonce + encryptedBlob.raw + encodedServerAdminPublicKey.rawData
        case .groupKick(encryptedAdministratorChain: let encryptedAdministratorChain, groupInvitationNonce: let groupInvitationNonce):
            return encryptedAdministratorChain.raw + groupInvitationNonce
        case .ownedIdentityDeletion(notifiedContactIdentity: let notifiedContactIdentity):
            return notifiedContactIdentity.getIdentity()
        }
    }

}
