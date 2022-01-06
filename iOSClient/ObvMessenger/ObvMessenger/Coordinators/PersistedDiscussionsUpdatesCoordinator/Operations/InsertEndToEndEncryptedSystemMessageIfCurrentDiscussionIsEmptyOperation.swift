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
import os.log

final class InsertEndToEndEncryptedSystemMessageIfCurrentDiscussionIsEmptyOperation: ContextualOperationWithSpecificReasonForCancel<InsertEndToEndEncryptedSystemMessageIfCurrentDiscussionIsEmptyOperationReasonForCancel> {
    
    let discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>
    let markAsRead: Bool
    
    init(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, markAsRead: Bool) {
        self.discussionObjectID = discussionObjectID
        self.markAsRead = markAsRead
        super.init()
    }
    
    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        obvContext.performAndWait {
            
            do {
                guard let discussion = try PersistedDiscussion.get(objectID: discussionObjectID, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindDiscussion)
                }
                try discussion.insertSystemMessagesIfDiscussionIsEmpty(markAsRead: markAsRead)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
        }
        
    }
    
}


enum InsertEndToEndEncryptedSystemMessageIfCurrentDiscussionIsEmptyOperationReasonForCancel: LocalizedErrorWithLogType {
    
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
