/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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


extension PollVoteJSON {
    
    public init(persistedMessageToReact msg: PersistedMessage, pollCandidateUuid: UUID, voted: Bool, version: Int, originalServerTimestamp: Date?) throws {
        
        guard let messageReference = msg.toMessageReferenceJSON() else {
            throw PollVoteJSON.makeError(message: "Could not create MessageReferenceJSON")
        }
        guard let discussion = msg.discussion else {
            throw PollVoteJSON.makeError(message: "Discussion is nil")
        }
        guard let discussionKind = try msg.discussion?.kind else {
            throw PollVoteJSON.makeError(message: "Could not find discussion")
        }
        
        switch discussionKind {
        case .oneToOne:
            guard let ownedCryptoId = discussion.ownedIdentity?.cryptoId, let contactCryptoId = (discussion as? PersistedOneToOneDiscussion)?.contactIdentity?.cryptoId else {
                throw PollVoteJSON.makeError(message: "Could not determine OneToOneIdentifierJSON")
            }
            let oneToOneIdentifier = OneToOneIdentifierJSON(ownedCryptoId: ownedCryptoId, contactCryptoId: contactCryptoId)
            self.init(messageReference: messageReference,
                      oneToOneIdentifier: oneToOneIdentifier,
                      groupV1Identifier: nil,
                      groupV2Identifier: nil,
                      pollCandidateUuid: pollCandidateUuid,
                      voted: voted,
                      version: version,
                      originalServerTimestamp: originalServerTimestamp)
            
        case .groupV1(withContactGroup: let contactGroup):
            guard let groupUid = contactGroup?.groupUid,
                  let groupOwnerIdentity = contactGroup?.ownerIdentity,
                  let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) else {
                      throw PollVoteJSON.makeError(message: "Could not determine group v1 uid")
                  }
            let groupV1Identifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
            self.init(messageReference: messageReference,
                      oneToOneIdentifier: nil,
                      groupV1Identifier: groupV1Identifier,
                      groupV2Identifier: nil,
                      pollCandidateUuid: pollCandidateUuid,
                      voted: voted,
                      version: version,
                      originalServerTimestamp: originalServerTimestamp)

        case .groupV2(withGroup: let group):
            guard let groupV2Identifier = group?.groupIdentifier else {
                throw PollVoteJSON.makeError(message: "Could not determine group v2 uid")
            }
            self.init(messageReference: messageReference,
                      oneToOneIdentifier: nil,
                      groupV1Identifier: nil,
                      groupV2Identifier: groupV2Identifier,
                      pollCandidateUuid: pollCandidateUuid,
                      voted: voted,
                      version: version,
                      originalServerTimestamp: originalServerTimestamp)
        }
    }

}
