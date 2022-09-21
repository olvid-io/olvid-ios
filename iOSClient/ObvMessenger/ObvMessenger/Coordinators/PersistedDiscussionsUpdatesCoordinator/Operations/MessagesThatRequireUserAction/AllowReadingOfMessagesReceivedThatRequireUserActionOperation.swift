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

/// This operation allows reading of an ephemeral received message that requires user action (e.g. tap) before displaying its content, but only if appropriate.
///
/// This operation shall only be called when the user **explicitely** requested to open a message (in particular, it shall **not** be called for implementing
/// the auto-read feature).
///
/// This operation does nothing if the discussion is not the one corresponding to the user current activity, or if the app is not initialized and active.
///
final class AllowReadingOfMessagesReceivedThatRequireUserActionOperation: OperationWithSpecificReasonForCancel<AllowReadingOfReadOnceMessageOperationReasonForCancel> {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: AllowReadingOfMessagesReceivedThatRequireUserActionOperation.self))

    let persistedMessageReceivedObjectIDs: Set<TypeSafeManagedObjectID<PersistedMessageReceived>>
    
    init(persistedMessageReceivedObjectIDs: Set<TypeSafeManagedObjectID<PersistedMessageReceived>>) {
        self.persistedMessageReceivedObjectIDs = persistedMessageReceivedObjectIDs
        super.init()
    }

    override func main() {

        var discussionObjectIDsToRefresh = Set<NSManagedObjectID>()
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            
            /* The following line was added to solve a recurring merge conflict between the context created here
             * and the one one created in ProcessPersistedMessageAsItTurnsNotNewOperation. I do not understand why
             * this is required at all since these two operations cannot be executed at the same time. Still,
             * if we do not specify this merge policy, it is easy to reproduce a merge conflict: configure a discussion
             * with only readOnly messages and auto reading, and let the contact send several messages in a row.
             */
            context.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump
            
            for messageID in persistedMessageReceivedObjectIDs {
                
                let messageReceived: PersistedMessageReceived
                do {
                    guard let _message = try PersistedMessageReceived.get(with: messageID, within: context) else {
                        return
                    }
                    messageReceived = _message
                } catch {
                    assertionFailure()
                    os_log("Could not get received message: %{public}@", log: log, type: .fault, error.localizedDescription)
                    // Continue anyway
                    return
                }
                
                guard ObvUserActivitySingleton.shared.currentPersistedDiscussionObjectID == messageReceived.discussion.typedObjectID else {
                    assertionFailure("How is it possible that the user requested to read a (say) read once message if she is not currently within the corresponding discussion?")
                    continue
                }

                do {
                    try messageReceived.allowReading(now: Date())
                } catch {
                    return cancel(withReason: .couldNotAllowReading)
                }

                discussionObjectIDsToRefresh.insert(messageReceived.discussion.objectID)

            }
            
            do {
                try context.save(logOnFailure: log)
            } catch {
                cancel(withReason: .coreDataError(error: error))
                return
            }
                     
        }
       
        // The following allows to make sure we properly refresh the discussion in the view context
        // For now, it is not required since the viewContext is automatically refreshed. But, some day, we won't rely on automatic refresh.
        let messageObjectIDs = persistedMessageReceivedObjectIDs
        ObvStack.shared.viewContext.perform {
            
            for messageID in messageObjectIDs {
                if let message = try? PersistedMessageReceived.get(with: messageID, within: ObvStack.shared.viewContext) {
                    ObvStack.shared.viewContext.refresh(message, mergeChanges: false)
                } else {
                    assertionFailure()
                }
            }
            
            // We also look for messages containing a reply-to to the messages that have been interacted with
            let registeredMessages = ObvStack.shared.viewContext.registeredObjects.compactMap({ $0 as? PersistedMessage })
            registeredMessages.forEach { replyTo in
                switch replyTo.genericRepliesTo {
                case .available(message: let message):
                    if let receivedMessage = message as? PersistedMessageReceived, messageObjectIDs.contains(receivedMessage.typedObjectID) {
                        ObvStack.shared.viewContext.refresh(replyTo, mergeChanges: false)
                    }
                case .deleted, .notAvailableYet, .none:
                    return
                }
            }
            
            for discussionID in discussionObjectIDsToRefresh {
                if let discussion = try? PersistedDiscussion.get(objectID: discussionID, within: ObvStack.shared.viewContext) {
                    ObvStack.shared.viewContext.refresh(discussion, mergeChanges: false)
                } else {
                    assertionFailure()
                }
            }
        }
    }
    
}


enum AllowReadingOfReadOnceMessageOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case messageDoesNotExist
    case coreDataError(error: Error)
    case couldNotAllowReading
    
    var logType: OSLogType {
        switch self {
        case .coreDataError,
             .couldNotAllowReading:
            return .fault
        case .messageDoesNotExist:
            return .info
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .messageDoesNotExist:
            return "We could not find the persisted message in database"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotAllowReading:
            return "Could not allow reading"
        }
    }
    
}
