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
import OlvidUtils
import ObvTypes
import os.log
import ObvUICoreData
import CoreData


/// This one-time operation recomputes the search keys for all contacts with personal notes, as we introduced storing personal notes in contact search keys on 2024-10-16.
/// This process is only required to be run once, as subsequent updates to personal notes will automatically trigger search key updates. Running this operation more than once is unnecessary.
final class RecomputeSortKeyOfContactsWithPersonalNoteOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            try PersistedObvContactIdentity.recomputeSortKeyOfContactsWithPersonalNote(within: obvContext.context)
            
        } catch {
            
            return cancel(withReason: .coreDataError(error: error))
            
        }
        
    }
    
}
