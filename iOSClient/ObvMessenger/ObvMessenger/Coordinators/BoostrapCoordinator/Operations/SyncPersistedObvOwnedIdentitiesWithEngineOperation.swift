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
import OlvidUtils
import ObvEngine
import os.log


final class SyncPersistedObvOwnedIdentitiesWithEngineOperation: ContextualOperationWithSpecificReasonForCancel<SyncPersistedObvOwnedIdentityWithEngineOperationReasonForCancel> {
    
    private let obvEngine: ObvEngine
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))

    init(obvEngine: ObvEngine) {
        self.obvEngine = obvEngine
        super.init()
    }
    
    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        // Get all owned identities within the engine
        
        let obvOwnedIdentitiesWithinEngine: Set<ObvOwnedIdentity>
        do {
            obvOwnedIdentitiesWithinEngine = try obvEngine.getOwnedIdentities()
        } catch {
            assertionFailure()
            return cancel(withReason: .couldNotGetOwnedIdentitiesFromEngine(error: error))
        }
        let cryptoIdsWithinEngine = Set(obvOwnedIdentitiesWithinEngine.map { $0.cryptoId })
        
        obvContext.performAndWait {
                    
            // Get the owned identities within the app
            
            let ownedIdentitiesWithApp: [PersistedObvOwnedIdentity]
            do {
                ownedIdentitiesWithApp = try PersistedObvOwnedIdentity.getAll(within: obvContext.context)
            } catch {
                assertionFailure()
                return cancel(withReason: .coreDataError(error: error))
            }

            // Determine the owned identities to create, delete, or update
            
            let cryptoIdsWithinApp = Set(ownedIdentitiesWithApp.map { $0.cryptoId })
            let missingCryptoIds = cryptoIdsWithinEngine.subtracting(cryptoIdsWithinApp)
            let cryptoIdsToDelete = cryptoIdsWithinApp.subtracting(cryptoIdsWithinEngine)
            let cryptoIdsToUpdate = cryptoIdsWithinApp.subtracting(cryptoIdsToDelete)

            os_log("Bootstrap: Number of missing owned identities to create: %d", log: log, type: .info, missingCryptoIds.count)
            os_log("Bootstrap: Number of existing owned identities to delete (for now we do not delete them): %d", log: log, type: .info, cryptoIdsToDelete.count)
            os_log("Bootstrap: Number of existing owned identities to refresh: %d", log: log, type: .info, cryptoIdsToUpdate.count)

            // Create the missing owned identities
            
            for ownedCryptoId in missingCryptoIds {
                
                guard let obvOwnedIdentity = obvOwnedIdentitiesWithinEngine.filter({ $0.cryptoId == ownedCryptoId }).first else {
                    os_log("Could not find owned identity to add, unexpected", log: log, type: .fault)
                    assertionFailure()
                    continue
                }
                
                guard PersistedObvOwnedIdentity(ownedIdentity: obvOwnedIdentity, within: obvContext.context) != nil else {
                    os_log("Failed to create persisted owned identity", log: log, type: .fault)
                    assertionFailure()
                    continue
                }
                
            }

            // Update the pre-existing identities
            
            for ownedCryptoId in cryptoIdsToUpdate {
                
                guard let obvOwnedIdentityFromEngine = obvOwnedIdentitiesWithinEngine.filter({ $0.cryptoId == ownedCryptoId }).first else {
                    os_log("Could not find owned identity to update within engine, unexpected", log: log, type: .fault)
                    assertionFailure()
                    continue
                }

                guard let ownedIdentityWithApp = ownedIdentitiesWithApp.filter({ $0.cryptoId == ownedCryptoId }).first else {
                    os_log("Could not find owned identity to update within app, unexpected", log: log, type: .fault)
                    assertionFailure()
                    continue
                }

                do {
                    try ownedIdentityWithApp.update(with: obvOwnedIdentityFromEngine)
                } catch {
                    os_log("Could not update app owned identity with engine owned identity: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                }
                
            }

            
        }
        
    }
    
}



enum SyncPersistedObvOwnedIdentityWithEngineOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case contextIsNil
    case couldNotGetOwnedIdentitiesFromEngine(error: Error)
    
    public var logType: OSLogType {
        switch self {
        case .coreDataError,
                .contextIsNil,
                .couldNotGetOwnedIdentitiesFromEngine:
            return .fault
        }
    }
    
    public var errorDescription: String? {
        switch self {
        case .contextIsNil:
            return "Context is nil"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotGetOwnedIdentitiesFromEngine:
            return "Could not get owned identities within engine."
        }
    }
    
    
}
