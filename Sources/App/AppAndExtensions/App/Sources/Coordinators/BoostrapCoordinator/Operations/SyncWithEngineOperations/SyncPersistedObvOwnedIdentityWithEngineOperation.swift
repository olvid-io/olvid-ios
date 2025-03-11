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
import OlvidUtils
import ObvTypes
import ObvEngine
import ObvUICoreData
import os.log
import CoreData


/// This operation updates the app database in order to ensures it is in sync with the engine database for owned identities.
///
/// It leverages the hints provided by the ``ComputeHintsAboutRequiredOwnedIdentitiesSyncWithEngineOperation``.
final class SyncPersistedObvOwnedIdentityWithEngineOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {

    private let syncType: SyncType
    private let obvEngine: ObvEngine
    
    enum SyncType {
        case addToApp(ownedCryptoId: ObvCryptoId, isRestoringSyncSnapshotOrBackup: Bool)
        case deleteFromApp(ownedCryptoId: ObvCryptoId)
        case syncWithEngine(ownedCryptoId: ObvCryptoId)
        var ownedCryptoId: ObvCryptoId {
            switch self {
            case .addToApp(let ownedCryptoId, _),
                    .deleteFromApp(let ownedCryptoId),
                    .syncWithEngine(let ownedCryptoId):
                return ownedCryptoId
            }
        }
    }
    
    init(syncType: SyncType, obvEngine: ObvEngine) {
        self.syncType = syncType
        self.obvEngine = obvEngine
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {

            switch syncType {

            case .addToApp(let ownedCryptoId, let isRestoringSyncSnapshotOrBackup):
                
                // Make sure the owned identity still exists within the engine
                guard let ownedIdentityWithinEngine = try? obvEngine.getOwnedIdentity(with: ownedCryptoId) else {
                    assertionFailure()
                    return
                }
                
                // Make sure the owned identity still does not exist within within the app
                guard try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: obvContext.context) == nil else {
                    // Nothing left to do
                    return
                }
                
                // Create the owned identity within the app
                guard let persistedObvOwnedIdentity = PersistedObvOwnedIdentity(ownedIdentity: ownedIdentityWithinEngine, isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup, within: obvContext.context) else {
                    assertionFailure()
                    return
                }
                
                if let capabilities = try obvEngine.getCapabilitiesOfOwnedIdentity(ownedCryptoId) {
                    persistedObvOwnedIdentity.setOwnedCapabilities(to: capabilities)
                }

            case .deleteFromApp(let ownedCryptoId):
                
                // Make sure the owned identity still does not exists within the engine
                guard (try? obvEngine.getOwnedIdentity(with: ownedCryptoId)) == nil else {
                    assertionFailure()
                    return
                }
                
                // Make sure the owned identity still exists within within the app
                guard let ownedIdentityToDelete = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: obvContext.context) else {
                    // Nothing left to do
                    return
                }

                try ownedIdentityToDelete.delete()

            case .syncWithEngine(let ownedCryptoId):
                
                // Make sure the owned identity still exists within the engine
                guard let ownedIdentityWithinEngine = try? obvEngine.getOwnedIdentity(with: ownedCryptoId) else {
                    assertionFailure()
                    return
                }

                // Make sure the owned identity still exists within within the app
                guard let ownedIdentityToUpdate = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: obvContext.context) else {
                    // Nothing left to do
                    return
                }

                try ownedIdentityToUpdate.update(with: ownedIdentityWithinEngine)
                
                if let capabilities = try obvEngine.getCapabilitiesOfOwnedIdentity(ownedCryptoId) {
                    ownedIdentityToUpdate.setOwnedCapabilities(to: capabilities)
                }

            }
            
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
