/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

/// When a discussion displays a new message, we consider it to be "not new" anymore. In the case of a `PersistedMessageReceived` instance, we mark the message as `unread` if it it marked as `readOnce`, and we mark it as `read` otherwise.
final class ProcessPersistedMessageAsItTurnsNotNewOperation: OperationWithSpecificReasonForCancel<MarkPersistedMessageReceivedAsNotNewOperationReasonForCancel> {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))
    let persistedMessageObjectID: TypeSafeManagedObjectID<PersistedMessage>
    
    init(persistedMessageObjectID: TypeSafeManagedObjectID<PersistedMessage>) {
        self.persistedMessageObjectID = persistedMessageObjectID
        super.init()
    }

    override func main() {

        var discussionObjectID: NSManagedObjectID?
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            
            /// 2020-12-23 Required to prevent a merge conflict when entering a new discussion
            context.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump
            
            let message: PersistedMessage
            do {
                guard let _message = try PersistedMessage.get(with: persistedMessageObjectID, within: context) else {
                    cancel(withReason: .messageDoesNotExist)
                    return
                }
                message = _message
            } catch {
                cancel(withReason: .coreDataError(error: error))
                return
            }
            
            if let messageReceived = message as? PersistedMessageReceived {
                do {
                    try messageReceived.markAsNotNew(now: Date())
                } catch {
                    return cancel(withReason: .couldNotMarkMessageReceivedAsNotNew)
                }
            } else if let systemMessage = message as? PersistedMessageSystem {
                systemMessage.status = .read
            } else {
                cancel(withReason: .unhandledMessageType)
                return
            }
            
            do {
                try context.save(logOnFailure: log)
            } catch {
                cancel(withReason: .coreDataError(error: error))
                return
            }
                        
            discussionObjectID = message.discussion.objectID
            
        }
        
        // The following allows to make sure we properly refresh the discussion in the view context
        // In particular, this will trigger a proper computation of the new message badges
        if let objectID = discussionObjectID {
            ObvStack.shared.viewContext.performAndWait {
                guard let discussion = try? PersistedDiscussion.get(objectID: objectID, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
                ObvStack.shared.viewContext.refresh(discussion, mergeChanges: false)
            }
        }

    }
    
}


enum MarkPersistedMessageReceivedAsNotNewOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case messageDoesNotExist
    case unhandledMessageType
    case coreDataError(error: Error)
    case couldNotMarkMessageReceivedAsNotNew
    
    var logType: OSLogType {
        switch self {
        case .coreDataError, .unhandledMessageType, .couldNotMarkMessageReceivedAsNotNew:
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
        case .unhandledMessageType:
            return "The message type is not handled (yet) by this operation"
        case .couldNotMarkMessageReceivedAsNotNew:
            return "Could not mark message received as not new"
        }
    }
    
}
