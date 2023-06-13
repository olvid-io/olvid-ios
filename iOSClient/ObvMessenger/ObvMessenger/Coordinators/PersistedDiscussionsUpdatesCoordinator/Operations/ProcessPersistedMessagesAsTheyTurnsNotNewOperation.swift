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

/// When a discussion displays a new message, we consider it to be "not new" anymore. In the case of a `PersistedMessageReceived` instance, we mark the message as `unread` if it it marked as `readOnce`, and we mark it as `read` otherwise.
final class ProcessPersistedMessagesAsTheyTurnsNotNewOperation: ContextualOperationWithSpecificReasonForCancel<ProcessPersistedMessagesAsTheyTurnsNotNewOperationReasonForCancel> {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: ProcessPersistedMessagesAsTheyTurnsNotNewOperation.self))
    private let persistedMessageObjectIDs: Set<TypeSafeManagedObjectID<PersistedMessage>>
    
    init(persistedMessageObjectIDs: Set<TypeSafeManagedObjectID<PersistedMessage>>) {
        self.persistedMessageObjectIDs = persistedMessageObjectIDs
        super.init()
    }

    override func main() {

        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        var discussionObjectIDs = Set<TypeSafeManagedObjectID<PersistedDiscussion>>()
        let now = Date()

        obvContext.performAndWait {
            
            for persistedMessageObjectID in self.persistedMessageObjectIDs {
                
                let message: PersistedMessage
                do {
                    guard let _message = try PersistedMessage.get(with: persistedMessageObjectID, within: obvContext.context) else {
                        continue
                    }
                    message = _message
                } catch {
                    cancel(withReason: .coreDataError(error: error))
                    return
                }
                
                if let messageReceived = message as? PersistedMessageReceived {
                    do {
                        try messageReceived.markAsNotNew(now: now)
                    } catch {
                        assertionFailure()
                        continue
                    }
                } else if let systemMessage = message as? PersistedMessageSystem {
                    systemMessage.status = .read
                } else {
                    assertionFailure("Unhandled message type")
                    continue
                }
                       
                discussionObjectIDs.insert(message.discussion.typedObjectID)
                
            }
            
            do {
                if !discussionObjectIDs.isEmpty, obvContext.context.hasChanges {
                    try obvContext.addContextDidSaveCompletionHandler({ error in
                        guard error == nil else { assertionFailure(error!.localizedDescription); return }
                        // The following allows to make sure we properly refresh the discussion in the view context
                        // In particular, this will trigger a proper computation of the new message badges
                        for objectID in discussionObjectIDs {
                            ObvStack.shared.viewContext.performAndWait {
                                guard let discussion = try? PersistedDiscussion.get(objectID: objectID, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
                                ObvStack.shared.viewContext.refresh(discussion, mergeChanges: false)
                            }
                        }
                    })
                }
            } catch {
                os_log("Could not add completion handler to ObvContext: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure(error.localizedDescription)
                return cancel(withReason: .coreDataError(error: error))
            }

        }
        
    }
    
}


enum ProcessPersistedMessagesAsTheyTurnsNotNewOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case contextIsNil
    case coreDataError(error: Error)
    case couldNotMarkMessageReceivedAsNotNew
    
    var logType: OSLogType {
        switch self {
        case .coreDataError, .couldNotMarkMessageReceivedAsNotNew, .contextIsNil:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .contextIsNil:
            return "Context is nil"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotMarkMessageReceivedAsNotNew:
            return "Could not mark message received as not new"
        }
    }
    
}
