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



fileprivate enum UpdateReactionsOfMessageOperationInput {
    
    case contact(emoji: String?,
                 messageReference: MessageReferenceJSON,
                 groupId: (groupUid: UID, groupOwner: ObvCryptoId)?,
                 contactIdentity: ObvContactIdentity,
                 addPendingReactionIfMessageCannotBeFound: Bool)
    case owned(emoji: String?,
               message: TypeSafeManagedObjectID<PersistedMessage>)

    var emoji: String? {
        switch self {
        case .contact(let emoji, _, _, _, _),
                .owned(let emoji, _):
            return emoji
        }
    }
}

final class UpdateReactionsOfMessageOperation: ContextualOperationWithSpecificReasonForCancel<UpdateReactionsOperationReasonForCancel> {

    private let input: UpdateReactionsOfMessageOperationInput
    private let reactionTimestamp: Date

    /// Use this initializer when updating the reactions of a message with a reaction made by an owned identity.
    init(emoji: String?, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>) {
        self.input = .owned(emoji: emoji, message: messageObjectID)
        self.reactionTimestamp = Date()
        super.init()
    }

    init(emoji: String?,
         messageReference: MessageReferenceJSON,
         groupId: (groupUid: UID, groupOwner: ObvCryptoId)?,
         contactIdentity: ObvContactIdentity,
         reactionTimestamp: Date,
         addPendingReactionIfMessageCannotBeFound: Bool) {
        self.input = .contact(emoji: emoji,
                              messageReference: messageReference,
                              groupId: groupId,
                              contactIdentity: contactIdentity,
                              addPendingReactionIfMessageCannotBeFound: addPendingReactionIfMessageCannotBeFound)
        self.reactionTimestamp = reactionTimestamp
        super.init()
    }

    init(contactIdentity: ObvContactIdentity, reactionJSON: ReactionJSON, reactionTimestamp: Date, addPendingReactionIfMessageCannotBeFound: Bool) {
        self.input = .contact(emoji: reactionJSON.emoji,
                              messageReference: reactionJSON.messageReference,
                              groupId: reactionJSON.groupId,
                              contactIdentity: contactIdentity,
                              addPendingReactionIfMessageCannotBeFound: addPendingReactionIfMessageCannotBeFound)
        self.reactionTimestamp = reactionTimestamp
        super.init()
    }

    
    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

        obvContext.performAndWait {

            var message: PersistedMessage?

            switch input {

            case .contact(let emoji, let messageReference, let groupId, let contactIdentity, let addPendingReactionIfMessageCannotBeFound):

                // Get the contact and the owned identities

                let persistedContactIdentity: PersistedObvContactIdentity
                do {
                    do {
                        guard let _persistedContactIdentity = try PersistedObvContactIdentity.get(persisted: contactIdentity, within: obvContext.context) else {
                            return cancel(withReason: .couldNotFindContact)
                        }
                        persistedContactIdentity = _persistedContactIdentity
                    } catch {
                        return cancel(withReason: .coreDataError(error: error))
                    }
                }

                guard let ownedIdentity = persistedContactIdentity.ownedIdentity else {
                    return cancel(withReason: .couldNotFindOwnedIdentity)
                }

                // Recover the appropriate discussion

                let discussion: PersistedDiscussion
                if let groupId = groupId {
                    do {
                        guard let group = try PersistedContactGroup.getContactGroup(groupId: groupId, ownedIdentity: ownedIdentity) else {
                            return cancel(withReason: .couldNotFindGroupDiscussion)
                        }
                        discussion = group.discussion
                    } catch {
                        return cancel(withReason: .coreDataError(error: error))
                    }
                } else {
                    discussion = persistedContactIdentity.oneToOneDiscussion
                }

                // Get the message on which we will add a reaction
                
                do {
                    if let sentMessage = try PersistedMessageSent.get(
                        senderSequenceNumber: messageReference.senderSequenceNumber,
                        senderThreadIdentifier: messageReference.senderThreadIdentifier,
                        ownedIdentity: messageReference.senderIdentifier,
                        discussion: discussion) {
                        message = sentMessage
                    } else if let receivedMessage = try PersistedMessageReceived.get(
                        senderSequenceNumber: messageReference.senderSequenceNumber,
                        senderThreadIdentifier: messageReference.senderThreadIdentifier,
                        contactIdentity: messageReference.senderIdentifier,
                        discussion: discussion) {
                        message = receivedMessage
                    }
                } catch {
                    return cancel(withReason: .coreDataError(error: error))
                }
                
                // If a message was found, we can update its reactions. If not, we create a pending reaction  if appropriate.

                if let message = message {
                    do {
                        try message.setReactionFromContact(persistedContactIdentity, withEmoji: emoji, reactionTimestamp: reactionTimestamp)
                    } catch {
                        return cancel(withReason: .coreDataError(error: error))
                    }
                } else if addPendingReactionIfMessageCannotBeFound {
                    do {
                        try PendingMessageReaction.createPendingMessageReactionIfAppropriate(
                            emoji: emoji,
                            messageReference: messageReference,
                            serverTimestamp: reactionTimestamp,
                            discussion: discussion)
                    } catch {
                        return cancel(withReason: .coreDataError(error: error))
                    }
                } else {
                    return cancel(withReason: .couldNotFindMessage)
                }
                
            case .owned(emoji: let emoji, message: let messageObjectID):
                do {
                    guard let _message = try PersistedMessage.get(with: messageObjectID, within: obvContext.context) else {
                        return cancel(withReason: .couldNotFindMessage)
                    }
                    message = _message
                } catch {
                    return cancel(withReason: .coreDataError(error: error))
                }
                
                guard let message = message else {
                    assertionFailure(); return
                }
                
                do {
                    try message.setReactionFromOwnedIdentity(withEmoji: emoji, reactionTimestamp: reactionTimestamp)
                } catch {
                    return cancel(withReason: .coreDataError(error: error))
                }
                
            }

            // If the message was registered in the view context, we refresh it

            if let messageObjectID = message?.typedObjectID {
                ObvStack.shared.viewContext.perform {
                    guard let message = ObvStack.shared.viewContext.registeredObject(for: messageObjectID.objectID) else { return }
                    ObvStack.shared.viewContext.refresh(message, mergeChanges: false)
                }
            }
        }
    }

}

enum UpdateReactionsOperationReasonForCancel: LocalizedErrorWithLogType {
    case coreDataError(error: Error)
    case contextIsNil
    case couldNotFindContact
    case couldNotFindOwnedIdentity
    case couldNotFindGroupDiscussion
    case couldNotFindMessage
    case invalidEmoji

    var logType: OSLogType { .fault }

    var errorDescription: String? {
        switch self {
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .contextIsNil:
            return "The context is not set"
        case .couldNotFindOwnedIdentity:
            return "Could not find owned identity"
        case .couldNotFindContact:
            return "Could not find the contact identity"
        case .couldNotFindGroupDiscussion:
            return "Could not find group discussion"
        case .couldNotFindMessage:
            return "Could not find message to react"
        case .invalidEmoji:
            return "Invalid emoji"
        }
    }

}
