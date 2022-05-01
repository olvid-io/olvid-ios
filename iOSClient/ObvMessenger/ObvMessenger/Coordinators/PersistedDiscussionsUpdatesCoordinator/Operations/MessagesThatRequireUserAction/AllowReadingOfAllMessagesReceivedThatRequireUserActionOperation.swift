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

/// This operation allows reading of all ephemeral received messages that requires user action (e.g. tap) before displaying its content, within the given discussion, but only if appropriate.
///
/// This operation allows to implement the auto-read feature.
///
/// This operation does nothing if the discussion is not the one corresponding to the user current activity, or if the app is not initialized and active.
///
final class AllowReadingOfAllMessagesReceivedThatRequireUserActionOperation: OperationWithSpecificReasonForCancel<AllowReadingOfAllMessagesReceivedThatRequireUserActionOperationReasonForCancel> {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: AllowReadingOfAllMessagesReceivedThatRequireUserActionOperation.self))

    let persistedDiscussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>
    
    init(persistedDiscussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) {
        self.persistedDiscussionObjectID = persistedDiscussionObjectID
        super.init()
    }

    override func main() {

        guard AppStateManager.shared.currentState.isInitializedAndActive else { return }
        guard ObvUserActivitySingleton.shared.currentPersistedDiscussionObjectID == persistedDiscussionObjectID else { assertionFailure(); return }
        
        ObvStack.shared.performBackgroundTaskAndWait { context in

            // If we reach this point, the app is initialized and ative, and the user is in the appropriate discussion.
            // We get all received messages that still require autorization before displaying their content.
            
            let receivedMessagesThatRequireUserActionForReading: [PersistedMessageReceived]
            do {
                receivedMessagesThatRequireUserActionForReading = try PersistedMessageReceived.getAllReceivedMessagesThatRequireUserActionForReading(discussionObjectID: persistedDiscussionObjectID, within: context)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
            /* For each received message that still requires autorization before displaying their content,
             * we check whether the discussion has its auto-read configuration set to true (we expect this to
             * be true for all messages, or false for all messages, since they come from the same discussion).
             * We also check that the ephemerality of the message is at least as permissive as that of the discussion,
             * otherwise, we do not auto-read.
             */
            
            receivedMessagesThatRequireUserActionForReading.forEach { receivedMessageThatRequireUserActionForReading in
                guard receivedMessageThatRequireUserActionForReading.discussion.autoRead == true else { return }
                // Check that the message ephemerality is at least that of the discussion, otherwise, do not auto read
                guard receivedMessageThatRequireUserActionForReading.ephemeralityIsAtLeastAsPermissiveThanDiscussionSharedConfiguration else {
                    return
                }
                do {
                    try receivedMessageThatRequireUserActionForReading.allowReading(now: Date())
                } catch {
                    os_log("Could not auto-read received message although we should: %{public}@", log: log, type: .fault, error.localizedDescription)
                    // Continue anyway
                }
            }
            
            do {
                try context.save(logOnFailure: log)
            } catch {
                cancel(withReason: .coreDataError(error: error))
                return
            }
                     
        }
       
    }
    
}


enum AllowReadingOfAllMessagesReceivedThatRequireUserActionOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case messageDoesNotExist
    case coreDataError(error: Error)
    
    var logType: OSLogType {
        switch self {
        case .coreDataError:
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
        }
    }
    
}
