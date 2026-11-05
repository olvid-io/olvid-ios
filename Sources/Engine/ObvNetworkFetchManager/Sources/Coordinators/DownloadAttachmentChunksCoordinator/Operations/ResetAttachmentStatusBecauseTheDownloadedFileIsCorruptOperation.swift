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


/// Discards the file of an attachment this manager reported as complete, and puts every one of its chunks back to be fetched again.
///
/// The sibling ``ResetAttachmentStatusIfCurrentStatusIsDownloadedAndFileIsNotAvailableOperation`` covers the case where the file has gone; this one covers a
/// file that is there and whose bytes are wrong, which the app finds by hashing it and which that sibling declines by design.
final class ResetAttachmentStatusBecauseTheDownloadedFileIsCorruptOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {

    private let attachmentId: ObvAttachmentIdentifier
    private let inbox: URL

    init(attachmentId: ObvAttachmentIdentifier, inbox: URL) {
        self.attachmentId = attachmentId
        self.inbox = inbox
        super.init()
    }

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {

        do {
            guard let attachment = try InboxAttachment.get(attachmentId: attachmentId, within: obvContext.context) else { return }
            try attachment.resetStatusBecauseTheDownloadedFileIsCorrupt(withinInbox: inbox)
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }

    }

}
