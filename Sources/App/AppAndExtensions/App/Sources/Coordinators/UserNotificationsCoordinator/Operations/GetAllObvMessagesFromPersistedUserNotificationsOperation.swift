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
import ObvTypes
import ObvUserNotificationsDatabase


/// This operation is executed when the app is launched, in order to persist in the app database all the `ObvMessages` contained in persisted user notifications.
final class GetAllObvMessagesFromPersistedUserNotificationsOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private(set) var requestIdentifiersAndObvMessages = [(requestIdentifier: String, obvMessage: ObvMessage, obvMessageUpdate: ObvMessage?)]()
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            requestIdentifiersAndObvMessages = try PersistedUserNotification.getAllObvMessagesFromPersistedUserNotifications(within: obvContext.context)
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
