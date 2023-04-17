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

final class CleanExpiredMuteNotficationEndDatesOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {

    override func main() {

        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

        obvContext.performAndWait {
            do {
                let allLocalConfigurations = try PersistedDiscussionLocalConfiguration.getAll(within: obvContext.context)
                for localConfiguration in allLocalConfigurations {
                    guard localConfiguration.isMuteNotificationsEndDateExpired else { continue }
                    localConfiguration.cleanExpiredMuteNotificationsEndDate()
                    assert(localConfiguration.currentMuteNotificationsEndDate == nil)
                    try? obvContext.addContextWillSaveCompletionHandler {
                        ObvMessengerInternalNotification.discussionLocalConfigurationHasBeenUpdated(newValue: .muteNotificationsDuration(.none), localConfigurationObjectID: localConfiguration.typedObjectID).postOnDispatchQueue()
                    }
                }
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
        }

    }

}
