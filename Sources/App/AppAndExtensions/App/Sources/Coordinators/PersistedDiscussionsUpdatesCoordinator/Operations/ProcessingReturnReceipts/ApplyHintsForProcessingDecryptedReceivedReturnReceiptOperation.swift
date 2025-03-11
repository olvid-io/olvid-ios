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
import ObvTypes
import ObvEngine
import OlvidUtils
import ObvUICoreData
import ObvAppCoreConstants


/// When handling an encrypted return receipt, we first decrypt it and then execute an operation aiming at identifying necessary database modifications for accurate processing of the receipt,
/// and that returns an instance of `HintsForProcessingDecryptedRecievedReturnReceipt`. This operation uses this hint to effectively manage the received return receipt and
/// update the database. Since this operation updates the database, it must run on the coordinators's queue.
final class ApplyHintsForProcessingDecryptedReceivedReturnReceiptOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
 
    private let hints: HintsForProcessingDecryptedReceivedReturnReceipt
    
    init(hints: HintsForProcessingDecryptedReceivedReturnReceipt) {
        self.hints = hints
        super.init()
    }

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            try PersistedMessageSentRecipientInfos.applyHintsForProcessingDecryptedReceivedReturnReceipt(hints: hints, within: obvContext.context)
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
