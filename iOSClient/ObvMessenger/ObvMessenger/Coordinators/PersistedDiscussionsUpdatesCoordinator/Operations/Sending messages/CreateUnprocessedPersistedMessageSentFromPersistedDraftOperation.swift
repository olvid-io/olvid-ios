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


final class CreateUnprocessedPersistedMessageSentFromPersistedDraftOperation: ContextualOperationWithSpecificReasonForCancel<CreateUnprocessedPersistedMessageSentFromPersistedDraftOperationReasonForCancel> {
    
    private let persistedDraftObjectID: TypeSafeManagedObjectID<PersistedDraft>
    private(set) var persistedMessageSentObjectID: NSManagedObjectID?

    init(persistedDraftObjectID: TypeSafeManagedObjectID<PersistedDraft>) {
        self.persistedDraftObjectID = persistedDraftObjectID
        super.init()
    }
    
    override func main() {

        guard let obvContext = self.obvContext else {
            cancel(withReason: .contextIsNil)
            return
        }
        
        obvContext.performAndWait {
            
            // Get the persisted draft to send
            
            let draftToSend: PersistedDraft
            do {
                guard let _draftToSend = try PersistedDraft.get(objectID: persistedDraftObjectID, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindDraftInDatabase)
                }
                draftToSend = _draftToSend
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
            // Make sure the draft is not empty
            guard draftToSend.isNotEmpty else {
                return cancel(withReason: .draftIsEmpty)
            }
            
            // Create a PersistedMessageSent from the draft and reset the draft
            
            let persistedMessageSent: PersistedMessageSent
            do {
                persistedMessageSent = try PersistedMessageSent(draft: draftToSend)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
            do {
                try obvContext.context.obtainPermanentIDs(for: [persistedMessageSent])
            } catch {
                return cancel(withReason: .couldNotObtainPermanentIDForPersistedMessageSent)
            }
                        
            let discussionObjectID = draftToSend.discussion.typedObjectID
            let draftToSendObjectID = draftToSend.typedObjectID
            
            draftToSend.reset()

            do {
                self.persistedMessageSentObjectID = persistedMessageSent.objectID
                try obvContext.addContextDidSaveCompletionHandler { error in
                    guard error == nil else { assertionFailure(); return }
                    ObvMessengerInternalNotification.draftToSendWasReset(discussionObjectID: discussionObjectID, draftObjectID: draftToSendObjectID)
                        .postOnDispatchQueue()
                }
            } catch {
                assertionFailure(error.localizedDescription)
            }
            
        }
        
    }
    
}


enum CreateUnprocessedPersistedMessageSentFromPersistedDraftOperationReasonForCancel: LocalizedErrorWithLogType {
 
    case contextIsNil
    case couldNotObtainPermanentIDForPersistedMessageSent
    case couldNotFindDraftInDatabase
    case coreDataError(error: Error)
    case failedToCreatePersistedMessageSent
    case draftIsEmpty
    
    var logType: OSLogType {
        switch self {
        case .couldNotFindDraftInDatabase:
            return .error
        case .coreDataError, .failedToCreatePersistedMessageSent, .contextIsNil, .couldNotObtainPermanentIDForPersistedMessageSent, .draftIsEmpty:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .couldNotObtainPermanentIDForPersistedMessageSent: return "Could not obtain persisted permanent ID for PersistedMessageSent"
        case .contextIsNil: return "Context is nil"
        case .couldNotFindDraftInDatabase: return "Could not find the draft in database"
        case .coreDataError(error: let error): return "Core Data error: \(error.localizedDescription)"
        case .failedToCreatePersistedMessageSent: return "Could not create an instance of PersistedMessageSent"
        case .draftIsEmpty: return "Draft is empty"
        }
    }

}
