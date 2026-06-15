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
import ObvCrypto
import OlvidUtils
import ObvUICoreData
import ObvTypes
import ObvAppCoreConstants
import ObvAppTypes


final class CreatePersistedMessageReceivedFromReceivedObvMessageOperation: ContextualOperationWithSpecificReasonForCancel<CreatePersistedMessageReceivedFromReceivedObvMessageOperation.ReasonForCancel>, @unchecked Sendable, OperationProvidingDiscussionPermanentID, OperationProvidingMessageReceivedPermanentID {

    private let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "CreatePersistedMessageReceivedFromReceivedObvMessageOperation")

    private let obvMessage: ObvMessage
    private let messageJSON: MessageJSON
    private let returnReceiptJSON: ReturnReceiptJSON?
    private let source: ObvMessageSource

    init(obvMessage: ObvMessage, messageJSON: MessageJSON, source: ObvMessageSource, returnReceiptJSON: ReturnReceiptJSON?) {
        self.obvMessage = obvMessage
        self.messageJSON = messageJSON
        self.returnReceiptJSON = returnReceiptJSON
        self.source = source
        super.init()
    }

    enum Result {
        case messageCreated(discussionPermanentID: DiscussionPermanentID)
        case couldNotFindActiveDiscussionInDatabase(discussionIdentifier: ObvDiscussionIdentifier)
        case contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: ObvGroupIdentifier, contactCryptoId: ObvCryptoId)
        case messageIsPriorToLastRemoteDeletionRequest
        case cannotCreateReceivedMessageThatAlreadyExpired
        case obvMessageReceivedFromUserNotificationIsInsufficientToCreateMessageReceived
    }
    
    private(set) var result: Result?
    
    
    var discussionPermanentID: ObvUICoreData.DiscussionPermanentID? {
        switch result {
        case .messageIsPriorToLastRemoteDeletionRequest,
                .contactIsNotPartOfGroupOrRequiresPermissions,
                .couldNotFindActiveDiscussionInDatabase,
                .cannotCreateReceivedMessageThatAlreadyExpired,
            nil:
            return nil
        case .obvMessageReceivedFromUserNotificationIsInsufficientToCreateMessageReceived:
            return nil
        case .messageCreated(discussionPermanentID: let discussionPermanentID):
            return discussionPermanentID
        }
    }

    
    private(set) var messageReceivedPermanentId: MessageReceivedPermanentID?
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        let debugDescription = obvMessage.messageIdentifierFromEngine.debugDescription
        logger.debug("Executing a CreatePersistedMessageReceivedFromReceivedObvMessageOperation for obvMessage \(debugDescription, privacy: .public)")
        
        guard let discussionIdentifier = messageJSON.getDiscussionIdentifier(ownedCryptoId: obvMessage.fromContactIdentity.ownedCryptoId) else {
            return cancel(withReason: .couldNotDetermineDiscussionIdentifier)
        }
        
        do {
            
            guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: obvMessage.fromContactIdentity.ownedCryptoId, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindOwnedIdentityInDatabase)
            }
            
            // Create or update the PersistedMessageReceived from that contact
            
            do {
                
                let requestResult = try ownedIdentity.createOrOverridePersistedMessageReceived(
                    obvMessage: obvMessage,
                    messageJSON: messageJSON,
                    returnReceiptJSON: returnReceiptJSON,
                    source: source)
                
                self.messageReceivedPermanentId = requestResult.messageReceivedPermanentId
                return self.result = .messageCreated(discussionPermanentID: requestResult.discussionPermanentID)

            } catch {
                
                switch error {
                    
                case let error as ObvUICoreDataError:
                    
                    switch error {
                        
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
                        return result = .contactIsNotPartOfGroupOrRequiresPermissions(
                            groupIdentifier: groupIdentifier,
                            contactCryptoId: contactCryptoId)
                        
                    case .messageHasNoBody:
                        switch source {
                        case .engine:
                            assertionFailure("This is unexpected as no Olvid platform should be sending a message with no body and no attachments")
                            return cancel(withReason: .obvUICoreDataError(error: error))
                        case .userNotification:
                            // This happens when the receiving a notification for a message that contains no body, but only attachments. In that case, the ObvMessage
                            // received from the notification center only knows about the number of expected attachments, but not about the attachments themselves, resulting
                            // in an ObvMessage that is not appropriate for creating a PersistedMessageReceived.
                            return result = .obvMessageReceivedFromUserNotificationIsInsufficientToCreateMessageReceived
                        case .historyTransfer:
                            assertionFailure("Unexpected source")
                            return cancel(withReason: .unexpectedMessageSource)
                        }

                    case .cannotCreateReceivedMessageThatAlreadyExpired:
                        return result = .cannotCreateReceivedMessageThatAlreadyExpired
                        
                    case .messageIsPriorToLastRemoteDeletionRequest:
                        return result = .messageIsPriorToLastRemoteDeletionRequest

                    default:
                        assertionFailure("We should make sure the type thrown doesn't deserve a special treatment, potentially allowing the message to wait like it does for the, e.g., couldNotFindGroupV2InDatabase error")
                        return cancel(withReason: .obvUICoreDataError(error: error))

                    }
                    
                default:
                    
                    assertionFailure("This is unexpected, as the ObvUICoreData module should only throw errors of the ObvUICoreDataError type")
                    return cancel(withReason: .coreDataError(error: error))

                }

            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }

    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case couldNotFindOwnedIdentityInDatabase
        case obvUICoreDataError(error: ObvUICoreDataError)
        case coreDataError(error: Error)
        case couldNotDetermineDiscussionIdentifier
        case unexpectedMessageSource

        var logType: OSLogType {
            switch self {
            case .couldNotFindOwnedIdentityInDatabase:
                return .error
            case .obvUICoreDataError, .coreDataError, .couldNotDetermineDiscussionIdentifier, .unexpectedMessageSource:
                return .fault
            }
        }
        
        var errorDescription: String? {
            switch self {
            case .couldNotFindOwnedIdentityInDatabase:
                return "Could not find owned identity in database"
            case .obvUICoreDataError(error: let error):
                return "ObvUICoreDataError error: \(error.localizedDescription)"
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .couldNotDetermineDiscussionIdentifier:
                return "Could not determine discussion identifier"
            case .unexpectedMessageSource:
                return "Unexpected message source"
            }
        }
        
    }

}
