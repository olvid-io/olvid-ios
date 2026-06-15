/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvUICoreData
import OlvidUtils


/// Discards the `PersistedLocationContinuousReceived` when it expires. Also discard expired `PersistedLocationContinuousSent` received from other owned devices.
///
/// This operation looks among all the `PersistedLocationContinuousReceived` and discards those that are expired.
final class DiscardExpiredPersistedLocationContinuousReceivedOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        do {
            try PersistedLocationContinuousReceived.discardExpiredPersistedLocationContinuousReceived(within: obvContext.context)
            try PersistedLocationContinuousSent.discardExpiredPersistedLocationContinuousSentFromOtherOwnedDevices(within: obvContext.context)
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }

    }
    
}
