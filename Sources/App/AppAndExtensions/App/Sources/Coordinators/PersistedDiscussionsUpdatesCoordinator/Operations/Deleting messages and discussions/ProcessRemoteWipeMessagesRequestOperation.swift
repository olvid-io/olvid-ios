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


/// This method is typically called when we receive a request to delete some messages by a contact or by an owned identity willing to globally delete these messages.
final class ProcessRemoteWipeMessagesRequestOperation: ContextualOperationWithSpecificReasonForCancel<ProcessRemoteWipeMessagesRequestOperation.ReasonForCancel>, @unchecked Sendable {

    enum Requester {
        case contact(contactIdentifier: ObvContactIdentifier)
        case ownedIdentity(ownedCryptoId: ObvCryptoId)
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
        case couldNotFindGroupV2InDatabase(groupIdentifier: GroupV2Identifier)
        case processed
    }

    private(set) var result: Result?

    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        guard !deleteMessagesJSON.messagesToDelete.isEmpty else {
            result = .processed
            assertionFailure()
            return
        }
        
        do {
            
            let infosAboutWipedMessages: [InfoAboutWipedOrDeletedPersistedMessage]
            
            switch requester {
                
            case .contact(contactIdentifier: let contactIdentifier):
                
                // Get the PersistedObvContactIdentity who requested the wipe
                
                guard let contact = try PersistedObvContactIdentity.get(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindContact)
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
                case .couldNotFindGroupV2InDatabase(groupIdentifier: let groupIdentifier):
                    result = .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
                    return
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
        case couldNotFindContact

        var logType: OSLogType {
            switch self {
            case .coreDataError, .couldNotFindOwnedIdentity, .couldNotFindContact:
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
