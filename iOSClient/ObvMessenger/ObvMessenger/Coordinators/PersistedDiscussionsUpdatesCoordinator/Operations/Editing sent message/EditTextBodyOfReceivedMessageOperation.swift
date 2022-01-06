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

final class EditTextBodyOfReceivedMessageOperation: ContextualOperationWithSpecificReasonForCancel<EditTextBodyOfReceivedMessageOperationReasonForCancel> {
    
    private let groupId: (groupUid: UID, groupOwner: ObvCryptoId)?
    private let requester: ObvContactIdentity
    private let newTextBody: String?
    private let receivedMessageToEdit: MessageReferenceJSON
    private let messageUploadTimestampFromServer: Date
    private let saveRequestIfMessageCannotBeFound: Bool

    init(newTextBody: String?, requester: ObvContactIdentity, groupId: (groupUid: UID, groupOwner: ObvCryptoId)?, receivedMessageToEdit: MessageReferenceJSON, messageUploadTimestampFromServer: Date, saveRequestIfMessageCannotBeFound: Bool) {
        self.newTextBody = newTextBody
        self.groupId = groupId
        self.requester = requester
        self.messageUploadTimestampFromServer = messageUploadTimestampFromServer
        self.receivedMessageToEdit = receivedMessageToEdit
        self.saveRequestIfMessageCannotBeFound = saveRequestIfMessageCannotBeFound
        super.init()
    }

    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

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
            
            // Make sure the requester is the one indicated as the identity of the MessageReferenceJSON
            
            guard contact.cryptoId.getIdentity() == receivedMessageToEdit.senderIdentifier else {
                return cancel(withReason: .requesterIsNotTheOneWhoSentTheOriginalMessage)
            }

            // Recover the appropriate discussion
            
            let discussion: PersistedDiscussion
            if let groupId = self.groupId {
                do {
                    guard let group = try PersistedContactGroup.getContactGroup(groupId: groupId, ownedIdentity: ownedIdentity) else {
                        return cancel(withReason: .couldNotFindGroupDiscussion)
                    }
                    discussion = group.discussion
                } catch {
                    return cancel(withReason: .coreDataError(error: error))
                }
            } else {
                discussion = contact.oneToOneDiscussion
            }
            
            // If the message to edit can be found, edit it. If not save the request for later if `saveRequestIfMessageCannotBeFound` is true
            
            do {
                if let receivedMessage = try PersistedMessageReceived.get(senderSequenceNumber: receivedMessageToEdit.senderSequenceNumber,
                                                                          senderThreadIdentifier: receivedMessageToEdit.senderThreadIdentifier,
                                                                          contactIdentity: contact.cryptoId.getIdentity(),
                                                                          discussion: discussion) {
                    try receivedMessage.editTextBody(newTextBody: newTextBody, requester: contact.cryptoId, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
                } else if saveRequestIfMessageCannotBeFound {
                    try RemoteDeleteAndEditRequest.createEditRequestIfAppropriate(body: newTextBody,
                                                                                  messageReference: receivedMessageToEdit,
                                                                                  serverTimestamp: messageUploadTimestampFromServer,
                                                                                  discussion: discussion)
                }
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }

        }
        
    }
}


enum EditTextBodyOfReceivedMessageOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case contextIsNil
    case couldNotFindContact
    case couldNotFindOwnedIdentity
    case couldNotFindGroupDiscussion
    case requesterIsNotTheOneWhoSentTheOriginalMessage
    case cannotFindMessageReceived
    case couldNotEditMessage(error: Error)

    var logType: OSLogType {
        switch self {
        case .coreDataError, .couldNotFindContact, .couldNotFindOwnedIdentity, .requesterIsNotTheOneWhoSentTheOriginalMessage, .couldNotFindGroupDiscussion, .cannotFindMessageReceived, .couldNotEditMessage, .contextIsNil:
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
        case .couldNotFindContact:
            return "Could not find the contact identity"
        case .couldNotFindGroupDiscussion:
            return "Could not find group discussion"
        case .requesterIsNotTheOneWhoSentTheOriginalMessage:
            return "The requester is not the one who sent the original message"
        case .cannotFindMessageReceived:
            return "Could not find received message to edit"
        case .couldNotEditMessage(error: let error):
            return "Could not edit message: \(error.localizedDescription)"

        }
    }

}
