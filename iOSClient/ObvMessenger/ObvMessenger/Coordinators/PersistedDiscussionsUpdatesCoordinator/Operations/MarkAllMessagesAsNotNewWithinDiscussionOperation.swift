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


final class MarkAllMessagesAsNotNewWithinDiscussionOperation: ContextualOperationWithSpecificReasonForCancel<MarkAllMessagesAsNotNewWithinDiscussionOperationReasonForCancel> {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))

    private let persistedDiscussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>?
    private let persistedDraftObjectID: TypeSafeManagedObjectID<PersistedDraft>?

    init(persistedDiscussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) {
        self.persistedDiscussionObjectID = persistedDiscussionObjectID
        self.persistedDraftObjectID = nil
        super.init()
    }

    init(persistedDraftObjectID: TypeSafeManagedObjectID<PersistedDraft>) {
        self.persistedDiscussionObjectID = nil
        self.persistedDraftObjectID = persistedDraftObjectID
        super.init()
    }

    override func main() {

        os_log("Executing a MarkAllMessagesAsNotNewWithinDiscussionOperation for discussion %{public}@", log: log, type: .debug, persistedDiscussionObjectID.debugDescription)

        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        obvContext.performAndWait {
            
            do {
                
                let discussion: PersistedDiscussion
                if let persistedDiscussionObjectID = self.persistedDiscussionObjectID {
                    guard let _discussion = try PersistedDiscussion.get(objectID: persistedDiscussionObjectID, within: obvContext.context) else {
                        return cancel(withReason: .couldNotFindDiscussion)
                    }
                    discussion = _discussion
                } else if let persistedDraftObjectID = self.persistedDraftObjectID {
                    guard let draft = try PersistedDraft.get(objectID: persistedDraftObjectID, within: obvContext.context) else {
                        return cancel(withReason: .couldNotFindDiscussion)
                    }
                    discussion = draft.discussion
                } else {
                    return cancel(withReason: .couldNotFindDiscussion)
                }
                
                try PersistedMessageReceived.markAllAsNotNew(within: discussion)
                try PersistedMessageSystem.markAllAsNotNew(within: discussion)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }

        }
        
    }
}


enum MarkAllMessagesAsNotNewWithinDiscussionOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case couldNotFindDiscussion
    case contextIsNil

    var logType: OSLogType {
        switch self {
        case .coreDataError,
             .contextIsNil:
            return .fault
        case .couldNotFindDiscussion:
            return .error
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .contextIsNil:
            return "Context is nil"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotFindDiscussion:
            return "Could not find discussion in database"
        }
    }

    
}
