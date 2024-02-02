/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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
final class DeleteOrphanedExpirationsOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            try PersistedMessageExpiration.deleteAllOrphanedExpirations(within: obvContext.context)
        } catch {
            assertionFailure(error.localizedDescription)
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}


extension PersistedMessageExpiration {

    static func deleteAllOrphanedExpirations(within context: NSManagedObjectContext) throws {
        try PersistedExpirationForReceivedMessageWithLimitedVisibility.deleteAllOrphaned(within: context)
        try PersistedExpirationForReceivedMessageWithLimitedExistence.deleteAllOrphaned(within: context)
        try PersistedExpirationForSentMessageWithLimitedVisibility.deleteAllOrphaned(within: context)
        try PersistedExpirationForSentMessageWithLimitedExistence.deleteAllOrphaned(within: context)
    }

}
