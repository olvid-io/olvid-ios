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
import OlvidUtils


final class CreateUnprocessedPersistedMessageSentFromInMemoryDraftOperation: OperationWithSpecificReasonForCancel<CreateUnprocessedPersistedMessageSentFromInMemoryDraftOperationReasonForCancel> {
    
    
    let inMemoryDraft: InMemoryDraft
    
    init(inMemoryDraft: InMemoryDraft) {
        self.inMemoryDraft = inMemoryDraft
        super.init()
    }
    
    private(set) var persistedMessageSentObjectID: NSManagedObjectID?

    override func main() {

        ObvStack.shared.performBackgroundTaskAndWait { (context) in

            inMemoryDraft.changeContext(to: context)
            
            // Create a PersistedMessageSent from the draft and reset the draft
            
            guard let persistedMessageSent = PersistedMessageSent(draft: inMemoryDraft) else {
                return cancel(withReason: .failedToCreatePersistedMessageSent)
            }
            
            inMemoryDraft.reset()

            // Save the context
            
            do {
                try context.save()
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
            self.persistedMessageSentObjectID = persistedMessageSent.objectID

        }
        
    }
}


enum CreateUnprocessedPersistedMessageSentFromInMemoryDraftOperationReasonForCancel: LocalizedErrorWithLogType {
    case failedToCreatePersistedMessageSent
    case coreDataError(error: Error)
    
    var logType: OSLogType {
        switch self {
        case .coreDataError, .failedToCreatePersistedMessageSent:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .coreDataError(error: let error): return "Core Data error: \(error.localizedDescription)"
        case .failedToCreatePersistedMessageSent: return "Could not create an instance of PersistedMessageSent"
        }
    }

}
