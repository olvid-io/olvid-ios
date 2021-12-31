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
import os.log
import OlvidUtils


final class ReportEndCallOperation: OperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: ReportEndCallOperation.self))

    let callUUID: UUID

    init(callUUID: UUID) {
        self.callUUID = callUUID

        super.init()
    }

    override func main() {

        ObvStack.shared.performBackgroundTaskAndWait { context in
            os_log("☎️📖 Report ended call", log: log, type: .info)

            let item: PersistedCallLogItem
            do {
                if let _item = try PersistedCallLogItem.get(callUUID: callUUID, within: context) {
                    item = _item
                } else {
                    return
                }
            } catch(let error) {
                return cancel(withReason: .coreDataError(error: error))
            }

            guard item.endDate == nil else {
                os_log("☎️📖 Call endDate was been already set", log: log, type: .info)
                assertionFailure()
                return
            }

            item.endDate = Date()

            do {
                try context.save(logOnFailure: log)
            } catch(let error) {
                return cancel(withReason: .coreDataError(error: error))
            }

            ObvMessengerInternalNotification.callLogItemWasUpdated(objectID: item.typedObjectID).postOnDispatchQueue()
        }

    }

}
