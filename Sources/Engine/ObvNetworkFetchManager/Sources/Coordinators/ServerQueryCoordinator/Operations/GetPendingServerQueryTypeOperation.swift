/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvCrypto
import ObvMetaManager


final class GetPendingServerQueryTypeOperation: ContextualOperationWithSpecificReasonForCancel<GetPendingServerQueryTypeOperation.ReasonForCancel>, @unchecked Sendable {
    
    private let pendingServerQueryObjectID: NSManagedObjectID
    private let delegateManager: ObvNetworkFetchDelegateManager
    private let identityDelegate: ObvIdentityDelegate
    
    init(pendingServerQueryObjectID: NSManagedObjectID, delegateManager: ObvNetworkFetchDelegateManager, identityDelegate: ObvIdentityDelegate) {
        self.pendingServerQueryObjectID = pendingServerQueryObjectID
        self.delegateManager = delegateManager
        self.identityDelegate = identityDelegate
        super.init()
    }
    
    private(set) var queryTypeAndOwnedCryptoId: (queryType: ServerQuery.QueryType, ownedCryptoId: ObvCryptoIdentity)?
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        let flowId = obvContext.flowId
        
        do {
            
            guard let serverQuery = try PendingServerQuery.get(objectId: pendingServerQueryObjectID, delegateManager: delegateManager, within: obvContext) else {
                return cancel(withReason: .pendingServerQueryNotFound)
            }
            
            let ownedIdentity = try serverQuery.ownedIdentity

            // Most server queries expect an existing, active owned identity.
            // Two exceptions for now: putGroupLog and deleteGroupLog, which can be executed after the deletion
            // of an owned identity
            
            switch serverQuery.queryType {
            case .deviceDiscovery,
                    .putUserData,
                    .getUserData,
                    .checkKeycloakRevocation,
                    .createGroupBlob,
                    .getGroupBlob,
                    .requestGroupBlobLock,
                    .updateGroupBlob,
                    .getKeycloakData,
                    .ownedDeviceDiscovery,
                    .setOwnedDeviceName,
                    .deactivateOwnedDevice,
                    .setUnexpiringOwnedDevice,
                    .sourceGetSessionNumber,
                    .sourceWaitForTargetConnection,
                    .targetSendEphemeralIdentity,
                    .transferRelay,
                    .transferWait,
                    .closeWebsocketConnection,
                    .uploadPreKeyForCurrentDevice:
                
                guard try identityDelegate.isOwnedIdentityActive(ownedIdentity: ownedIdentity, flowId: flowId) else {
                    serverQuery.deletePendingServerQuery(within: obvContext)
                    return cancel(withReason: .ownedIdentityIsNotActive)
                }
                
            case .putGroupLog,
                    .deleteGroupBlob:
                
                break
                
            }
            
            
            queryTypeAndOwnedCryptoId = (serverQuery.queryType, ownedIdentity)
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
    public enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case coreDataError(error: Error)
        case pendingServerQueryNotFound
        case ownedIdentityIsNotActive

        public var logType: OSLogType {
            switch self {
            case .coreDataError:
                return .fault
            case .ownedIdentityIsNotActive, .pendingServerQueryNotFound:
                return .error
            }
        }

        public var errorDescription: String? {
            switch self {
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .pendingServerQueryNotFound:
                return "PendingServerQuery not found in database"
            case .ownedIdentityIsNotActive:
                return "Owned identity is not active"
            }
        }

    }

}
