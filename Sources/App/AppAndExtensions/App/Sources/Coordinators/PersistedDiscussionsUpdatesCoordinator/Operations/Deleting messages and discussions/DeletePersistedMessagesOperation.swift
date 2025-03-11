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
import ObvUICoreData
import ObvTypes


/// Called when processing the message deletion requested by an owned identity from the current device.
final class DeletePersistedMessagesOperation: ContextualOperationWithSpecificReasonForCancel<DeletePersistedMessagesOperation.ReasonForCancel>, @unchecked Sendable {
    
    private enum Input {
        case persistedMessageObjectIDs(_: Set<NSManagedObjectID>, ownedCryptoId: ObvCryptoId, deletionType: DeletionType)
        case provider(_: OperationProvidingPersistedMessageObjectIDsToDelete)
    }
    
    private let input: Input
    
    init(persistedMessageObjectIDs: Set<NSManagedObjectID>, ownedCryptoId: ObvCryptoId, deletionType: DeletionType) {
        self.input = .persistedMessageObjectIDs(persistedMessageObjectIDs, ownedCryptoId: ownedCryptoId, deletionType: deletionType)
        super.init()
    }
    
    
    init(operationProvidingPersistedMessageObjectIDsToDelete: OperationProvidingPersistedMessageObjectIDsToDelete) {
        self.input = .provider(operationProvidingPersistedMessageObjectIDsToDelete)
        super.init()
    }
 
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        let persistedMessageObjectIDs: Set<NSManagedObjectID>
        let ownedCryptoId: ObvCryptoId
        let deletionType: DeletionType
        switch input {
        case .persistedMessageObjectIDs(let objectIDs, let _ownedCryptoId, let _deletionType):
            persistedMessageObjectIDs = objectIDs
            ownedCryptoId = _ownedCryptoId
            deletionType = _deletionType
        case .provider(let provider):
            persistedMessageObjectIDs = Set(provider.persistedMessageObjectIDsToDelete.map({ $0.objectID }))
            ownedCryptoId = provider.ownedCryptoId
            deletionType = provider.deletionType
        }
        
        guard !persistedMessageObjectIDs.isEmpty else { return }
        
        do {
            
            guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: obvContext.context) else {
                return cancel(withReason: .cannotFindOwnedIdentity)
            }
            
            let infos = try ownedIdentity.processMessageDeletionRequestRequestedFromCurrentDeviceOfThisOwnedIdentity(
                persistedMessageObjectIDs: persistedMessageObjectIDs,
                deletionType: deletionType)
            
            do {
                try obvContext.addContextDidSaveCompletionHandler { error in
                    guard error == nil else { return }
                    
                    // We deleted some persisted messages. We notify about that.
                    InfoAboutWipedOrDeletedPersistedMessage.notifyThatMessagesWereWipedOrDeleted(infos)
                    
                    // Refresh objects in the view context
                    if let viewContext = self.viewContext {
                        InfoAboutWipedOrDeletedPersistedMessage.refresh(viewContext: viewContext, infos)
                    }
                    
                }
            } catch {
                assertionFailure() // In production, continue anyway
            }
            
        } catch {
            assertionFailure(error.localizedDescription)
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
 
    
    enum ReasonForCancel: LocalizedErrorWithLogType {

        case coreDataError(error: Error)
        case contextIsNil
        case cannotFindOwnedIdentity
        
        var logType: OSLogType {
            switch self {
            case .coreDataError, .contextIsNil, .cannotFindOwnedIdentity:
                return .fault
            }
        }
        
        var errorDescription: String? {
            switch self {
            case .contextIsNil:
                return "Context is nil"
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .cannotFindOwnedIdentity:
                return "Cannot find owned identity"
            }
        }
        
    }

}


protocol OperationProvidingPersistedMessageObjectIDsToDelete: Operation {
    var persistedMessageObjectIDsToDelete: Set<TypeSafeManagedObjectID<PersistedMessage>> { get }
    var ownedCryptoId: ObvCryptoId { get }
    var deletionType: DeletionType { get }
}
