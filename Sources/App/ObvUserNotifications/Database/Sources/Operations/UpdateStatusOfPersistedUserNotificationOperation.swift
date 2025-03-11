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


/// This operation updates the status of a `PersistedUserNotification`.
///
/// This called, e.g., when the user taps a notification. In which case, the user notification will be deleted from the notification system by the OS. This operation allows to persist this status change.
public final class UpdateStatusOfPersistedUserNotificationOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private let requestIdentifier: String
    private let newStatus: PersistedUserNotification.Status
    
    public init(requestIdentifier: String, newStatus: PersistedUserNotification.Status) {
        self.requestIdentifier = requestIdentifier
        self.newStatus = newStatus
        super.init()
    }
    
    public override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            try PersistedUserNotification.updateStatus(to: newStatus, requestIdentifier: requestIdentifier, within: obvContext.context)
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
