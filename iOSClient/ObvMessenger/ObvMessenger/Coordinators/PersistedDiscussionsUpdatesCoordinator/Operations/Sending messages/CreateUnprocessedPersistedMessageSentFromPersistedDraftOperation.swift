/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvUICoreData


final class CreateUnprocessedPersistedMessageSentFromPersistedDraftOperation: ContextualOperationWithSpecificReasonForCancel<CreateUnprocessedPersistedMessageSentFromPersistedDraftOperationReasonForCancel>, UnprocessedPersistedMessageSentProvider {
    
    private let draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>
    
    private(set) var messageSentPermanentID: MessageSentPermanentID?

    init(draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>) {
        self.draftPermanentID = draftPermanentID
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        // Get the persisted draft to send
        
        let draftToSend: PersistedDraft
        do {
            guard let _draftToSend = try PersistedDraft.getManagedObject(withPermanentID: draftPermanentID, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindDraftInDatabase)
            }
            draftToSend = _draftToSend
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
        // Make sure the draft is not empty
        guard draftToSend.isNotEmpty else {
            assertionFailure()
            return cancel(withReason: .draftIsEmpty)
        }
        
        // Create a PersistedMessageSent from the draft and reset the draft
        
        let persistedMessageSent: PersistedMessageSent
        do {
            persistedMessageSent = try PersistedMessageSent.createPersistedMessageSentFromDraft(draftToSend)
        } catch {
            tryToResetDraftOnHardFailure(draftObjectID: draftToSend.typedObjectID)
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
        do {
            try obvContext.context.obtainPermanentIDs(for: [persistedMessageSent])
        } catch {
            assertionFailure()
            return cancel(withReason: .couldNotObtainPermanentIDForPersistedMessageSent)
        }
        
        let discussionPermanentID = draftToSend.discussion.discussionPermanentID
        let draftPermanentID = draftToSend.objectPermanentID
        
        draftToSend.reset()
        
        do {
            self.messageSentPermanentID = persistedMessageSent.objectPermanentID
            try obvContext.addContextDidSaveCompletionHandler { error in
                guard error == nil else { assertionFailure(); return }
                guard let draftPermanentID else { return }
                ObvMessengerInternalNotification.draftToSendWasReset(discussionPermanentID: discussionPermanentID, draftPermanentID: draftPermanentID)
                    .postOnDispatchQueue()
            }
        } catch {
            assertionFailure(error.localizedDescription)
        }
        
    }
    
    
    private func tryToResetDraftOnHardFailure(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) {
        ObvStack.shared.performBackgroundTaskAndWait { context in 
            guard let draftToReset = try? PersistedDraft.get(objectID: draftObjectID, within: context) else { return }
            draftToReset.reset()
            try? context.save()
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
