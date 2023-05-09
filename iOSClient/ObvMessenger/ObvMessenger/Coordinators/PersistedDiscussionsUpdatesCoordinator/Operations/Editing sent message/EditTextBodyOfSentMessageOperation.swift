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

final class EditTextBodyOfSentMessageOperation: ContextualOperationWithSpecificReasonForCancel<EditTextBodyOfSentMessageOperationReasonForCancel> {

    private let persistedSentMessageObjectID: NSManagedObjectID
    private let newTextBody: String?
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: EditTextBodyOfSentMessageOperation.self))

    init(persistedSentMessageObjectID: NSManagedObjectID, newTextBody: String?) {
        self.persistedSentMessageObjectID = persistedSentMessageObjectID
        self.newTextBody = newTextBody
        super.init()
    }

    override func main() {

        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        obvContext.performAndWait {
            
            let messageSent: PersistedMessageSent
            do {
                guard let _messageSent = try PersistedMessageSent.get(with: persistedSentMessageObjectID, within: obvContext.context) as? PersistedMessageSent else {
                    return cancel(withReason: .cannotFindMessageSent)
                }
                messageSent = _messageSent
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
            // If we reach this point, we can edit the text body
            
            do {
                try messageSent.editTextBody(newTextBody: newTextBody)
            } catch {
                return cancel(withReason: .failedToEditTextBody(error: error))
            }
            
            // If the message appears as a reply-to in some other messages, we must refresh those messages in the view context
            // Similarly, if a draft is replying to this message, we must refresh the draft in the view context

            do {
                let repliesObjectIDs = messageSent.repliesObjectIDs.map({ $0.objectID })
                let draftObjectIDs = try PersistedDraft.getObjectIDsOfAllDraftsReplyingTo(message: messageSent).map({ $0.objectID })
                let objectIDsToRefresh = repliesObjectIDs + draftObjectIDs
                if !objectIDsToRefresh.isEmpty {
                    try? obvContext.addContextDidSaveCompletionHandler { error in
                        guard error == nil else { return }
                        DispatchQueue.main.async {
                            let objectsToRefresh = ObvStack.shared.viewContext.registeredObjects
                                .filter({ objectIDsToRefresh.contains($0.objectID) })
                            objectsToRefresh.forEach { objectID in
                                ObvStack.shared.viewContext.refresh(objectID, mergeChanges: true)
                            }
                        }
                    }
                }
            } catch {
                assertionFailure()
                // In production, continue anyway
            }
            
        }
        
    }
    
}


enum EditTextBodyOfSentMessageOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case cannotFindMessageSent
    case failedToEditTextBody(error: Error)
    case contextIsNil

    var logType: OSLogType {
        switch self {
        case .coreDataError,
             .cannotFindMessageSent,
             .failedToEditTextBody,
             .contextIsNil:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .contextIsNil:
            return "Context is nil"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .cannotFindMessageSent:
            return "Cannot find message sent to edit"
        case .failedToEditTextBody(error: let error):
            return "Failed to edit text body: \(error.localizedDescription)"
        }
    }

}
