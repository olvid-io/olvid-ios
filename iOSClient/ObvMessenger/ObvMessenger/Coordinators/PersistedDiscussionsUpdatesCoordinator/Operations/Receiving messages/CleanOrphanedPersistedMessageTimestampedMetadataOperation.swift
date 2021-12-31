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
import OlvidUtils
import os
import Darwin


final class CleanOrphanedPersistedMessageTimestampedMetadataOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "CleanOrphanedPersistedMessageTimestampedMetadataOperation")

    override func main() {
        
        os_log("Executing an CleanOrphanedPersistedMessageTimestampedMetadataOperation", log: log, type: .debug)

        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

        obvContext.performAndWait {
            
            do {
                let orphanedObjects = try PersistedMessageTimestampedMetadata.getOrphanedPersistedMessageTimestampedMetadata(within: obvContext)
                os_log("We found %d orphaned PersistedMessageTimestampedMetadata", log: log, type: .error, orphanedObjects.count)
                for object in orphanedObjects {
                    do {
                        try object.delete()
                    } catch {
                        os_log("An orphaned PersistedMessageTimestampedMetadata could not be deleted", log: log, type: .fault)
                    }
                }
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
            
        }
        
    }
    
}
