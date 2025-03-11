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
import os.log
import CoreData
import OlvidUtils
import ObvUICoreData


final class PerformAdditionalStepsAfterBackupRestorationOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private let log: OSLog
    
    init(log: OSLog) {
        self.log = log
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            let discussions = try PersistedDiscussion.getAllActiveDiscussionsForAllOwnedIdentities(within: obvContext.context)
            for discussion in discussions {
                discussion.insertUpdatedDiscussionSharedSettingsSystemMessageIfRequired(markAsRead: true)
            }
        } catch {
            os_log("Cannot insert current discussion shared configuration system message: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
            // Continue anyway
        }

    }
    
}
