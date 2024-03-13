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
import os.log
import CoreData
import ObvTypes
import OlvidUtils


final class DeletePendingDeleteFromServerAndInboxMessageAndAttachmentsOperation: ContextualOperationWithSpecificReasonForCancel<DeletePendingDeleteFromServerAndInboxMessageAndAttachmentsOperation.ReasonForCancel> {
    
    private let messageId: ObvMessageIdentifier
    private let inbox: URL

    init(messageId: ObvMessageIdentifier, inbox: URL) {
        self.messageId = messageId
        self.inbox = inbox
        super.init()
    }
    
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        do {
            
            try PendingDeleteFromServer.deletePendingDeleteFromServer(messageId: messageId, within: obvContext)
            
            guard let inboxMessage = try InboxMessage.get(messageId: messageId, within: obvContext) else { return }
            
            guard inboxMessage.canBeDeleted else {
                assertionFailure()
                return cancel(withReason: .messageConnotBeDeleted)
            }
            
            inboxMessage.attachments.forEach { attachment in
                try? attachment.deleteDownload(fromInbox: inbox, within: obvContext)
            }
            
            try? inboxMessage.deleteAttachmentsDirectory(fromInbox: inbox)

            try inboxMessage.deleteInboxMessage()

        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
    }
    
    
    public enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case coreDataError(error: Error)
        case messageConnotBeDeleted

        public var logType: OSLogType {
            switch self {
            case .coreDataError,
                    .messageConnotBeDeleted:
                return .fault
            }
        }

        public var errorDescription: String? {
            switch self {
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .messageConnotBeDeleted:
                return "Message cannot be deleted"
            }
        }

    }

}
