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
import CoreData
import os.log
import OlvidUtils
import ObvUICoreData
import ObvTypes


/// This operation is typically executed when requesting the download progresses of incomplete attachments that results being absent from the engine's inbox.
/// In that case, we know we won't receive the missing bytes of any of the message attachments, so we mark all the incomplete `ReceivedFyleMessageJoinWithStatus`
/// of the message as `cancelledByServer`.
final class MarkAllIncompleteReceivedFyleMessageJoinWithStatusAsCancelledByServer: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: MarkAllIncompleteReceivedFyleMessageJoinWithStatusAsCancelledByServer.self))

    private let ownedCryptoId: ObvCryptoId
    private let messageIdentifierFromEngine: Data
    
    init(ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data) {
        self.ownedCryptoId = ownedCryptoId
        self.messageIdentifierFromEngine = messageIdentifierFromEngine
        super.init()
    }
 
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        do {
            
            let receivedMessages = try PersistedMessageReceived.getAll(ownedCryptoId: ownedCryptoId, messageIdentifierFromEngine: messageIdentifierFromEngine, within: obvContext.context)
            
            guard !receivedMessages.isEmpty else {
                // No message found, so there is nothing to do
                return
            }
            
            // We do not expect more than one message within the `receivedMessages` array.
            // But we still perform the operation for "all" messages found.
            
            for message in receivedMessages {
                for join in message.fyleMessageJoinWithStatuses {
                    switch join.status {
                    case .downloadable, .downloading:
                        join.tryToSetStatusToCancelledByServer()
                    case .complete, .cancelledByServer:
                        break
                    }
                }
            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }

    }
    
}
