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
import OlvidUtils

final class ReplaceDiscussionSharedExpirationConfigurationOperation: OperationWithSpecificReasonForCancel<UpdateDiscussionSharedExpirationConfigurationOperationReasonForCancel> {
    
    let persistedDiscussionObjectID: NSManagedObjectID
    let expirationJSON: ExpirationJSON
    let initiator: ObvCryptoId
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))

    init(persistedDiscussionObjectID: NSManagedObjectID, expirationJSON: ExpirationJSON, initiator: ObvCryptoId) {
        self.persistedDiscussionObjectID = persistedDiscussionObjectID
        self.expirationJSON = expirationJSON
        self.initiator = initiator
        super.init()
    }
    
    override func main() {
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in

            let discussion: PersistedDiscussion
            do {
                guard let _discussion = try PersistedDiscussion.get(objectID: persistedDiscussionObjectID, within: context) else {
                    return cancel(withReason: .discussionCannotBeFound)
                }
                discussion = _discussion
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
            do {
                guard try discussion.sharedConfiguration.replace(with: expirationJSON, initiator: initiator) else {
                    // There was nothing to do
                    return
                }
            } catch {
                return cancel(withReason: .failedToReplaceSharedConfiguration(error: error))
            }
            
            do {
                try context.save(logOnFailure: log)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }

        }
        
    }
}

enum UpdateDiscussionSharedExpirationConfigurationOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case discussionCannotBeFound
    case failedToReplaceSharedConfiguration(error: Error)
    
    var logType: OSLogType {
        switch self {
        case .coreDataError, .failedToReplaceSharedConfiguration:
            return .fault
        case .discussionCannotBeFound:
            return .error
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .discussionCannotBeFound:
            return "Could not find discussion in database"
        case .failedToReplaceSharedConfiguration(error: let error):
            return "Failed to replace shared config: \(error.localizedDescription)"
        }
    }

}
