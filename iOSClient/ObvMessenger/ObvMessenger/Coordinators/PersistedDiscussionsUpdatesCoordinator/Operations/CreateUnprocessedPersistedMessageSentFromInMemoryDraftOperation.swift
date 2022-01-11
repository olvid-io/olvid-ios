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


final class CreateUnprocessedPersistedMessageSentFromInMemoryDraftOperation: OperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    
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
            
            let persistedMessageSent: PersistedMessageSent
            do {
                persistedMessageSent = try PersistedMessageSent(draft: inMemoryDraft)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
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
