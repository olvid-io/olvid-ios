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

///
/// This operation allows reading of an ephemeral received message that requires user action (e.g. tap) before displaying its content, but only if appropriate.
///
/// This operation shall only be called when the user **explicitely** requested to open a message (in particular, it shall **not** be called for implementing
/// the auto-read feature).
///
final class AllowReadingOfMessagesReceivedThatRequireUserActionOperation: ContextualOperationWithSpecificReasonForCancel<AllowReadingOfMessagesReceivedThatRequireUserActionOperation.ReasonForCancel>, OperationProvidingLimitedVisibilityMessageOpenedJSONs {
        
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: AllowReadingOfMessagesReceivedThatRequireUserActionOperation.self))

    enum Input {
        case requestedOnCurrentDevice(ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageId: ReceivedMessageIdentifier)
        case requestedOnAnotherOwnedDevice(ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageId: ReceivedMessageIdentifier, messageUploadTimestampFromServer: Date)
    }
    
    let input: Input

    init(_ input: Input) {
        self.input = input
        super.init()
    }
    
    var ownedCryptoId: ObvCryptoId? {
        switch input {
        case .requestedOnAnotherOwnedDevice(ownedCryptoId: let ownedCryptoId, discussionId: _, messageId: _, messageUploadTimestampFromServer: _):
            return ownedCryptoId
        case .requestedOnCurrentDevice(ownedCryptoId: let ownedCryptoId, discussionId: _, messageId: _):
            return ownedCryptoId
        }
    }
    
    private(set) var limitedVisibilityMessageOpenedJSONsToSend = [ObvUICoreData.LimitedVisibilityMessageOpenedJSON]()

    
    enum Result {
        case couldNotFindGroupV2InDatabase(groupIdentifier: GroupV2Identifier)
        case processed
    }

    private(set) var result: Result?

    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {

        do {
            
            let ownedCryptoId: ObvCryptoId
            let discussionId: DiscussionIdentifier
            let messageId: ReceivedMessageIdentifier
            let dateWhenMessageWasRead: Date
            let shouldSendLimitedVisibilityMessageOpenedJSON: Bool
            let requestedOnAnotherOwnedDevice: Bool
            switch input {
            case .requestedOnCurrentDevice(let _ownedCryptoId, let _discussionId, let _messageId):
                ownedCryptoId = _ownedCryptoId
                discussionId = _discussionId
                messageId = _messageId
                dateWhenMessageWasRead = Date()
                shouldSendLimitedVisibilityMessageOpenedJSON = true
                requestedOnAnotherOwnedDevice = false
            case .requestedOnAnotherOwnedDevice(let _ownedCryptoId, let _discussionId, let _messageId, let messageUploadTimestampFromServer):
                ownedCryptoId = _ownedCryptoId
                discussionId = _discussionId
                messageId = _messageId
                dateWhenMessageWasRead = messageUploadTimestampFromServer
                shouldSendLimitedVisibilityMessageOpenedJSON = false
                requestedOnAnotherOwnedDevice = true
            }
            
            guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindOwnedIdentity)
            }
            
            let infos = try ownedIdentity.userWantsToReadReceivedMessageWithLimitedVisibility(discussionId: discussionId, messageId: messageId, dateWhenMessageWasRead: dateWhenMessageWasRead, requestedOnAnotherOwnedDevice: requestedOnAnotherOwnedDevice)
            
            // If we indeed deleted at least one message, we must refresh the view context and notify (to, e.g., delete hard links)

            if let infos {
                try? obvContext.addContextDidSaveCompletionHandler { error in
                    guard error == nil else { return }
                    // We deleted some persisted messages. We notify about that.
                    InfoAboutWipedOrDeletedPersistedMessage.notifyThatMessagesWereWipedOrDeleted([infos])
                    // Refresh objects in the view context
                    InfoAboutWipedOrDeletedPersistedMessage.refresh(viewContext: viewContext, [infos])
                }
            }
            
            // If the user decide to read the message on this device, we must notify other devices.
            // To make this possible, we compute a LimitedVisibilityMessageOpenedJSON that will be processed by another operation.
            
            if shouldSendLimitedVisibilityMessageOpenedJSON {
                do {
                    let limitedVisibilityMessageOpenedJSONToSend = try ownedIdentity.getLimitedVisibilityMessageOpenedJSON(discussionId: discussionId, messageId: messageId)
                    limitedVisibilityMessageOpenedJSONsToSend = [limitedVisibilityMessageOpenedJSONToSend]
                } catch {
                    assertionFailure(error.localizedDescription)
                }
            }
            
            // The following allows to make sure we properly refresh the discussion's messages in the view context.
            // Although this is not required for the read message (thanks the view context's auto refresh feature), this is required to refresh messages that replied to it.
            
            do {
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
            } catch {
                if (error as? ObvUICoreData.PersistedDiscussion.ObvError) == .couldNotFindMessage {
                    // This is ok as this happens when the message was 
                } else {
                    assertionFailure(error.localizedDescription)
                }
            }
            
            result = .processed
            
        } catch {
            if let error = error as? ObvUICoreDataError {
                switch error {
                case .couldNotFindGroupV2InDatabase(groupIdentifier: let groupIdentifier):
                    result = .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
                    return
                case .couldNotFindDiscussionWithId(discussionId: let discussionId):
                    switch discussionId {
                    case .groupV2(let id):
                        switch id {
                        case .groupV2Identifier(let groupIdentifier):
                            result = .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
                            return
                        case .objectID:
                            assertionFailure()
                            return cancel(withReason: .coreDataError(error: error))
                        }
                    case .oneToOne, .groupV1:
                        assertionFailure()
                        return cancel(withReason: .coreDataError(error: error))
                    }
                default:
                    assertionFailure()
                    return cancel(withReason: .coreDataError(error: error))
                }
            } else if let error = error as? ObvUICoreData.PersistedDiscussion.ObvError {
                switch error {
                case .couldNotFindMessage:
                    // This can happen for a read once message, if it has already been deleted
                    result = .processed
                    return
                default:
                    assertionFailure()
                    return cancel(withReason: .coreDataError(error: error))
                }
            } else {
                assertionFailure()
                return cancel(withReason: .coreDataError(error: error))
            }
        }
    }

    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case messageDoesNotExist
        case coreDataError(error: Error)
        case couldNotAllowReading
        case couldNotFindOwnedIdentity
        
        var logType: OSLogType {
            switch self {
            case .coreDataError,
                    .couldNotAllowReading,
                    .couldNotFindOwnedIdentity:
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
            case .couldNotFindOwnedIdentity:
                return "Could not find owned identity"
            }
        }
        
    }

}
