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
import os.log
import CoreData
import OlvidUtils
import ObvMetaManager


final class SetWebSocketPendingServerQueryResponseOperation: ContextualOperationWithSpecificReasonForCancel<SetWebSocketPendingServerQueryResponseOperation.ReasonForCancel> {
    
    private let pendingServerQueryObjectId: NSManagedObjectID
    private let serverResponseType: ServerResponse.ResponseType
    private let delegateManager: ObvNetworkFetchDelegateManager
    
    init(pendingServerQueryObjectId: NSManagedObjectID, serverResponseType: ServerResponse.ResponseType, delegateManager: ObvNetworkFetchDelegateManager) {
        self.pendingServerQueryObjectId = pendingServerQueryObjectId
        self.serverResponseType = serverResponseType
        self.delegateManager = delegateManager
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            guard let pendingServerQuery = try PendingServerQuery.get(objectId: pendingServerQueryObjectId, delegateManager: delegateManager, within: obvContext) else {
                assertionFailure()
                return cancel(withReason: .couldNotFindPendingServerQueryInDatabase)
            }
            
            guard pendingServerQuery.isWebSocket else {
                assertionFailure()
                return cancel(withReason: .pendingServerQueryIsNotOfWebSocketType)
            }

            pendingServerQuery.responseType = serverResponseType

            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
 
    
    public enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case coreDataError(error: Error)
        case couldNotFindPendingServerQueryInDatabase
        case pendingServerQueryIsNotOfWebSocketType

        public var logType: OSLogType {
            return .fault
        }

        public var errorDescription: String? {
            switch self {
            case .couldNotFindPendingServerQueryInDatabase:
                return "Could not find PendingServerQuery in database"
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .pendingServerQueryIsNotOfWebSocketType:
                return "PendingServerQuery is not of WebSocket type"
            }
        }

    }

}
