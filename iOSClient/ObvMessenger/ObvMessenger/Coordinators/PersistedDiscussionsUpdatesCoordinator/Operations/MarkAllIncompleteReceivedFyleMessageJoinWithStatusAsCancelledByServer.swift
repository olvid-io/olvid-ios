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
import ObvUICoreData


/// This operation is typically executed when requesting the download progresses of incomplete attachments that results being absent from the engine's inbox.
/// In that case, we know we won't receive the missing bytes of any of the message attachments, so we mark all the incomplete `ReceivedFyleMessageJoinWithStatus`
/// of the message as `cancelledByServer`.
final class MarkAllIncompleteReceivedFyleMessageJoinWithStatusAsCancelledByServer: OperationWithSpecificReasonForCancel<MarkAllIncompleteReceivedFyleMessageJoinWithStatusAsCancelledByServerReasonForCancel> {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: MarkAllIncompleteReceivedFyleMessageJoinWithStatusAsCancelledByServer.self))

    private let messageIdentifierFromEngine: Data
    
    init(messageIdentifierFromEngine: Data) {
        self.messageIdentifierFromEngine = messageIdentifierFromEngine
        super.init()
    }
 
    
    override func main() {
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in

            let receivedMessages: [PersistedMessageReceived]
            do {
                receivedMessages = try PersistedMessageReceived.getAll(messageIdentifierFromEngine: messageIdentifierFromEngine, within: context)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
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
                        join.tryToSetStatusTo(.cancelledByServer)
                    case .complete, .cancelledByServer:
                        break
                    }
                }
            }
            
            do {
                try context.save(logOnFailure: log)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
        }
        
    }
    
}


enum MarkAllIncompleteReceivedFyleMessageJoinWithStatusAsCancelledByServerReasonForCancel: LocalizedErrorWithLogType {
    case coreDataError(error: Error)
    
    var logType: OSLogType {
        switch self {
        case .coreDataError:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        }
    }
    
}
