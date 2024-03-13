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


/// This operation updates the app database in order to ensures it is in sync with the engine database for contact devices.
///
/// It leverages the hints provided by the ``ComputeHintsAboutRequiredContactDevicesSyncWithEngineOperation``.
final class SyncPersistedObvContactDeviceWithEngineOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    private let syncType: SyncType
    private let obvEngine: ObvEngine
    
    enum SyncType {
        case addToApp(contactDeviceIdentifier: ObvContactDeviceIdentifier, isRestoringSyncSnapshotOrBackup: Bool)
        case deleteFromApp(contactDeviceIdentifier: ObvContactDeviceIdentifier)
        case syncWithEngine(contactDeviceIdentifier: ObvContactDeviceIdentifier, isRestoringSyncSnapshotOrBackup: Bool)
        var ownedCryptoId: ObvCryptoId {
            switch self {
            case .addToApp(let contactDeviceIdentifier, _),
                    .deleteFromApp(let contactDeviceIdentifier),
                    .syncWithEngine(let contactDeviceIdentifier, _):
                return contactDeviceIdentifier.ownedCryptoId
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
                
            case .addToApp(contactDeviceIdentifier: let contactDeviceIdentifier, isRestoringSyncSnapshotOrBackup: let isRestoringSyncSnapshotOrBackup):
            
                // Make sure the owned device still exists within the engine
                guard let obvContactDeviceWithinEngine = try obvEngine.getObvContactDevice(with: contactDeviceIdentifier) else {
                    assertionFailure()
                    return
                }
                
                try persistedOwnedIdentity.addContactDevice(with: obvContactDeviceWithinEngine, isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup)
                
            case .deleteFromApp(contactDeviceIdentifier: let contactDeviceIdentifier):
                
                // Make sure the contact device still does not exist within the engine
                guard try obvEngine.getObvContactDevice(with: contactDeviceIdentifier) == nil else {
                    assertionFailure()
                    return
                }

                // Delete the owned device (if it still exists) within the app
                try persistedOwnedIdentity.deleteContactDevice(with: contactDeviceIdentifier)
                
            case .syncWithEngine(contactDeviceIdentifier: let contactDeviceIdentifier, isRestoringSyncSnapshotOrBackup: let isRestoringSyncSnapshotOrBackup):
                
                // Make sure the owned device still exists within the engine
                guard let obvContactDeviceWithinEngine = try obvEngine.getObvContactDevice(with: contactDeviceIdentifier) else {
                    assertionFailure()
                    return
                }

                // Update the owned device within the app
                let deviceHadToBeUpdated = try persistedOwnedIdentity.updateContactDevice(with: obvContactDeviceWithinEngine, isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup)
             
                if deviceHadToBeUpdated {
                    if let objectID = obvContext.context.registeredObjects
                        .compactMap({ $0 as? PersistedObvContactDevice })
                        .first(where: { (try? $0.contactDeviceIdentifier) == contactDeviceIdentifier }) {
                        try? obvContext.addContextDidSaveCompletionHandler { error in
                            guard error == nil else { return }
                            ObvStack.shared.viewContext.perform {
                                if let objectToRefresh = ObvStack.shared.viewContext.registeredObjects.first(where: { $0.objectID == objectID }) {
                                    ObvStack.shared.viewContext.refresh(objectToRefresh, mergeChanges: true)
                                }
                            }
                        }
                    }
                }

            }
            
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
