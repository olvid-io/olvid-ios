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
import ObvEngine
import ObvTypes
import OlvidUtils
import ObvCrypto


/// This method is typically called when we receive a request to delete some messages by a contact willing to globally delete these messages
final class WipeMessagesOperation: ContextualOperationWithSpecificReasonForCancel<WipeMessagesOperationReasonForCancel> {
    
    private let groupIdentifier: GroupIdentifier?
    private let messagesToDelete: [MessageReferenceJSON]
    private let requester: ObvContactIdentity
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: WipeMessagesOperation.self))
    private let saveRequestIfMessageCannotBeFound: Bool
    private let messageUploadTimestampFromServer: Date
    
    init(messagesToDelete: [MessageReferenceJSON], groupIdentifier: GroupIdentifier?, requester: ObvContactIdentity, messageUploadTimestampFromServer: Date, saveRequestIfMessageCannotBeFound: Bool) {
        self.messagesToDelete = messagesToDelete
        self.groupIdentifier = groupIdentifier
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
                    guard let _contact = try PersistedObvContactIdentity.get(persisted: requester, whereOneToOneStatusIs: .any, within: obvContext.context) else {
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
            do {
                if let groupIdentifier = self.groupIdentifier {
                    switch groupIdentifier {
                    case .groupV1(let groupV1Identifier):
                        guard let group = try PersistedContactGroup.getContactGroup(groupId: groupV1Identifier, ownedIdentity: ownedIdentity) else {
                            return cancel(withReason: .couldNotFindGroupDiscussion)
                        }
                        guard group.contactIdentities.contains(contact) || group.ownerIdentity == requester.cryptoId.getIdentity() else {
                            return cancel(withReason: .wipeRequestedByNonGroupMember)
                        }
                        discussion = group.discussion
                    case .groupV2(let groupV2Identifier):
                        guard let group = try PersistedGroupV2.get(ownIdentity: ownedIdentity, appGroupIdentifier: groupV2Identifier) else {
                            return cancel(withReason: .couldNotFindGroupDiscussion)
                        }
                        guard let requester = group.otherMembers.first(where: { $0.identity == requester.cryptoId.getIdentity() }) else {
                            return cancel(withReason: .wipeRequestedByNonGroupMember)
                        }
                        guard requester.isAllowedToRemoteDeleteAnything || requester.isAllowedToEditOrRemoteDeleteOwnMessages else {
                            assertionFailure()
                            return cancel(withReason: .wipeRequestedByMemberNotAllowedToRemoteDelete)
                        }
                        guard let _discussion = group.discussion else {
                            return cancel(withReason: .couldNotFindGroupDiscussion)
                        }
                        discussion = _discussion
                    }
                } else if let oneToOneDiscussion = contact.oneToOneDiscussion {
                    discussion = oneToOneDiscussion
                } else {
                    return cancel(withReason: .couldNotFindDiscussion)
                }
            } catch {
                assertionFailure()
                return cancel(withReason: .coreDataError(error: error))
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

            var objectIDOfWipedMessages = Set<TypeSafeManagedObjectID<PersistedMessage>>()
            
            for message in sentMessagesToWipe {
                messageUriRepresentations.insert(message.typedObjectID.downcast.uriRepresentation())
                let requesterOfDeletion = RequesterOfMessageDeletion.contact(ownedCryptoId: ownedIdentity.cryptoId,
                                                                             contactCryptoId: contact.cryptoId,
                                                                             messageUploadTimestampFromServer: messageUploadTimestampFromServer)
                try? message.wipe(requester: requesterOfDeletion)
                objectIDOfWipedMessages.insert(message.typedObjectID.downcast)
            }
            
            for message in receivedMessagesToWipe {
                messageUriRepresentations.insert(message.typedObjectID.downcast.uriRepresentation())
                try? message.wipeByContact(ownedCryptoId: ownedIdentity.cryptoId,
                                           contactCryptoId: contact.cryptoId,
                                           messageUploadTimestampFromServer: messageUploadTimestampFromServer)
                objectIDOfWipedMessages.insert(message.typedObjectID.downcast)
            }
            
            do {
                try obvContext.addContextDidSaveCompletionHandler { error in
                    guard error == nil else { return }
                    ObvMessengerCoreDataNotification.persistedMessagesWereWiped(discussionUriRepresentation: discussionUriRepresentation, messageUriRepresentations: messageUriRepresentations)
                        .postOnDispatchQueue()
                    // The view context should refresh the wiped messages and the messages that are replies to these wiped messages
                    DispatchQueue.main.async {
                        let registeredMessages = ObvStack.shared.viewContext.registeredObjects.compactMap({ $0 as? PersistedMessage })
                        for message in registeredMessages {
                            if objectIDOfWipedMessages.contains(message.typedObjectID) {
                                ObvStack.shared.viewContext.refresh(message, mergeChanges: false)
                            } else if let reply = message.rawMessageRepliedTo, objectIDOfWipedMessages.contains(reply.typedObjectID) {
                                ObvStack.shared.viewContext.refresh(message, mergeChanges: false)
                            }
                        }
                    }
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
    case wipeRequestedByMemberNotAllowedToRemoteDelete
    case couldNotFindDiscussion

    var logType: OSLogType {
        switch self {
        case .wipeRequestedByMemberNotAllowedToRemoteDelete:
            return .error
        case .coreDataError, .couldNotFindOwnedIdentity, .couldNotFindGroupDiscussion, .couldNotFindContact, .wipeRequestedByNonGroupMember, .contextIsNil, .couldNotFindDiscussion:
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
        case .couldNotFindDiscussion:
            return "Could not find discussion"
        case .wipeRequestedByMemberNotAllowedToRemoteDelete:
            return "The message wipe was requested by a member who is not allowed to perform remote delete"
        }
    }

}
