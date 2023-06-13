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
import OlvidUtils
import ObvUICoreData


final class DeletePersistedMessagesOperation: ContextualOperationWithSpecificReasonForCancel<DeletePersistedMessageOperationReasonForCancel> {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: DeletePersistedMessagesOperation.self))

    private enum Input {
        case persistedMessageObjectIDs(_: Set<NSManagedObjectID>, requester: RequesterOfMessageDeletion)
        case provider(_: OperationProvidingPersistedMessageObjectIDsToDelete)
    }
    
    private let input: Input
    
    init(persistedMessageObjectIDs: Set<NSManagedObjectID>, requester: RequesterOfMessageDeletion) {
        self.input = .persistedMessageObjectIDs(persistedMessageObjectIDs, requester: requester)
        super.init()
    }
    
    
    init(operationProvidingPersistedMessageObjectIDsToDelete: OperationProvidingPersistedMessageObjectIDsToDelete) {
        self.input = .provider(operationProvidingPersistedMessageObjectIDsToDelete)
        super.init()
    }
 
    
    override func main() {
                
        let persistedMessageObjectIDs: Set<NSManagedObjectID>
        let requester: RequesterOfMessageDeletion
        switch input {
        case .persistedMessageObjectIDs(let objectIDs, let _requester):
            persistedMessageObjectIDs = objectIDs
            requester = _requester
        case .provider(let provider):
            persistedMessageObjectIDs = Set(provider.persistedMessageObjectIDsToDelete.map({ $0.objectID }))
            requester = provider.requester
        }
        
        guard !persistedMessageObjectIDs.isEmpty else { return }
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        obvContext.performAndWait {

            var infos = [InfoAboutWipedOrDeletedPersistedMessage]()

            for persistedMessageObjectID in persistedMessageObjectIDs {
                do {
                    guard let messageToDelete = try PersistedMessage.get(with: persistedMessageObjectID, within: obvContext.context) else { return }
                    let info = try messageToDelete.delete(requester: requester)
                    infos += [info]
                } catch {
                    return cancel(withReason: .coreDataError(error: error))
                }
            }
            
            
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
                return cancel(withReason: .coreDataError(error: error))
            }
                        
        }
        
    }
    
}


protocol OperationProvidingPersistedMessageObjectIDsToDelete: Operation {
    var persistedMessageObjectIDsToDelete: Set<TypeSafeManagedObjectID<PersistedMessage>> { get }
    var requester: RequesterOfMessageDeletion { get }
}


enum DeletePersistedMessageOperationReasonForCancel: LocalizedErrorWithLogType {

    case coreDataError(error: Error)
    case contextIsNil
    
    var logType: OSLogType {
        switch self {
        case .coreDataError, .contextIsNil:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .contextIsNil:
            return "Context is nil"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        }
    }
    
}
