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
import ObvEngine
import ObvTypes
import OlvidUtils
import ObvCrypto
import ObvUICoreData


final class EditTextBodyOfReceivedMessageOperation: ContextualOperationWithSpecificReasonForCancel<EditTextBodyOfReceivedMessageOperation.ReasonForCancel> {
    
    enum Requester {
        case contact(contactIdentifier: ObvContactIdentifier)
        case ownedIdentity(ownedCryptoId: ObvCryptoId)
    }

    private let updateMessageJSON: UpdateMessageJSON
    private let requester: Requester
    private let messageUploadTimestampFromServer: Date

    init(updateMessageJSON: UpdateMessageJSON, requester: Requester, messageUploadTimestampFromServer: Date) {
        self.requester = requester
        self.updateMessageJSON = updateMessageJSON
        self.messageUploadTimestampFromServer = messageUploadTimestampFromServer
        super.init()
    }

    
    enum Result {
        case couldNotFindGroupV2InDatabase(groupIdentifier: GroupV2Identifier)
        case processed
    }

    private(set) var result: Result?

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            let updatedMessage: PersistedMessage?
            
            switch requester {
                
            case .contact(contactIdentifier: let contactIdentifier):
                
                // Get the PersistedObvContactIdentity who requested the edit
                
                guard let contact = try PersistedObvContactIdentity.get(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindContact)
                }
                
                // Process the edit request. If the message is updated, the call returns this updated message
                
                updatedMessage = try contact.processUpdateMessageRequestFromThisContact(
                    updateMessageJSON: updateMessageJSON,
                    messageUploadTimestampFromServer: messageUploadTimestampFromServer)
                
            case .ownedIdentity(ownedCryptoId: let ownedCryptoId):
                
                // Get the PersistedObvContactIdentity who requested the edit
                
                guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindOwnedIdentity)
                }
                
                // Process the edit request. If the message is updated, the call returns this updated message
                
                updatedMessage = try ownedIdentity.processUpdateMessageRequestFromThisOwnedIdentity(
                    updateMessageJSON: updateMessageJSON,
                    messageUploadTimestampFromServer: messageUploadTimestampFromServer)
                
            }
            
            result = .processed
            
            // If the message appears as a reply-to in some other messages, we must refresh those messages in the view context
            // Similarly, if a draft is replying to this message, we must refresh the draft in the view context
            
            if let updatedMessage {
                do {
                    let repliesObjectIDs = updatedMessage.repliesObjectIDs.map({ $0.objectID })
                    let draftObjectIDs = try PersistedDraft.getObjectIDsOfAllDraftsReplyingTo(message: updatedMessage).map({ $0.objectID })
                    let objectIDsToRefresh = [updatedMessage.objectID] + repliesObjectIDs + draftObjectIDs
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
            }
            
        } catch {
            if let error = error as? ObvUICoreDataError {
                switch error {
                case .couldNotFindGroupV2InDatabase(groupIdentifier: let groupIdentifier):
                    result = .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
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
        
        case coreDataError(error: Error)
        case couldNotFindContact
        case couldNotFindOwnedIdentity

        var logType: OSLogType {
            switch self {
            case .coreDataError,
                 .couldNotFindContact,
                 .couldNotFindOwnedIdentity:
                return .fault
            }
        }
        
        var errorDescription: String? {
            switch self {
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .couldNotFindOwnedIdentity:
                return "Could not find owned identity"
            case .couldNotFindContact:
                return "Could not find the contact identity"
            }
        }

    }

}
