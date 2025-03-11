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
import OlvidUtils
import ObvUICoreData
import ObvTypes
import ObvAppCoreConstants



/// This operation allows reading of all ephemeral received messages that requires user action (e.g. tap) before displaying its content, within the given discussion, but only if appropriate.
///
/// This operation allows to implement the auto-read feature.
///
/// This operation does nothing if the discussion is not the one corresponding to the user current activity.
///
final class TryToAutoReadDiscussionsReceivedMessagesThatRequireUserActionOperation: ContextualOperationWithSpecificReasonForCancel<TryToAutoReadDiscussionsReceivedMessagesThatRequireUserActionOperation.ReasonForCancel>, @unchecked Sendable, OperationProvidingLimitedVisibilityMessageOpenedJSONs {
        
    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: TryToAutoReadDiscussionsReceivedMessagesThatRequireUserActionOperation.self))

    enum Input {
        case discussionPermanentID(discussionPermanentID: DiscussionPermanentID)
        case operationProvidingDiscussionPermanentID(op: OperationProvidingDiscussionPermanentID)
    }
    
    let input: Input

    init(input: Input) {
        self.input = input
        super.init()
    }

    /// This array stores all the `LimitedVisibilityMessageOpenedJSON` that should be sent after this operation finishes.
    private(set) var limitedVisibilityMessageOpenedJSONsToSend = [ObvUICoreData.LimitedVisibilityMessageOpenedJSON]()
    private(set) var ownedCryptoId: ObvCryptoId?
    private(set) var ownedIdentityHasAnotherReachableDevice = false
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        let discussionPermanentID: DiscussionPermanentID
        switch input {
        case .discussionPermanentID(discussionPermanentID: let _discussionPermanentID):
            discussionPermanentID = _discussionPermanentID
        case .operationProvidingDiscussionPermanentID(op: let op):
            guard let _discussionPermanentID = op.discussionPermanentID else { return }
            discussionPermanentID = _discussionPermanentID
        }
        
        do {
            
            let (ownedCryptoId, discussionId) = try PersistedDiscussion.getIdentifiers(for: discussionPermanentID, within: obvContext.context)
        
            self.ownedCryptoId = ownedCryptoId
            
            guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindOwnedIdentity)
            }

            self.ownedIdentityHasAnotherReachableDevice = ownedIdentity.hasAnotherDeviceWhichIsReachable
            
            guard OlvidUserActivitySingleton.shared.currentDiscussionPermanentID == discussionPermanentID else { return }

            let dateWhenMessageWasRead = Date()
            
            let (infos, identifiersOfReadReceivedMessages) = try ownedIdentity.userWantsToAllowReadingAllReceivedMessagesReceivedThatRequireUserAction(discussionId: discussionId, dateWhenMessageWasRead: dateWhenMessageWasRead)
            
            // If the user decide to read the message on this device, we must notify other devices.
            // To make this possible, we compute a LimitedVisibilityMessageOpenedJSON for each message. They will be processed by another operation.

            for messageId in identifiersOfReadReceivedMessages {
                do {
                    let limitedVisibilityMessageOpenedJSON = try ownedIdentity.getLimitedVisibilityMessageOpenedJSON(discussionId: discussionId, messageId: messageId)
                    limitedVisibilityMessageOpenedJSONsToSend.append(limitedVisibilityMessageOpenedJSON)
                } catch {
                    assertionFailure(error.localizedDescription) // Continue anyway
                }
            }
            
            // If we indeed deleted at least one message, we must refresh the view context and notify (to, e.g., delete hard links)
            
            if !infos.isEmpty {
                try obvContext.addContextDidSaveCompletionHandler { error in
                    guard error == nil else { return }
                    // We deleted some persisted messages. We notify about that.
                    InfoAboutWipedOrDeletedPersistedMessage.notifyThatMessagesWereWipedOrDeleted(infos)
                    // Refresh objects in the view context
                    InfoAboutWipedOrDeletedPersistedMessage.refresh(viewContext: viewContext, infos)
                }
            }

            // The following allows to make sure we properly refresh the discussion's messages in the view context.
            // Although this is not required for the read messages (thanks the view context's auto refresh feature), this is required to refresh messages that replied to it.
            
            if !identifiersOfReadReceivedMessages.isEmpty {
                do {
                    for messageId in identifiersOfReadReceivedMessages {
                        let receivedMessageObjectID = try ownedIdentity.getObjectIDOfReceivedMessage(discussionId: discussionId, messageId: messageId)
                        try obvContext.addContextDidSaveCompletionHandler { error in
                            guard error == nil else { return }
                            viewContext.perform {
                                guard let object = viewContext.registeredObject(for: receivedMessageObjectID) else { return }
                                viewContext.refresh(object, mergeChanges: false)
                                // We also look for messages containing a reply-to to the messages that have been interacted with
                                let registeredMessages = ObvStack.shared.viewContext.registeredObjects.compactMap({ $0 as? PersistedMessage })
                                registeredMessages.forEach { replyTo in
                                    switch replyTo.genericRepliesTo {
                                    case .available(message: let message):
                                        if message.objectID == receivedMessageObjectID {
                                            ObvStack.shared.viewContext.refresh(replyTo, mergeChanges: false)
                                        }
                                    case .deleted, .notAvailableYet, .none:
                                        return
                                    }
                                }
                            }
                        }
                    }
                } catch {
                    assertionFailure(error.localizedDescription)
                }
            }

        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }

    }
    
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case messageDoesNotExist
        case coreDataError(error: Error)
        case discussionDoesNotExist
        case couldNotFindOwnedIdentity
        
        var logType: OSLogType {
            switch self {
            case .coreDataError, .discussionDoesNotExist, .couldNotFindOwnedIdentity:
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
            case .couldNotFindOwnedIdentity:
                return "Could not find owned identity"
            case .discussionDoesNotExist:
                return "Discussion does not exist"
            }
        }
        
    }

}


protocol OperationProvidingDiscussionPermanentID: Operation {
    
    var discussionPermanentID: DiscussionPermanentID? { get }
    
}
