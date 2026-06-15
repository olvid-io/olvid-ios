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
import OlvidUtils
import ObvUICoreData
import ObvHistoryTransfer
import ObvAppTypes


final class StoreHistoryTransferredMessageOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private let message: ObvAppTypes.ObvHistoryReceivedMessage
    
    init(message: ObvAppTypes.ObvHistoryReceivedMessage) {
        self.message = message
    }
    
    private(set) var sha256ToRequestToSource = [Data : UInt64]()
    private(set) var sha256NotToBeRequestedToSource = Set<Data>()

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        do {
            (sha256ToRequestToSource, sha256NotToBeRequestedToSource) = try PersistedMessage.createDuringHistoryTransfer(message, within: obvContext.context)
        } catch {
            assertionFailure(error.localizedDescription)
            return cancel(withReason: .coreDataError(error: error))
        }
    }
    
}
