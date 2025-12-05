/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import OSLog
import CoreData
import OlvidUtils
import ObvServerInterface
import ObvCrypto


final class SaveReturnedServerValuesForBatchUploadedMessagesOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    let valuesToSave: [(uploadedMessage: ObvServerBatchUploadMessages.MessageToUpload, serverReturnedValues: (uidFromServer: UID, nonce: Data, timestampFromServer: Date))]
    
    init(valuesToSave: [(uploadedMessage: ObvServerBatchUploadMessages.MessageToUpload, serverReturnedValues: (uidFromServer: UID, nonce: Data, timestampFromServer: Date))]) {
        self.valuesToSave = valuesToSave
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        for (uploadedMessage, serverReturnedValues) in valuesToSave {
         
            do {
                
                let outboxMessage = try OutboxMessage.get(messageId: uploadedMessage.messageId, within: obvContext.context)
                guard let outboxMessage else { assertionFailure(); continue }
                
                outboxMessage.setAcknowledged(withMessageUidFromServer: serverReturnedValues.uidFromServer,
                                              nonceFromServer: serverReturnedValues.nonce,
                                              andTimeStampFromServer: serverReturnedValues.timestampFromServer)

                
            } catch {
                assertionFailure()
                // In production, continue with the next message
            }
            
            
        }
        
    }
    
}
