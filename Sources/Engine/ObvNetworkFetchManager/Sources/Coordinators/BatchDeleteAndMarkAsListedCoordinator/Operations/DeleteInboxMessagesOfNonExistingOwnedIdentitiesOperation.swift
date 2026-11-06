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
import CoreData
import ObvCrypto
import OlvidUtils


/// Deletes one page of the `InboxMessage` rows belonging to an owned identity that no longer exists.
///
/// A profile is deleted in two steps of the deletion protocol: the first asks this manager to mark every one of its messages for deletion, the second removes
/// the owned identity itself. What the first step starts is not awaited, so rows are routinely left marked and unswept once the identity has gone — and
/// nothing else in the engine removes them: there is no relationship between an `InboxMessage` and an `OwnedIdentity` to cascade along, and the bootstrap
/// sweeps orphaned attachments only. This operation is how they are collected, next to the server sessions and pending server queries of profiles that no
/// longer exist.
///
/// It deletes a row whatever state that row is in, which no other deletion here does. See
/// ``InboxMessage/deleteMessagesOfNonExistingOwnedIdentities(existingOwnedCryptoIds:fetchLimit:inbox:within:)`` for why that is right rather than merely
/// convenient.
final class DeleteInboxMessagesOfNonExistingOwnedIdentitiesOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {

    private let existingOwnedCryptoIds: Set<ObvCryptoIdentity>
    private let fetchLimit: Int
    private let inbox: URL

    /// How many rows this operation deleted. The caller pages until this is 0.
    private(set) var numberOfRowsDeleted = 0

    init(existingOwnedCryptoIds: Set<ObvCryptoIdentity>, fetchLimit: Int, inbox: URL) {
        self.existingOwnedCryptoIds = existingOwnedCryptoIds
        self.fetchLimit = fetchLimit
        self.inbox = inbox
        super.init()
    }


    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {

        do {

            let (numberOfRowsDeleted, directoriesToDelete) = try InboxMessage.deleteMessagesOfNonExistingOwnedIdentities(existingOwnedCryptoIds: existingOwnedCryptoIds, fetchLimit: fetchLimit, inbox: inbox, within: obvContext.context)
            self.numberOfRowsDeleted = numberOfRowsDeleted

            try InboxMessage.removeAttachmentsDirectoriesOnceSaved(directoriesToDelete, within: obvContext)

        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }

    }

}
