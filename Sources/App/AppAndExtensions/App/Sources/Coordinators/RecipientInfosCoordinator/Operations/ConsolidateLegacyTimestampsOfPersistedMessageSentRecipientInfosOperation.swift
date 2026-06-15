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


/// Called during bootstrap, to make sure all ``PersistedMessageSentRecipientInfos`` have consolidated timestamps.
///
/// Before version 3.1, it was possible to find ``PersistedMessageSentRecipientInfos`` with a non-nil `timestampDelivered`, but a nil `timestampMessageSent`. This operation makes sure all timestamps are consistent.
/// It only performs this on `maxNumberOfChanges` distinct infos, in order to make sure that saving the Core Data context is fast enough. This operation will be relaunched by the coordinator in case more infos remain.
final class ConsolidateLegacyTimestampsOfPersistedMessageSentRecipientInfosOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {

    private(set) var didSaveSomeChanges = false

    private let maxNumberOfChanges: Int
    
    init(maxNumberOfChanges: Int) {
        self.maxNumberOfChanges = maxNumberOfChanges
        super.init()
    }

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            try PersistedMessageSentRecipientInfos.consolidateLegacyTimestamps(within: obvContext.context, maxNumberOfChanges: maxNumberOfChanges)
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
        didSaveSomeChanges = obvContext.context.hasChanges
        
    }
    
}
