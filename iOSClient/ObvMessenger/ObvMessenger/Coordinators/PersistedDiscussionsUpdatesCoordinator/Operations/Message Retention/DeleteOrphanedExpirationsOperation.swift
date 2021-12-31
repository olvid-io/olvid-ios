/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import os.log
import OlvidUtils


/// This operations deletes all orphaned expirations, i.e., expirations that have no associated message.
///
/// This operation deletes all the instances of
///
/// - `PersistedExpirationForReceivedMessageWithLimitedVisibility`
/// - `PersistedExpirationForReceivedMessageWithLimitedExistence`
/// - `PersistedExpirationForSentMessageWithLimitedVisibility`
/// - `PersistedExpirationForSentMessageWithLimitedExistence`
///
/// that have no associated received/sent message. Note that the we could expect not to find any such instance, thanks to the cascade delete feature of Core Data.
/// In practice, cleaning these instances proved to be useful.
final class DeleteOrphanedExpirationsOperation: OperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))

    override func main() {
        
        ObvStack.shared.performBackgroundTaskAndWait { context in
            
            do {
                try PersistedMessageExpiration.deleteAllOrphanedExpirations(within: context)
                try context.save(logOnFailure: log)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
        }
        
    }
    
}
