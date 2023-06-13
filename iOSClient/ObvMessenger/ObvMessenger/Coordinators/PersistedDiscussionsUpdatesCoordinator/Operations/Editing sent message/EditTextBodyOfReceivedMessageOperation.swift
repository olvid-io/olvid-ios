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
import ObvUICoreData


final class EditTextBodyOfReceivedMessageOperation: ContextualOperationWithSpecificReasonForCancel<EditTextBodyOfReceivedMessageOperationReasonForCancel> {
    
    private let groupIdentifier: GroupIdentifier?
    private let requester: ObvContactIdentity
    private let newTextBody: String?
    private let receivedMessageToEdit: MessageReferenceJSON
    private let messageUploadTimestampFromServer: Date
    private let saveRequestIfMessageCannotBeFound: Bool
    private let newMentions: [MessageJSON.UserMention]

    init(newTextBody: String?, requester: ObvContactIdentity, groupIdentifier: GroupIdentifier?, receivedMessageToEdit: MessageReferenceJSON, messageUploadTimestampFromServer: Date, saveRequestIfMessageCannotBeFound: Bool, newMentions: [MessageJSON.UserMention]) {
        self.newTextBody = newTextBody
        self.groupIdentifier = groupIdentifier
        self.requester = requester
        self.messageUploadTimestampFromServer = messageUploadTimestampFromServer
        self.receivedMessageToEdit = receivedMessageToEdit
        self.saveRequestIfMessageCannotBeFound = saveRequestIfMessageCannotBeFound
        self.newMentions = newMentions
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
            
            // Make sure the requester is the one indicated as the identity of the MessageReferenceJSON
            
            guard contact.cryptoId.getIdentity() == receivedMessageToEdit.senderIdentifier else {
                return cancel(withReason: .requesterIsNotTheOneWhoSentTheOriginalMessage)
            }

            // Recover the appropriate discussion
            
            let discussion: PersistedDiscussion
            do {
                switch groupIdentifier {
                case .none:
                    guard let oneToOneDiscussion = contact.oneToOneDiscussion else {
                        return cancel(withReason: .couldNotFindAnyDiscussion)
                    }
                    discussion = oneToOneDiscussion
                case .groupV1(groupV1Identifier: let groupV1Identifier):
                    guard let group = try PersistedContactGroup.getContactGroup(groupId: groupV1Identifier, ownedIdentity: ownedIdentity) else {
                        return cancel(withReason: .couldNotFindGroupDiscussion)
                    }
                    discussion = group.discussion
                case .groupV2(groupV2Identifier: let groupV2Identifier):
                    guard let group = try PersistedGroupV2.get(ownIdentity: ownedIdentity, appGroupIdentifier: groupV2Identifier) else {
                        return cancel(withReason: .couldNotFindGroupDiscussion)
                    }
                    guard let _discussion = group.discussion else {
                        return cancel(withReason: .couldNotFindAnyDiscussion)
                    }
                    discussion = _discussion
                }                
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
            // If the message to edit can be found, edit it. If not save the request for later if `saveRequestIfMessageCannotBeFound` is true
            
            do {
                if let receivedMessage = try PersistedMessageReceived.get(senderSequenceNumber: receivedMessageToEdit.senderSequenceNumber,
                                                                          senderThreadIdentifier: receivedMessageToEdit.senderThreadIdentifier,
                                                                          contactIdentity: contact.cryptoId.getIdentity(),
                                                                          discussion: discussion) {
                    try receivedMessage.replaceContentWith(newBody: newTextBody, newMentions: Set(newMentions), requester: contact.cryptoId, messageUploadTimestampFromServer: messageUploadTimestampFromServer)

                    // If the message appears as a reply-to in some other messages, we must refresh those messages in the view context
                    // Similarly, if a draft is replying to this message, we must refresh the draft in the view context

                    do {
                        let repliesObjectIDs = receivedMessage.repliesObjectIDs.map({ $0.objectID })
                        let draftObjectIDs = try PersistedDraft.getObjectIDsOfAllDraftsReplyingTo(message: receivedMessage).map({ $0.objectID })
                        let objectIDsToRefresh = repliesObjectIDs + draftObjectIDs
                        if !objectIDsToRefresh.isEmpty {
                            try? obvContext.addContextDidSaveCompletionHandler { error in
                                guard error == nil else { return }
                                DispatchQueue.main.async {
                                    let objectsToRefresh = ObvStack.shared.viewContext.registeredObjects
                                        .filter({ objectIDsToRefresh.contains($0.objectID) })
                                    objectsToRefresh.forEach { objectID in
                                        ObvStack.shared.viewContext.refresh(objectID, mergeChanges: true)
                                    }
                                }
                            }
                        }
                    } catch {
                        assertionFailure()
                        // In production, continue anyway
                    }

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
    case couldNotFindAnyDiscussion

    var logType: OSLogType {
        switch self {
        case .coreDataError, .couldNotFindContact, .couldNotFindOwnedIdentity, .requesterIsNotTheOneWhoSentTheOriginalMessage, .couldNotFindGroupDiscussion, .cannotFindMessageReceived, .couldNotEditMessage, .contextIsNil, .couldNotFindAnyDiscussion:
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
        case .couldNotFindAnyDiscussion:
            return "Could not find any discussion"
        }
    }

}
