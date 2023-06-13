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
import ObvUICoreData


final class CreateRandomDraftDebugOperation: ContextualOperationWithSpecificReasonForCancel<CreateRandomDraftDebugOperationReasonForCancel> {
    
    private let discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>
    
    init(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) {
        self.discussionObjectID = discussionObjectID
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
                
                discussion.draft.reset()
                
                let randomBodySize = Int.random(in: Range<Int>.init(uncheckedBounds: (lower: 2, upper: 200)))
                let randomBody = CreateRandomDraftDebugOperation.randomString(length: randomBodySize)
                discussion.draft.replaceContentWith(newBody: randomBody, newMentions: Set<MessageJSON.UserMention>())
                
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
        }
        
    }
    
    
    static func randomString(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789                  "
        return String((0...length-1).map { _ in letters.randomElement()! })
    }

    
}


enum CreateRandomDraftDebugOperationReasonForCancel: LocalizedErrorWithLogType {

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
