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
import ObvEngine
import os.log
import ObvUICoreData
import CoreData
import ObvTypes


/// This operation updates the app database in order to ensures it is in sync with the engine database for owned devices.
///
/// It leverages the hints provided by the ``ComputeHintsAboutRequiredOwnedDevicesSyncWithEngineOperation``.
final class SyncPersistedObvOwnedDeviceWithEngineOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private let syncType: SyncType
    private let obvEngine: ObvEngine
    
    enum SyncType {
        case addToApp(ownedDeviceIdentifier: ObvOwnedDeviceIdentifier)
        case deleteFromApp(ownedDeviceIdentifier: ObvOwnedDeviceIdentifier)
        case syncWithEngine(ownedDeviceIdentifier: ObvOwnedDeviceIdentifier)
        var ownedCryptoId: ObvCryptoId {
            switch self {
            case .addToApp(let ownedDeviceIdentifier),
                    .deleteFromApp(let ownedDeviceIdentifier),
                    .syncWithEngine(let ownedDeviceIdentifier):
                return ownedDeviceIdentifier.ownedCryptoId
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
            
            guard let persistedOwnedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: syncType.ownedCryptoId, within: obvContext.context) else {
                assertionFailure()
                return
            }

            switch syncType {
                
            case .addToApp(ownedDeviceIdentifier: let ownedDeviceIdentifier):
            
                // Make sure the owned device still exists within the engine
                guard let obvOwnedDeviceWithinEngine = try obvEngine.getObvOwnedDevice(with: ownedDeviceIdentifier) else {
                    assertionFailure()
                    return
                }
                
                // Make sure the owned device still does not exist within within the app
                guard try PersistedObvOwnedDevice.getPersistedObvOwnedDevice(with: ownedDeviceIdentifier, within: obvContext.context) == nil else {
                    // Nothing left to do
                    return
                }
                
                // Create the owned device within the app
                try persistedOwnedIdentity.addOwnedDevice(obvOwnedDeviceWithinEngine)
                
            case .deleteFromApp(ownedDeviceIdentifier: let ownedDeviceIdentifier):
                
                // Make sure the owned device still does not exist within the engine
                guard try obvEngine.getObvOwnedDevice(with: ownedDeviceIdentifier) == nil else {
                    // This can happen for an inactive identity. This should be investigated.
                    assertionFailure()
                    return
                }

                // Delete the owned device (if it still exists) within the app
                try persistedOwnedIdentity.deleteOwnedDevice(ownedDeviceIdentifier)
                
            case .syncWithEngine(ownedDeviceIdentifier: let ownedDeviceIdentifier):
                
                // Make sure the owned device still exists within the engine
                guard let obvOwnedDeviceWithinEngine = try obvEngine.getObvOwnedDevice(with: ownedDeviceIdentifier) else {
                    assertionFailure()
                    return
                }

                // Update the owned device within the app
                try persistedOwnedIdentity.updateOwnedDevice(with: obvOwnedDeviceWithinEngine)
                
            }
            
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
