/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import CoreData


/// Operation executed during bootstrap. It deletes all received messages that are older than 15 days and that have no associated protocol instance.
final class DeleteObsoleteReceivedMessagesOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    let delegateManager: ObvProtocolDelegateManager
    
    init(delegateManager: ObvProtocolDelegateManager) {
        self.delegateManager = delegateManager
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            // Find all old messages
            
            let fifteenDays = TimeInterval(days: 15)
            let oldDate = Date(timeIntervalSinceNow: -fifteenDays)
            assert(oldDate < Date())
            
            let oldMessages = try ReceivedMessage.getAllReceivedMessageOlderThan(timestamp: oldDate, delegateManager: delegateManager, within: obvContext)
            
            guard !oldMessages.isEmpty else { return }
            
            // For each old message, delete the message if it has no associated protocol instance
            
            for oldMessage in oldMessages {
                let protocolInstanceExistForMessage = try ProtocolInstance.exists(cryptoProtocolId: oldMessage.cryptoProtocolId,
                                                                                  uid: oldMessage.protocolInstanceUid,
                                                                                  ownedIdentity: oldMessage.messageId.ownedCryptoIdentity,
                                                                                  within: obvContext)
                if !protocolInstanceExistForMessage {
                    try oldMessage.deleteReceivedMessage()
                }
                
            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
        
    }
}
