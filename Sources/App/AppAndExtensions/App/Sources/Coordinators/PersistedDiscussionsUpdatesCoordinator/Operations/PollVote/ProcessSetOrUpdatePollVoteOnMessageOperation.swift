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
import ObvEngine
import ObvTypes
import OlvidUtils
import ObvCrypto
import ObvUICoreData
import ObvAppTypes

/// Called when receiving a remote request (from a contact or from another owned device) to set or edit the poll vote on a message.
final class ProcessSetOrUpdatePollVoteOnMessageOperation: ContextualOperationWithSpecificReasonForCancel<ProcessSetOrUpdatePollVoteOnMessageOperation.ReasonForCancel>, @unchecked Sendable {
    
    
    enum Requester {
        case contact(contactIdentifier: ObvContactIdentifier)
        case ownedIdentity(ownedCryptoId: ObvCryptoId)
        
        var ownedCryptoId: ObvCryptoId {
            switch self {
            case .contact(let contactIdentifier):
                return contactIdentifier.ownedCryptoId
            case .ownedIdentity(let ownedCryptoId):
                return ownedCryptoId
            }
        }
    }

    private let pollVoteJSON: PollVoteJSON
    private let requester: Requester
    private let messageUploadTimestampFromServer: Date

    init(pollVoteJSON: PollVoteJSON, requester: Requester, messageUploadTimestampFromServer: Date) {
        self.pollVoteJSON = pollVoteJSON
        self.requester = requester
        self.messageUploadTimestampFromServer = messageUploadTimestampFromServer
        super.init()
    }
    

    enum Result {
        case processed
        case couldNotFindActiveDiscussionInDatabase(discussionIdentifier: ObvDiscussionIdentifier)
        case couldNotFindMessageInDatabase(messageIdentifier: ObvMessageAppIdentifier)
        case contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: ObvGroupIdentifier, contactCryptoId: ObvCryptoId)
    }

    private(set) var result: Result?

    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        guard let discussionIdentifier = pollVoteJSON.getDiscussionIdentifier(ownedCryptoId: requester.ownedCryptoId) else {
            assertionFailure()
            return cancel(withReason: .couldNotDetermineDiscussionIdentifier)
        }

        let messageIdentifier = pollVoteJSON.messageReference.getMessageIdentifier(discussionIdentifier: discussionIdentifier)

        do {
            
            let updatedMessage: PersistedMessage?
            
            switch requester {
                
            case .contact(contactIdentifier: let contactIdentifier):
                
                // Get the PersistedObvContactIdentity who requested the edit
                
                guard let contact = try PersistedObvContactIdentity.get(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: obvContext.context) else {
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
                }
                
                updatedMessage = try contact.processSetOrUpdatePollVoteOnMessageRequestFromThisContact(
                    pollVoteJSON: pollVoteJSON,
                    messageUploadTimestampFromServer: messageUploadTimestampFromServer)
                
            case .ownedIdentity(ownedCryptoId: let ownedCryptoId):
                
                // Get the PersistedObvContactIdentity who requested the edit
                
                guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindOwnedIdentity)
                }
                
                updatedMessage = try ownedIdentity.processSetOrUpdatePollVoteOnMessageRequestFromThisOwnedIdentity(pollVoteJSON: pollVoteJSON, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
            }
            
            result = .processed
            
            // If the message is registered in the view context, we refresh it
            
            if let messageObjectID = updatedMessage?.typedObjectID, obvContext.context.hasChanges {
                try? obvContext.addContextDidSaveCompletionHandler { error in
                    guard error == nil else { return }
                    ObvStack.shared.viewContext.perform {
                        guard let message = ObvStack.shared.viewContext.registeredObject(for: messageObjectID.objectID) else { return }
                        ObvStack.shared.viewContext.refresh(message, mergeChanges: false)
                    }
                }
            }
            
        } catch {
            if let error = error as? ObvUICoreDataError {
                switch error {
                    
                case .couldNotFindPersistedMessage, .couldNotFindPersistedMessageReceived, .couldNotFindPersistedMessageSent:
                    return result = .couldNotFindMessageInDatabase(messageIdentifier: messageIdentifier)
                    
                case .couldNotFindDiscussion,
                        .aMessageCannotBeUpdatedInLockedDiscussion,
                        .aMessageCannotBeUpdatedInPrediscussion:
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
        
        case coreDataError(error: Error)
        case couldNotFindOwnedIdentity
        case couldNotDetermineDiscussionIdentifier
        
        var logType: OSLogType {
            switch self {
            case .coreDataError,
                    .couldNotDetermineDiscussionIdentifier,
                    .couldNotFindOwnedIdentity:
                return .error
            }
        }
        
        var errorDescription: String? {
            switch self {
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .couldNotFindOwnedIdentity:
                return "Could not find owned identity"
            case .couldNotDetermineDiscussionIdentifier:
                return "Could not determine discussion identifier"
            }
        }

    }

}

