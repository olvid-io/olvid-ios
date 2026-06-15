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


extension ObvAppTypes.DeleteMessagesJSON {
    
    public init(persistedMessagesToDelete: [PersistedMessage]) throws {
        
        guard !persistedMessagesToDelete.isEmpty else { throw DeleteMessagesJSON.makeError(message: "No message to delete") }
        
        let discussion: PersistedDiscussion
        do {
            let discussions = Set(persistedMessagesToDelete.compactMap { $0.discussion })
            guard discussions.count == 1 else {
                throw DeleteMessagesJSON.makeError(message: "Could not construct DeleteMessagesJSON. Expecting one discussion, got \(discussions.count)")
            }
            guard let _discussion = discussions.first else {
                throw DeleteMessagesJSON.makeError(message: "Could not construct DeleteMessagesJSON. Expecting one discussion")
            }
            discussion = _discussion
        }

        let messagesToDelete = persistedMessagesToDelete.compactMap { $0.toMessageReferenceJSON() }
        switch try discussion.kind {
        case .oneToOne:
            guard let ownedCryptoId = discussion.ownedIdentity?.cryptoId, let contactCryptoId = (discussion as? PersistedOneToOneDiscussion)?.contactIdentity?.cryptoId else {
                throw DeleteMessagesJSON.makeError(message: "Could not determine OneToOneIdentifierJSON")
            }
            let oneToOneIdentifier = OneToOneIdentifierJSON(ownedCryptoId: ownedCryptoId, contactCryptoId: contactCryptoId)
            self.init(oneToOneIdentifier: oneToOneIdentifier, messagesToDelete: messagesToDelete)
        case .groupV1(withContactGroup: let contactGroup):
            guard let groupUid = contactGroup?.groupUid,
                  let groupOwnerIdentity = contactGroup?.ownerIdentity,
                  let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) else {
                throw DeleteMessagesJSON.makeError(message: "Could not determine group v1 id")
            }
            self.init(groupV1Identifier: .init(groupUid: groupUid, groupOwner: groupOwner), messagesToDelete: messagesToDelete)
        case .groupV2(withGroup: let group):
            guard let groupV2Identifier = group?.groupIdentifier else {
                throw DeleteMessagesJSON.makeError(message: "Could not determine group v2 id")
            }
            self.init(groupV2Identifier: groupV2Identifier, messagesToDelete: messagesToDelete)
        }
        
    }
    
}
