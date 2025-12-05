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
import CoreData
import OSLog
import OlvidUtils
import ObvUICoreData
import ObvTypes
import ObvAppCoreConstants
import ObvAppTypes

///
/// This operation allows reading of an ephemeral received message that requires user action (e.g. tap) before displaying its content, but only if appropriate.
///
/// This operation shall only be called when the user **explicitely** requested to open a message (in particular, it shall **not** be called for implementing
/// the auto-read feature).
///
final class AllowReadingOfMessagesReceivedThatRequireUserActionOperation: ContextualOperationWithSpecificReasonForCancel<AllowReadingOfMessagesReceivedThatRequireUserActionOperation.ReasonForCancel>, @unchecked Sendable, OperationProvidingLimitedVisibilityMessageOpenedJSONs {
        
    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: AllowReadingOfMessagesReceivedThatRequireUserActionOperation.self))

    enum Input {
        case requestedOnCurrentDevice(ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageId: ReceivedMessageIdentifier)
        case requestedOnAnotherOwnedDevice(ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageId: ReceivedMessageIdentifier, messageUploadTimestampFromServer: Date, obvDiscussionIdentifier: ObvDiscussionIdentifier)
    }
    
    let input: Input

    init(_ input: Input) {
        self.input = input
        super.init()
    }
    
    var ownedCryptoId: ObvCryptoId? {
        switch input {
        case .requestedOnAnotherOwnedDevice(ownedCryptoId: let ownedCryptoId, discussionId: _, messageId: _, messageUploadTimestampFromServer: _, obvDiscussionIdentifier: _):
            return ownedCryptoId
        case .requestedOnCurrentDevice(ownedCryptoId: let ownedCryptoId, discussionId: _, messageId: _):
            return ownedCryptoId
        }
    }
    
    private(set) var limitedVisibilityMessageOpenedJSONsToSend = [ObvUICoreData.LimitedVisibilityMessageOpenedJSON]()

    
    enum Result {
        case processed
        case couldNotFindActiveDiscussionInDatabase(discussionIdentifier: ObvDiscussionIdentifier)
        case couldNotFindMessageInDatabase(messageIdentifier: ObvMessageAppIdentifier)
        case contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: ObvGroupIdentifier, contactCryptoId: ObvCryptoId)
    }

    private(set) var result: Result?

    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {

        let ownedCryptoId: ObvCryptoId
        let discussionId: DiscussionIdentifier
        let messageId: ReceivedMessageIdentifier
        let dateWhenMessageWasRead: Date
        let shouldSendLimitedVisibilityMessageOpenedJSON: Bool
        let requestedOnAnotherOwnedDevice: Bool
        let discussionIdentifier: ObvDiscussionIdentifier? // Set iff the request comes from another owned device
        let obvMessageIdentifier: ObvMessageAppIdentifier? // Set iff the request comes from another owned device
        switch input {
        case .requestedOnCurrentDevice(let _ownedCryptoId, let _discussionId, let _messageId):
            ownedCryptoId = _ownedCryptoId
            discussionId = _discussionId
            messageId = _messageId
            dateWhenMessageWasRead = Date()
            shouldSendLimitedVisibilityMessageOpenedJSON = true
            requestedOnAnotherOwnedDevice = false
            discussionIdentifier = nil
            obvMessageIdentifier = nil
        case .requestedOnAnotherOwnedDevice(let _ownedCryptoId, let _discussionId, let _messageId, let messageUploadTimestampFromServer, obvDiscussionIdentifier: let _obvDiscussionIdentifier):
            ownedCryptoId = _ownedCryptoId
            discussionId = _discussionId
            messageId = _messageId
            dateWhenMessageWasRead = messageUploadTimestampFromServer
            shouldSendLimitedVisibilityMessageOpenedJSON = false
            requestedOnAnotherOwnedDevice = true
            discussionIdentifier = _obvDiscussionIdentifier
            switch messageId {
            case .objectID:
                assertionFailure()
                return cancel(withReason: .unexpectedMessageId)
            case .authorIdentifier(let writerIdentifier):
                obvMessageIdentifier = ObvMessageAppIdentifier.received(
                    discussionIdentifier: _obvDiscussionIdentifier,
                    senderIdentifier: writerIdentifier.senderIdentifier,
                    senderThreadIdentifier: writerIdentifier.senderThreadIdentifier,
                    senderSequenceNumber: writerIdentifier.senderSequenceNumber)
            }
        }

        do {
                        
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
                if let error = error as? ObvUICoreDataError {
                    switch error {
                    case .couldNotFindPersistedMessage, .couldNotFindPersistedMessageSent, .couldNotFindPersistedMessageReceived:
                        // This is ok as this happens when the message was deleted
                        break
                    default:
                        assertionFailure(error.localizedDescription)
                    }
                } else {
                    assertionFailure(error.localizedDescription)
                }
            }
            
            result = .processed
            
        } catch {
            // Note that discussionIdentifier is no-nil iff the request comes from another owned device,
            // which is the only case when we might want to keep the request for later in case of error.
            if let error = error as? ObvUICoreDataError, let discussionIdentifier {
                switch error {
                    
                case .couldNotFindPersistedMessage, .couldNotFindPersistedMessageReceived:
                    
                    // This only occurs when the message comes from another owned device. In that case `obvMessageIdentifier`
                    // is not nil.
                    if let obvMessageIdentifier {
                        return result = .couldNotFindMessageInDatabase(messageIdentifier: obvMessageIdentifier)
                    } else {
                        assertionFailure()
                        return
                    }
                    
                case .couldNotFindDiscussion,
                        .cannotChangeShareConfigurationOfLockedDiscussion,
                        .cannotChangeShareConfigurationOfPreDiscussion:
                    return result = .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)

                case .couldNotFindGroupV1InDatabase:
                    // If a group does not exist, any associated discussion also cannot exist.
                    // Therefore, return a `couldNotFindActiveDiscussionInDatabase` result.
                    // The message will remain on hold until the discussion is created,
                    // which occurs automatically upon group creation.
                    return result = .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)

                case .couldNotFindGroupV2InDatabase(groupIdentifier: let groupIdentifier):
                    // If a group does not exist, any associated discussion also cannot exist.
                    // Therefore, return a `couldNotFindActiveDiscussionInDatabase` result.
                    // The message will remain on hold until the discussion is created,
                    // which occurs automatically upon group creation.
                    assert(discussionIdentifier == ObvDiscussionIdentifier.groupV2(id: groupIdentifier))
                    return result = .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)

                case .couldNotFindContactWithId(contactIdentifier: let contactIdentifier):
                    // This can happen if the owned identity performed a mutual scan with the contact from another owned device.
                    // In the case the received information concerns:
                    // - a one2one discussion:
                    // If a contact does not exist, any associated discussion also cannot exist.
                    // Therefore, return a `couldNotFindActiveDiscussionInDatabase` result.
                    // The message will remain on hold until the discussion is created,
                    // which occurs automatically upon contact creation.
                    // - a group discussion:
                    // To the contrary of the previous case, the discussion with the contact might never be
                    // created (e.g., when the contact is added to the group by another administrator). So we
                    // return a `contactIsNotPartOfGroupOrRequiresPermissions` result.
                    if let obvGroupIdentifier = discussionIdentifier.obvGroupIdentifier {
                        // Group discussion
                        return result = .contactIsNotPartOfGroupOrRequiresPermissions(
                            groupIdentifier: obvGroupIdentifier,
                            contactCryptoId: contactIdentifier.contactCryptoId)
                    } else {
                        // One2one discussion
                        return result = .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)
                    }

                case .couldNotFindOneToOneContactWithId(contactIdentifier: let contactIdentifier):
                    // This can happen when receiving a shared config from a contact who just accepted
                    // our invitation to be a oneToOne contact. We should not fail as this case is handled:
                    // we will soon turn her into a oneToOne contact, and thus,
                    // send her back our own shared config for the discussion.
                    // Upon receiving our discussion shared settings, she will
                    // again send us back her shared settings if required.
                    //
                    // If a contact is not one-to-one, any associated discussion is locked, or cannot exist.
                    // Therefore, return a `couldNotFindDiscussionInDatabase` result.
                    // The message will remain on hold until the discussion is created, or if the existing discussion
                    // status is set to active again.
                    let discussionIdentifier = ObvDiscussionIdentifier.oneToOne(id: contactIdentifier)
                    return result = .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)

                case .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
                    assert(groupIdentifier == discussionIdentifier.obvGroupIdentifier)
                    return result = .contactIsNotPartOfGroupOrRequiresPermissions(
                        groupIdentifier: groupIdentifier,
                        contactCryptoId: contactCryptoId)

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
        case unexpectedMessageId
        
        var logType: OSLogType {
            switch self {
            case .coreDataError,
                    .couldNotAllowReading,
                    .couldNotFindOwnedIdentity,
                    .unexpectedMessageId:
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
            case .unexpectedMessageId:
                return "Unexpected message ID"
            }
        }
        
    }

}
