/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import OlvidUtils
import CoreData
import ObvTypes


final class CreateMissingPendingDeleteFromServerOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    private let messageId: ObvMessageIdentifier
    
    init(messageId: ObvMessageIdentifier) {
        self.messageId = messageId
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            guard let inboxMessage = try InboxMessage.get(messageId: messageId, within: obvContext) else { return }
            guard inboxMessage.canBeDeleted else { assertionFailure(); return }
            guard try !PendingDeleteFromServer.exists(for: inboxMessage) else { return }
            _ = PendingDeleteFromServer(messageId: messageId, within: obvContext)
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
        
    }
    
    
}
