/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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


/// Called when receiving a remote request (from a contact or from another owned device) to set or edit the reaction on a message.
final class ProcessSetOrUpdateReactionOnMessageOperation: ContextualOperationWithSpecificReasonForCancel<ProcessSetOrUpdateReactionOnMessageOperation.ReasonForCancel>, @unchecked Sendable {
    
    
    enum Requester {
        case contact(contactIdentifier: ObvContactIdentifier, overrideExistingReaction: Bool)
        case ownedIdentity(ownedCryptoId: ObvCryptoId)
    }

    private let reactionJSON: ReactionJSON
    private let requester: Requester
    private let messageUploadTimestampFromServer: Date

    init(reactionJSON: ReactionJSON, requester: Requester, messageUploadTimestampFromServer: Date) {
        self.reactionJSON = reactionJSON
        self.requester = requester
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
                
            case .contact(contactIdentifier: let contactIdentifier, overrideExistingReaction: let overrideExistingReaction):
                
                // Get the PersistedObvContactIdentity who requested the edit
                
                guard let contact = try PersistedObvContactIdentity.get(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindContact)
                }
                
                updatedMessage = try contact.processSetOrUpdateReactionOnMessageRequestFromThisContact(reactionJSON: reactionJSON, messageUploadTimestampFromServer: messageUploadTimestampFromServer, overrideExistingReaction: overrideExistingReaction)
                
            case .ownedIdentity(ownedCryptoId: let ownedCryptoId):
                
                // Get the PersistedObvContactIdentity who requested the edit
                
                guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindOwnedIdentity)
                }
                
                updatedMessage = try ownedIdentity.processSetOrUpdateReactionOnMessageRequestFromThisOwnedIdentity(reactionJSON: reactionJSON, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
                
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
        case couldNotFindOwnedIdentity
        case couldNotFindContact
        
        var logType: OSLogType {
            switch self {
            case .coreDataError,
                 .couldNotFindContact,
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
            case .couldNotFindContact:
                return "Could not find contact"
            }
        }

    }

}
