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
import OlvidUtils


final class DeleteOldOrOrphanedRemoteDeleteAndEditRequestsOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        obvContext.performAndWait {
            
            let deletionTimeInterval: TimeInterval = TimeInterval(30 * 24 * 60 * 60) // 30 days
            let deletionDate: Date = Date(timeIntervalSinceNow: -deletionTimeInterval)
            
            do {
                try RemoteDeleteAndEditRequest.deleteRequestsOlderThanDate(deletionDate, within: obvContext.context)
                try RemoteDeleteAndEditRequest.deleteOrphaned(within: obvContext.context)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
        }
        
    }
    
}
