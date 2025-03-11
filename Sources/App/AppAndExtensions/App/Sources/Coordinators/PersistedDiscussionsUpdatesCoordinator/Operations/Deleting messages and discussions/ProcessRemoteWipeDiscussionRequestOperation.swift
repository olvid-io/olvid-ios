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
import OlvidUtils
import ObvTypes
import ObvUICoreData
import ObvEngine


/// This operation is called when receiving a request to wipe all messages in a particular discussion. This request can come either from a contact of the discussion or from another owned device.
final class ProcessRemoteWipeDiscussionRequestOperation: ContextualOperationWithSpecificReasonForCancel<ProcessRemoteWipeDiscussionRequestOperation.ReasonForCancel>, @unchecked Sendable {
        
    enum Requester {
        case contact(contactIdentifier: ObvContactIdentifier)
        case ownedIdentity(ownedCryptoId: ObvCryptoId)
    }

    private let deleteDiscussionJSON: DeleteDiscussionJSON
    private let requester: Requester
    private let messageUploadTimestampFromServer: Date

    init(deleteDiscussionJSON: DeleteDiscussionJSON, requester: Requester, messageUploadTimestampFromServer: Date) {
        self.deleteDiscussionJSON = deleteDiscussionJSON
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
            
            switch requester {
                
            case .contact(contactIdentifier: let contactIdentifier):
                
                // Get the PersistedObvContactIdentity
                
                guard let contact = try PersistedObvContactIdentity.get(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindContact)
                }
                
                // Request a deletion of all messages within the discussion
                
                try contact.processThisContactRemoteRequestToWipeAllMessagesWithinDiscussion(deleteDiscussionJSON: deleteDiscussionJSON, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
                
            case .ownedIdentity(ownedCryptoId: let ownedCryptoId):
                
                guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindOwnedIdentity)
                }
                
                // Request a deletion of all messages within the discussion
                
                try ownedIdentity.processThisOwnedIdentityRemoteRequestToWipeAllMessagesWithinDiscussion(deleteDiscussionJSON: deleteDiscussionJSON, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
                
            }
            
            result = .processed
            
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
        case contextIsNil
        case couldNotFindContact
        case couldNotFindOwnedIdentity
        
        var logType: OSLogType {
            switch self {
            case .coreDataError,
                 .contextIsNil:
                return .fault
            case .couldNotFindContact,
                    .couldNotFindOwnedIdentity:
                return .error
            }
        }
        
        var errorDescription: String? {
            switch self {
            case .contextIsNil:
                return "Context is nil"
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .couldNotFindContact:
                return "Could not find contact"
            case .couldNotFindOwnedIdentity:
                return "Could not find owned identity"
            }
        }
        
    }

}
