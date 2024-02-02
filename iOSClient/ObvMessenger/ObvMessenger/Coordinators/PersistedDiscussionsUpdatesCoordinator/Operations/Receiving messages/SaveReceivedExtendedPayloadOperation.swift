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
import OlvidUtils
import os.log
import ObvEngine
import ObvEncoder
import ObvUICoreData
import CoreData


final class SaveReceivedExtendedPayloadOperation: ContextualOperationWithSpecificReasonForCancel<SaveReceivedExtendedPayloadOperationReasonForCancel> {

    private let extractReceivedExtendedPayloadOp: ExtractReceivedExtendedPayloadOperation

    init(extractReceivedExtendedPayloadOp: ExtractReceivedExtendedPayloadOperation) {
        self.extractReceivedExtendedPayloadOp = extractReceivedExtendedPayloadOp
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        guard let attachementImages = extractReceivedExtendedPayloadOp.attachementImages else {
            return cancel(withReason: .downsizedImagesIsNil)
        }
        
        let input = extractReceivedExtendedPayloadOp.input
        
        do {
            
            let permanentIDOfMessageToRefreshInViewContext: TypeSafeManagedObjectID<PersistedMessage>?
            
            switch input {
            case .messageSentByContact(obvMessage: let obvMessage):
                
                
                // Grab the persisted contact who sent the message
                
                guard let persistedContactIdentity = try PersistedObvContactIdentity.get(persisted: obvMessage.fromContactIdentity, whereOneToOneStatusIs: .any, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindPersistedObvContactIdentityInDatabase)
                }
                
                // Save the extended payload sent by this contact
                
                let permanentIDOfSentMessageToRefreshInViewContext = try persistedContactIdentity.saveExtendedPayload(foundIn: attachementImages, for: obvMessage)
                
                permanentIDOfMessageToRefreshInViewContext = permanentIDOfSentMessageToRefreshInViewContext?.downcast
                
            case .messageSentByOtherDeviceOfOwnedIdentity(obvOwnedMessage: let obvOwnedMessage):
                
                // Grab the persisted owned identity who sent the message on another owned device
                
                guard let persistedObvOwnedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: obvOwnedMessage.ownedCryptoId, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindOwnedIdentityInDatabase)
                }
                
                // Save the extended payload sent from another device of the owned identity
                
                let permanentIDOfMessageReceivedToRefreshInViewContext = try persistedObvOwnedIdentity.saveExtendedPayload(foundIn: attachementImages, for: obvOwnedMessage)
                
                permanentIDOfMessageToRefreshInViewContext = permanentIDOfMessageReceivedToRefreshInViewContext?.downcast
                
            }
            
            // If we saved an extended payload, we refresh the message in the view context
            
            if let permanentIDOfMessageToRefreshInViewContext {
                try? obvContext.addContextDidSaveCompletionHandler { error in
                    guard error == nil else { return }
                    ObvStack.shared.viewContext.perform {
                        if let draftInViewContext = ObvStack.shared.viewContext.registeredObjects
                            .filter({ !$0.isDeleted })
                            .first(where: { ($0 as? PersistedMessage)?.typedObjectID == permanentIDOfMessageToRefreshInViewContext }) {
                            ObvStack.shared.viewContext.refresh(draftInViewContext, mergeChanges: false)
                        }
                    }
                }
            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}

enum SaveReceivedExtendedPayloadOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case contextIsNil
    case coreDataError(error: Error)
    case downsizedImagesIsNil
    case couldNotFindPersistedObvContactIdentityInDatabase
    case couldNotFindOwnedIdentityInDatabase

    
    var logType: OSLogType {
        switch self {
        case .coreDataError, .contextIsNil:
            return .fault
        case .downsizedImagesIsNil, .couldNotFindPersistedObvContactIdentityInDatabase, .couldNotFindOwnedIdentityInDatabase:
            return .error
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .contextIsNil: return "Context is nil"
        case .coreDataError(error: let error): return "Core Data error: \(error.localizedDescription)"
        case .downsizedImagesIsNil: return "Downsized images is nil"
        case .couldNotFindPersistedObvContactIdentityInDatabase: return "Could not find contact in database"
        case .couldNotFindOwnedIdentityInDatabase: return "Could not find owned identity in database"
        }
    }

}
