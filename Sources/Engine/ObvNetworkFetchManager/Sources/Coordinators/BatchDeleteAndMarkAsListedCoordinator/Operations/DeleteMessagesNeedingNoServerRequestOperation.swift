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
import ObvTypes
import OlvidUtils
import ObvCrypto


/// Deletes the `InboxMessage` rows of messages the app is done with and that need no server request. See ``InboxMessage/GroundsForLocalDeletion`` for the two
/// reasons a row reaches this operation.
///
/// Under ``InboxMessage/GroundsForLocalDeletion/theServerHasConfirmed`` this is the second half of the early-deletion optimisation. A message with no
/// attachment and no extended payload is fully in this database the moment its row is committed, so the server is asked to delete it there and then, long
/// before the app has finished with it. The row survives that confirmation and records it (`deletedFromServer`); this operation is what finally removes the
/// row, once the app has marked the message for deletion. The invariant it rests on is that `deletedFromServer` is only ever set in response to a server
/// `.ok`: deleting a row on the strength of a request we merely *sent* would mean that a failed request left nothing behind to ask again.
final class DeleteMessagesNeedingNoServerRequestOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {

    private let messageIds: [ObvMessageIdentifier]
    private let grounds: InboxMessage.GroundsForLocalDeletion
    private let inbox: URL

    /// How many rows this operation deleted. This can be smaller than the number of `messageIds`, since some rows are skipped — see
    /// ``InboxMessage/deleteMessagesNeedingNoServerRequest(messageIds:grounds:inbox:within:)``. A value of 0 means that no row was deleted.
    private(set) var numberOfRowsDeleted = 0

    init(messageIds: [ObvMessageIdentifier], grounds: InboxMessage.GroundsForLocalDeletion, inbox: URL) {
        self.messageIds = messageIds
        self.grounds = grounds
        self.inbox = inbox
        super.init()
    }


    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {

        do {

            let (numberOfRowsDeleted, directoriesToDelete) = try InboxMessage.deleteMessagesNeedingNoServerRequest(messageIds: messageIds, grounds: grounds, inbox: inbox, within: obvContext.context)
            self.numberOfRowsDeleted = numberOfRowsDeleted

            // A message eligible for early deletion has no attachment, so on those grounds there should be no directory here at all; an inactive identity's
            // messages may have any number.
            try InboxMessage.removeAttachmentsDirectoriesOnceSaved(directoriesToDelete, within: obvContext)

        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }

    }

}
