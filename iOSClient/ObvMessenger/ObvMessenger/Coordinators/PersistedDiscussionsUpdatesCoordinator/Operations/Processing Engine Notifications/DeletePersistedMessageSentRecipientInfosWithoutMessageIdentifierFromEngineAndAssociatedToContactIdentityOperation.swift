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
import ObvEngine


/// This operation deletes all `PersistedMessageSentRecipientInfos` instances associated to the contact identity the  that have no `messageIdentifierFromEngine`. It appropriately recompute the status of the associated messages.
///
/// This operation is typically called when a contact is deleted. Yet, we do not test whether the contact is indeed deleted since, when receiving the information from the engine, the `PersistedObvContactIdentity` might not have been deleted already.
final class DeletePersistedMessageSentRecipientInfosWithoutMessageIdentifierFromEngineAndAssociatedToContactIdentityOperation: Operation {
 
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

    private let obvContactIdentity: ObvContactIdentity
    
    init(obvContactIdentity: ObvContactIdentity) {
        self.obvContactIdentity = obvContactIdentity
        super.init()
    }
    
    override func main() {
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in

            let infos: [PersistedMessageSentRecipientInfos]
            do {
                infos = try PersistedMessageSentRecipientInfos.getAllUnprocessedForSpecificContact(obvContactIdentity, within: context)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
            guard !infos.isEmpty else { return }
            
            let associatedSentMessages = infos.map({ $0.messageSent })
            
            for info in infos {
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
