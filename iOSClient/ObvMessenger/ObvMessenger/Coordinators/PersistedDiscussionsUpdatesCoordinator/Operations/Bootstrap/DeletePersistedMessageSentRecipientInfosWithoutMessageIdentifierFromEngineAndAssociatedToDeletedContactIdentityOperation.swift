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
import ObvEngine


/// This operation deletes all `PersistedMessageSentRecipientInfos` instances associated that have no `messageIdentifierFromEngine` and for which no `PersistedContactIdentity` can be found. It appropriately recompute the status of the associated messages.
///
/// This operation is typically called at bootstrap and is only needed if, for some reason, the `DeletePersistedMessageSentRecipientInfosWithoutMessageIdentifierFromEngineAndAssociatedToContactIdentityOperation`
/// failed.
final class DeletePersistedMessageSentRecipientInfosWithoutMessageIdentifierFromEngineAndAssociatedToDeletedContactIdentityOperation: Operation {
 
    enum ReasonForCancel: LocalizedError {
        case coreDataError(error: Error)
        
        var logType: OSLogType {
            switch self {
            case .coreDataError:
                return .fault
            }
        }
        
        var errorDescription: String? {
            switch self {
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            }
        }
        
    }

    func logReasonIfCancelled(log: OSLog) {
        assert(isFinished)
        guard isCancelled else { return }
        guard let reason = self.reasonForCancel else {
            os_log("%{public}@ cancelled without providing a reason. This is a bug", log: log, type: .fault, String(describing: self))
            assertionFailure()
            return
        }
        os_log("%{public}@ cancelled: %{public}@", log: log, type: reason.logType, String(describing: self), reason.localizedDescription)
        assertionFailure()
    }

    private(set) var reasonForCancel: ReasonForCancel?

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))

    private func cancel(withReason reason: ReasonForCancel) {
        assert(self.reasonForCancel == nil)
        self.reasonForCancel = reason
        self.cancel()
    }

    override func main() {
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in

            let infos: [PersistedMessageSentRecipientInfos]
            do {
                infos = try PersistedMessageSentRecipientInfos.getAllUnprocessed(within: context)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            

            var infosWithDeletedContact = [PersistedMessageSentRecipientInfos]()
            for info in infos {
                do {
                    let recipient = try info.getRecipient()
                    if recipient == nil {
                        infosWithDeletedContact.append(info)
                    }
                } catch {
                    os_log("Could not get contact: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    // We continue anyway
                }
            }
            
            guard !infosWithDeletedContact.isEmpty else { return }
            
            let associatedSentMessages = infosWithDeletedContact.map({ $0.messageSent })
            
            for info in infosWithDeletedContact {
                context.delete(info)
            }
            
            for message in associatedSentMessages {
                message.refreshStatus()
            }
            
            do {
                try context.save(logOnFailure: log)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
        }
        
    }

}
