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
import ObvMetaManager
import ObvCrypto
import OlvidUtils
import ObvServerInterface

protocol BatchDeleteAndMarkAsListedDelegate {

    /// Tells the server, for each of the given messages, either that we are aware of it or that it can be deleted.
    ///
    /// The caller chooses the category per message. It is the only one that can: the decision turns on whether everything the server holds for a message is
    /// already in our database, and the authoritative account of what the server holds is the listing the caller has just received — not our own database, which
    /// may hold fewer attachments than the server does when an insertion failed.
    func markSpecificMessagesAsListedOrRequestTheirDeletion(ownedCryptoId: ObvCryptoIdentity, messageUIDsAndCategories: [ObvServerDeleteMessageAndAttachmentsMethod.MessageUIDAndCategory], flowId: FlowIdentifier) async throws

    func batchDeleteAndMarkAsListed(ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws

    func deleteInboxMessagesAssociatedToNonExistingOwnedIdentity(existingOwnedCryptoIds: Set<ObvCryptoIdentity>, flowId: FlowIdentifier) async throws

}
