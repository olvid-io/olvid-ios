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
import ObvAppTypes
import ObvTypes


extension ObvAppTypes.ReactionJSON {
    
    public init(persistedMessageToReact msg: PersistedMessage, emoji: String?, originalServerTimestamp: Date?) throws {
        guard let msgRef = msg.toMessageReferenceJSON() else {
            throw ReactionJSON.makeError(message: "Could not create MessageReferenceJSON")
        }
        guard let discussion = msg.discussion else {
            throw ReactionJSON.makeError(message: "Discussion is nil")
        }
        guard let discussionKind = try msg.discussion?.kind else {
            throw ReactionJSON.makeError(message: "Could not find discussion")
        }
        let oneToOneIdentifier: OneToOneIdentifierJSON?
        let groupV1Identifier: GroupV1Identifier?
        let groupV2Identifier: GroupV2Identifier?
        switch discussionKind {
        case .oneToOne:
            guard let ownedCryptoId = discussion.ownedIdentity?.cryptoId, let contactCryptoId = (discussion as? PersistedOneToOneDiscussion)?.contactIdentity?.cryptoId else {
                throw ReactionJSON.makeError(message: "Could not determine OneToOneIdentifierJSON")
            }
            oneToOneIdentifier = OneToOneIdentifierJSON(ownedCryptoId: ownedCryptoId, contactCryptoId: contactCryptoId)
            groupV1Identifier = nil
            groupV2Identifier = nil
        case .groupV1(withContactGroup: let contactGroup):
            guard let groupUid = contactGroup?.groupUid,
                  let groupOwnerIdentity = contactGroup?.ownerIdentity,
                  let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) else {
                      throw ReactionJSON.makeError(message: "Could not determine group v1 uid")
                  }
            oneToOneIdentifier = nil
            groupV1Identifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
            groupV2Identifier = nil
        case .groupV2(withGroup: let group):
            guard let _groupV2Identifier = group?.groupIdentifier else {
                throw ReactionJSON.makeError(message: "Could not determine group v2 uid")
            }
            oneToOneIdentifier = nil
            groupV1Identifier = nil
            groupV2Identifier = _groupV2Identifier
        }
        self.init(messageReference: msgRef,
                  oneToOneIdentifier: oneToOneIdentifier,
                  groupV1Identifier: groupV1Identifier,
                  groupV2Identifier: groupV2Identifier,
                  emoji: emoji,
                  originalServerTimestamp: originalServerTimestamp)
    }

}
