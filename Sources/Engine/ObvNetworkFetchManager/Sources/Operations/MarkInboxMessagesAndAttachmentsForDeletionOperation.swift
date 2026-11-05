/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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


/// Marks a page of application messages, and all of their attachments, for deletion.
///
/// This is the bulk form of ``MarkInboxMessageAndAttachmentsForDeletionOperation``. It takes no ``InboxAttachmentsSet``, because a
/// per-attachment choice is expressed per message and so cannot be carried by a call that names many. The only caller wants every
/// attachment gone anyway.
final class MarkInboxMessagesAndAttachmentsForDeletionOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {

    private let messageIds: [ObvMessageIdentifier]

    private(set) var attachmentsMarkedForDeletion = [ObvAttachmentIdentifier]()

    init(messageIds: [ObvMessageIdentifier]) {
        self.messageIds = messageIds
        super.init()
    }

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        do {
            attachmentsMarkedForDeletion = try InboxMessage.markMessagesAndAttachmentsForDeletion(messageIds: messageIds, within: obvContext.context)
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
    }

}
