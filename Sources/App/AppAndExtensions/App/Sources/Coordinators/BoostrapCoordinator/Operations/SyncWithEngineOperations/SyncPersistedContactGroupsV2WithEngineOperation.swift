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
import ObvTypes
import ObvUICoreData
import CoreData



/// This operation updates the app database in order to ensures it is in sync with the engine database for contact groups (i.e., groups v1).
///
/// It leverages the hints provided by the ``ComputeHintsAboutRequiredContactGroupsV2SyncWithEngineOperation``.
final class SyncPersistedContactGroupV2WithEngineOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private let syncType: SyncType
    private let obvEngine: ObvEngine
    
    enum SyncType {
        case addToApp(groupIdentifier: ObvGroupV2Identifier, isRestoringSyncSnapshotOrBackup: Bool)
        case deleteFromApp(groupIdentifier: ObvGroupV2Identifier)
        case syncWithEngine(groupIdentifier: ObvGroupV2Identifier, isRestoringSyncSnapshotOrBackup: Bool)
        var ownedCryptoId: ObvCryptoId {
            switch self {
            case .addToApp(let groupIdentifier, _),
                    .deleteFromApp(let groupIdentifier),
                    .syncWithEngine(let groupIdentifier, _):
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
                guard let obvGroupV2WithinEngine = try? obvEngine.getObvGroupV2(with: groupIdentifier) else {
                    assertionFailure()
                    return
                }
                
                _ = try persistedOwnedIdentity.createOrUpdateGroupV2(obvGroupV2: obvGroupV2WithinEngine, createdByMe: false, isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup)

            case .deleteFromApp(groupIdentifier: let groupIdentifier):
                
                // Make sure the contact group still does not exist within the engine
                guard (try? obvEngine.getObvGroupV2(with: groupIdentifier)) == nil else {
                    assertionFailure()
                    return
                }

                try persistedOwnedIdentity.deleteGroupV2(with: groupIdentifier)

            case .syncWithEngine(groupIdentifier: let groupIdentifier, isRestoringSyncSnapshotOrBackup: let isRestoringSyncSnapshotOrBackup):

                // Make sure the contact group still exists within the engine
                guard let obvGroupV2WithinEngine = try? obvEngine.getObvGroupV2(with: groupIdentifier) else {
                    assertionFailure()
                    return
                }

                let persistedGroup = try persistedOwnedIdentity.createOrUpdateGroupV2(obvGroupV2: obvGroupV2WithinEngine, createdByMe: false, isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup)
                
                let groupHasUpdates = persistedGroup.isInserted || !persistedGroup.changedValues().isEmpty
                
                if groupHasUpdates {
                    if let objectID = obvContext.context.registeredObjects
                        .compactMap({ $0 as? PersistedGroupV2 })
                        .first(where: { $0.groupIdentifier == groupIdentifier.identifier.appGroupIdentifier }) {
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
