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
import ObvTypes
import ObvEngine
import OlvidUtils

final class CleanCallLogContactsOperation: OperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))

    override func main() {

        ObvStack.shared.performBackgroundTaskAndWait { context in
            let callLogContacts: [PersistedCallLogContact]
            do {
                callLogContacts = try PersistedCallLogContact.getCallLogsWithoutContacts(within: context)
            } catch(let error) {
                return cancel(withReason: .coreDataError(error: error))
            }

            var updatedItems = Set<TypeSafeManagedObjectID<PersistedCallLogItem>>()
            var updatedContacts: Int = 0
            for callLogContact in callLogContacts {
                assert(callLogContact.contactIdentity == nil)
                if let item = callLogContact.callLogItem {
                    item.incrementUnknownContactsCount()
                    updatedItems.insert(item.typedObjectID)
                    updatedContacts += 1
                }
                context.delete(callLogContact)
            }

            do {
                try context.save(logOnFailure: log)
            } catch(let error) {
                return cancel(withReason: .coreDataError(error: error))
            }

            os_log("Clean %{public}@ ContactLog(s) in %{public}@ LogItem(s)", log: log, type: .info, String(updatedContacts), String(updatedItems.count))

            for item in updatedItems {
                ObvMessengerInternalNotification.callLogItemWasUpdated(objectID: item).postOnDispatchQueue()
            }
        }

    }

}
