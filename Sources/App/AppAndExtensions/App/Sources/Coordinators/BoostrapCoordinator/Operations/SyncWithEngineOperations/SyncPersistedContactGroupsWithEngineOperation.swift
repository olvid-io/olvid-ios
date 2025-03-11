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


/// This operation updates the app database in order to ensures it is in sync with the engine database for contact groups (i.e., groups v1).
///
/// It leverages the hints provided by the ``ComputeHintsAboutRequiredContactGroupsSyncWithEngineOperation``.
final class SyncPersistedContactGroupWithEngineOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private let syncType: SyncType
    private let obvEngine: ObvEngine
    
    enum SyncType {
        case addToApp(groupIdentifier: ObvGroupV1Identifier, isRestoringSyncSnapshotOrBackup: Bool)
        case deleteFromApp(groupIdentifier: ObvGroupV1Identifier)
        case syncWithEngine(groupIdentifier: ObvGroupV1Identifier)
        var ownedCryptoId: ObvCryptoId {
            switch self {
            case .addToApp(let groupIdentifier, _),
                    .deleteFromApp(let groupIdentifier),
                    .syncWithEngine(let groupIdentifier):
                return groupIdentifier.ownedCryptoId
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
                
            case .addToApp(groupIdentifier: let groupIdentifier, isRestoringSyncSnapshotOrBackup: let isRestoringSyncSnapshotOrBackup):
            
                // Make sure the contact group still exists within the engine
                guard let obvContactGroupWithinEngine = try? obvEngine.getContactGroup(groupIdentifier: groupIdentifier) else {
                    assertionFailure()
                    return
                }
                
                try persistedOwnedIdentity.addOrUpdateContactGroup(with: obvContactGroupWithinEngine, isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup)

            case .deleteFromApp(groupIdentifier: let groupIdentifier):
                
                // Make sure the contact group still does not exist within the engine
                guard (try? obvEngine.getContactGroup(groupIdentifier: groupIdentifier)) == nil else {
                    assertionFailure()
                    return
                }

                try persistedOwnedIdentity.deleteContactGroup(with: groupIdentifier.groupV1Identifier)

            case .syncWithEngine(groupIdentifier: let groupIdentifier):

                // Make sure the contact group still exists within the engine
                guard let obvContactGroupWithinEngine = try? obvEngine.getContactGroup(groupIdentifier: groupIdentifier) else {
                    assertionFailure()
                    return
                }

                let groupHasUpdates = try persistedOwnedIdentity.updateContactGroup(with: obvContactGroupWithinEngine)
                
                if groupHasUpdates {
                    if let objectID = obvContext.context.registeredObjects
                        .compactMap({ $0 as? PersistedContactGroup })
                        .first(where: { (try? $0.obvGroupIdentifier) == groupIdentifier }) {
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
