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
import ObvEngine
import ObvTypes
import OlvidUtils


/// This method is typically called when we receive a request to delete some messages by a contact willing to globally delete these messages
final class WipeMessagesOperation: ContextualOperationWithSpecificReasonForCancel<WipeMessagesOperationReasonForCancel> {
    
    private let groupId: (groupUid: UID, groupOwner: ObvCryptoId)?
    private let messagesToDelete: [MessageReferenceJSON]
    private let requester: ObvContactIdentity
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))
    private let saveRequestIfMessageCannotBeFound: Bool
    private let messageUploadTimestampFromServer: Date
    
    init(messagesToDelete: [MessageReferenceJSON], groupId: (groupUid: UID, groupOwner: ObvCryptoId)?, requester: ObvContactIdentity, messageUploadTimestampFromServer: Date, saveRequestIfMessageCannotBeFound: Bool) {
        self.messagesToDelete = messagesToDelete
        self.groupId = groupId
        self.requester = requester
        self.saveRequestIfMessageCannotBeFound = saveRequestIfMessageCannotBeFound
        self.messageUploadTimestampFromServer = messageUploadTimestampFromServer
        super.init()
    }
 
    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

        guard !messagesToDelete.isEmpty else { assertionFailure(); return }

        obvContext.performAndWait {
            
            // Get the contact and the owned identities
            
            let contact: PersistedObvContactIdentity
            do {
                do {
                    guard let _contact = try PersistedObvContactIdentity.get(persisted: requester, within: obvContext.context) else {
                        return cancel(withReason: .couldNotFindContact)
                    }
                    contact = _contact
                } catch {
                    return cancel(withReason: .coreDataError(error: error))
                }
            }
            
            guard let ownedIdentity = contact.ownedIdentity else {
                return cancel(withReason: .couldNotFindOwnedIdentity)
            }
            
            // Recover the appropriate discussion. In case of a group discussion, make sure the contact is part of the group
            
            let discussion: PersistedDiscussion
            if let groupId = self.groupId {
                do {
                    guard let group = try PersistedContactGroup.getContactGroup(groupId: groupId, ownedIdentity: ownedIdentity) else {
                        return cancel(withReason: .couldNotFindGroupDiscussion)
                    }
                    guard group.contactIdentities.contains(contact) || group.ownerIdentity == requester.cryptoId.getIdentity() else {
                        return cancel(withReason: .wipeRequestedByNonGroupMember)
                    }
                    discussion = group.discussion
                } catch {
                    return cancel(withReason: .coreDataError(error: error))
                }
            } else {
                discussion = contact.oneToOneDiscussion
            }
            
            // Get the sent messages to wipe
            
            let sentMessagesToWipe = messagesToDelete
                .filter({ $0.senderIdentifier == ownedIdentity.cryptoId.getIdentity() })
                .compactMap({
                    try? PersistedMessageSent.get(senderSequenceNumber: $0.senderSequenceNumber,
                                                  senderThreadIdentifier: $0.senderThreadIdentifier,
                                                  ownedIdentity: $0.senderIdentifier,
                                                  discussion: discussion)
                })
            
            // Get received messages to wipe. If a message cannot be found, save the request for later if `saveRequestIfMessageCannotBeFound` is true
            
            var receivedMessagesToWipe = [PersistedMessageReceived]()
            do {
                let receivedMessages = messagesToDelete
                    .filter({ $0.senderIdentifier != ownedIdentity.cryptoId.getIdentity() })
                for receivedMessage in receivedMessages {
                    if let persistedMessageReceived = try PersistedMessageReceived.get(senderSequenceNumber: receivedMessage.senderSequenceNumber,
                                                                                       senderThreadIdentifier: receivedMessage.senderThreadIdentifier,
                                                                                       contactIdentity: receivedMessage.senderIdentifier,
                                                                                       discussion: discussion) {
                        receivedMessagesToWipe.append(persistedMessageReceived)
                    } else if saveRequestIfMessageCannotBeFound {
                        _ = try RemoteDeleteAndEditRequest.createDeleteRequest(remoteDeleterIdentity: requester.cryptoId.getIdentity(),
                                                                               messageReference: receivedMessage,
                                                                               serverTimestamp: messageUploadTimestampFromServer,
                                                                               discussion: discussion)
                    }
                }
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
            // Wipe each message and notify on context change
            
            let discussionUriRepresentation = discussion.typedObjectID.uriRepresentation()
            var messageUriRepresentations = Set<TypeSafeURL<PersistedMessage>>()

            for message in sentMessagesToWipe {
                messageUriRepresentations.insert(message.typedObjectID.downcast.uriRepresentation())
                try? message.wipe(requester: contact)
            }
            
            for message in receivedMessagesToWipe {
                messageUriRepresentations.insert(message.typedObjectID.downcast.uriRepresentation())
                try? message.wipe(requester: contact)
            }
            
            do {
                try obvContext.addContextDidSaveCompletionHandler { error in
                    guard error == nil else { return }
                    ObvMessengerInternalNotification.persistedMessagesWereWiped(discussionUriRepresentation: discussionUriRepresentation, messageUriRepresentations: messageUriRepresentations)
                        .postOnDispatchQueue()
                }
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
                        
        }
        
    }
}


enum WipeMessagesOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case contextIsNil
    case couldNotFindOwnedIdentity
    case couldNotFindGroupDiscussion
    case couldNotFindContact
    case wipeRequestedByNonGroupMember

    var logType: OSLogType {
        switch self {
        case .coreDataError, .couldNotFindOwnedIdentity, .couldNotFindGroupDiscussion, .couldNotFindContact, .wipeRequestedByNonGroupMember, .contextIsNil:
            return .fault
        }
    }

    var errorDescription: String? {
        switch self {
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .contextIsNil:
            return "The context is not set"
        case .couldNotFindOwnedIdentity:
            return "Could not find owned identity"
        case .couldNotFindGroupDiscussion:
            return "Could not find group discussion"
        case .couldNotFindContact:
            return "Could not find the contact identity"
        case .wipeRequestedByNonGroupMember:
            return "The message wipe was requested by a contact that is not part of the group"
        }
    }

}
