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


/// Called when the owned identity decided to set (or replace) a reaction on a message.
final class ProcessSetOrUpdateReactionOnMessageLocalRequestOperation: ContextualOperationWithSpecificReasonForCancel<ProcessSetOrUpdateReactionOnMessageLocalRequestOperation.ReasonForCancel>, @unchecked Sendable {
    
    private let ownedCryptoId: ObvCryptoId
    private let messageObjectID: TypeSafeManagedObjectID<PersistedMessage>
    private let newEmoji: String?
    
    init(ownedCryptoId: ObvCryptoId, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, newEmoji: String?) {
        self.ownedCryptoId = ownedCryptoId
        self.messageObjectID = messageObjectID
        self.newEmoji = newEmoji
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindOwnedIdentity)
            }
            
            let updatedMessage = try ownedIdentity.processSetOrUpdateReactionOnMessageLocalRequestFromThisOwnedIdentity(messageObjectID: messageObjectID, newEmoji: newEmoji)
            
            // If the message is registered in the view context, we refresh it
            
            if let messageObjectID = updatedMessage?.typedObjectID {
                try? obvContext.addContextDidSaveCompletionHandler { error in
                    guard error == nil else { return }
                    ObvStack.shared.viewContext.perform {
                        guard let message = ObvStack.shared.viewContext.registeredObject(for: messageObjectID.objectID) else { return }
                        ObvStack.shared.viewContext.refresh(message, mergeChanges: false)
                    }
                }
            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case contextIsNil
        case coreDataError(error: Error)
        case couldNotFindOwnedIdentity
        
        var logType: OSLogType {
            switch self {
            case .coreDataError,
                 .contextIsNil,
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
            case .couldNotFindOwnedIdentity:
                return "Could not find owned identity"
            }
        }

    }

}
