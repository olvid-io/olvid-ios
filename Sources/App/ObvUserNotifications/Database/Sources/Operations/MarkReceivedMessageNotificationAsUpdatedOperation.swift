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
import CoreData
import OlvidUtils
import ObvAppTypes
import ObvTypes


public final class MarkReceivedMessageNotificationAsUpdatedOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private let messageAppIdentifier: ObvMessageAppIdentifier
    private let dateOfUpdate: Date // Message upload timestamp of the update
    private let newRequestIdentifier: String
    private let obvMessageUpdate: ObvMessage
    
    public init(messageAppIdentifier: ObvMessageAppIdentifier, dateOfUpdate: Date, newRequestIdentifier: String, obvMessageUpdate: ObvMessage) {
        self.messageAppIdentifier = messageAppIdentifier
        self.dateOfUpdate = dateOfUpdate
        self.newRequestIdentifier = newRequestIdentifier
        self.obvMessageUpdate = obvMessageUpdate
        super.init()
    }
    
    public private(set) var previousRequestIdentifier: String?
    
    public override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            previousRequestIdentifier = try PersistedUserNotification.markReceivedMessageNotificationAsUpdated(
                messageAppIdentifier: messageAppIdentifier,
                dateOfUpdate: dateOfUpdate,
                newRequestIdentifier: newRequestIdentifier,
                obvMessageUpdate: obvMessageUpdate,
                within: obvContext.context)
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
