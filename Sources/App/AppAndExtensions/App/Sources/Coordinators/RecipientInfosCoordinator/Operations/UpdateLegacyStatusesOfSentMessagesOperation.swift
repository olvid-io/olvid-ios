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
import OlvidUtils
import ObvUICoreData


/// Called during bootstrap, to make sure all ``PersistedMessageSent`` have an appropriate status.
///
/// In version 3.1, we introduced new statuses for a ``PersistedMessageSent``. This operation updates the statuses of all ``PersistedMessageSent`` that require it.
final class UpdateLegacyStatusesOfSentMessagesOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private(set) var didSaveSomeChanges = false
    
    private let maxNumberOfChanges: Int
    
    init(maxNumberOfChanges: Int) {
        self.maxNumberOfChanges = maxNumberOfChanges
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            try PersistedMessageSent.updateLegacyStatuses(within: obvContext.context, maxNumberOfChanges: maxNumberOfChanges)
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
        didSaveSomeChanges = obvContext.context.hasChanges
        
    }
    
}
