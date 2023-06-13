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
import CoreData
import ObvUICoreData


final class AddReplyToOnDraftOperation: ContextualOperationWithSpecificReasonForCancel<AddReplyToOnDraftOperationReasonForCancel> {
    
    public let messageObjectID: TypeSafeManagedObjectID<PersistedMessage>
    let draftObjectID: TypeSafeManagedObjectID<PersistedDraft>
    
    init(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) {
        self.messageObjectID = messageObjectID
        self.draftObjectID = draftObjectID
        super.init()
    }
    
    
    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        obvContext.performAndWait {
            do {
                guard let draft = try PersistedDraft.get(objectID: draftObjectID, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindDraftInDatabase)
                }
                guard let repliedTo = try PersistedMessage.get(with: messageObjectID, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindMessageInDatabase)
                }
                guard draft.discussion == repliedTo.discussion else {
                    return cancel(withReason: .incoherentDiscussion)
                }
                guard repliedTo is PersistedMessageReceived || repliedTo is PersistedMessageSent else {
                    return cancel(withReason: .repliedToMessageIsNeitherSentOrReceived)
                }
                draft.setReplyTo(to: repliedTo)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
        }
        
    }
    
}


enum AddReplyToOnDraftOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case contextIsNil
    case coreDataError(error: Error)
    case couldNotFindDraftInDatabase
    case couldNotFindMessageInDatabase
    case incoherentDiscussion
    case repliedToMessageIsNeitherSentOrReceived
    
    var logType: OSLogType {
        switch self {
        case .contextIsNil,
             .coreDataError,
             .incoherentDiscussion,
             .repliedToMessageIsNeitherSentOrReceived:
            return .fault
        case .couldNotFindDraftInDatabase,
             .couldNotFindMessageInDatabase:
            return .error
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .contextIsNil:
            return "The context is not set"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotFindDraftInDatabase:
            return "Could not find draft in database"
        case .couldNotFindMessageInDatabase:
            return "Could not find message in database"
        case .incoherentDiscussion:
            return "Incohrent discussion: the replied to message does not belong to the discussion corresponding to the draft"
        case .repliedToMessageIsNeitherSentOrReceived:
            return "The replied to message should be either a sent or a received message. The one processed is neither"
        }
    }

}
