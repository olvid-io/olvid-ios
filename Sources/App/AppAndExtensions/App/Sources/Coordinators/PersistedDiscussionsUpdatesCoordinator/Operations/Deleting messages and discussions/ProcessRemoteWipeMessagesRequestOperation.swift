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


/// This method is typically called when we receive a request to delete some messages by a contact or by an owned identity willing to globally delete these messages.
final class ProcessRemoteWipeMessagesRequestOperation: ContextualOperationWithSpecificReasonForCancel<ProcessRemoteWipeMessagesRequestOperation.ReasonForCancel>, @unchecked Sendable {

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
    
    private let deleteMessagesJSON: DeleteMessagesJSON
    private let requester: Requester
    private let messageUploadTimestampFromServer: Date

    init(deleteMessagesJSON: DeleteMessagesJSON, requester: Requester, messageUploadTimestampFromServer: Date) {
        self.deleteMessagesJSON = deleteMessagesJSON
        self.requester = requester
        self.messageUploadTimestampFromServer = messageUploadTimestampFromServer
        super.init()
    }
 
    enum Result {
        case processed
        case couldNotFindActiveDiscussionInDatabase(discussionIdentifier: ObvDiscussionIdentifier)
        case contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: ObvGroupIdentifier, contactCryptoId: ObvCryptoId)
    }

    private(set) var result: Result?

    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        guard !deleteMessagesJSON.messagesToDelete.isEmpty else {
            assertionFailure()
            return result = .processed
        }
        
        guard let discussionIdentifier = deleteMessagesJSON.getDiscussionIdentifier(ownedCryptoId: requester.ownedCryptoId) else {
            return cancel(withReason: .couldNotDetermineDiscussionIdentifier)
        }

        do {
            
            let infosAboutWipedMessages: [InfoAboutWipedOrDeletedPersistedMessage]
            
            switch requester {
                
            case .contact(contactIdentifier: let contactIdentifier):
                
                // Get the PersistedObvContactIdentity who requested the wipe
                
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
                
                // Try to wipe
                
                infosAboutWipedMessages = try contact.processWipeMessageRequestFromThisContact(
                    deleteMessagesJSON: deleteMessagesJSON,
                    messageUploadTimestampFromServer: messageUploadTimestampFromServer)
                
            case .ownedIdentity(ownedCryptoId: let ownedCryptoId):
                
                // Get the PersistedObvContactIdentity who requested the wipe
                
                guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindOwnedIdentity)
                }
                
                infosAboutWipedMessages = try ownedIdentity.processWipeMessageRequestFromOtherOwnedDevice(
                    deleteMessagesJSON: deleteMessagesJSON,
                    messageUploadTimestampFromServer: messageUploadTimestampFromServer)
                
            }
            
            result = .processed
            
            // Refresh objects in the view context
            
            if !infosAboutWipedMessages.isEmpty {
                try? obvContext.addContextDidSaveCompletionHandler { error in
                    guard error == nil else { return }
                    
                    // We deleted some persisted messages. We notify about that.
                    InfoAboutWipedOrDeletedPersistedMessage.notifyThatMessagesWereWipedOrDeleted(infosAboutWipedMessages)
                    
                    // Refresh objects in the view context
                    if let viewContext = self.viewContext {
                        InfoAboutWipedOrDeletedPersistedMessage.refresh(viewContext: viewContext, infosAboutWipedMessages)
                    }
                    
                }
            }
            
        } catch {
            if let error = error as? ObvUICoreDataError {
                switch error {
                    
                case .couldNotFindDiscussion,
                        .aContactCannotWipeMessageFromLockedDiscussion,
                        .aContactCannotWipeMessageFromPrediscussion:
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
                    
                default:
                    return cancel(withReason: .coreDataError(error: error))
                }
            } else {
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
            case .coreDataError, .couldNotFindOwnedIdentity, .couldNotDetermineDiscussionIdentifier:
                return .fault
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
