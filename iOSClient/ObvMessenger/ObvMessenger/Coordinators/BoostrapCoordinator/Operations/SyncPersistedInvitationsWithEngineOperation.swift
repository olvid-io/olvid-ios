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
import OlvidUtils
import ObvEngine
import os.log
import ObvTypes
import ObvUICoreData
import CoreData


final class SyncPersistedInvitationsWithEngineOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    let obvDialogsFromEngine: [ObvDialog]
    let obvEngine: ObvEngine
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: SyncPersistedInvitationsWithEngineOperation.self))
    private let syncAtomRequestDelegate: ObvSyncAtomRequestDelegate

    init(obvDialogsFromEngine: [ObvDialog], obvEngine: ObvEngine, syncAtomRequestDelegate: ObvSyncAtomRequestDelegate) {
        self.obvDialogsFromEngine = obvDialogsFromEngine
        self.obvEngine = obvEngine
        self.syncAtomRequestDelegate = syncAtomRequestDelegate
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        let uuidsWithinEngineForOwnedCryptoId: [ObvCryptoId: Set<UUID>] = obvDialogsFromEngine.reduce(into: [ObvCryptoId: Set<UUID>]()) { dict, obvDialog in
            if var existingSet = dict[obvDialog.ownedCryptoId] {
                existingSet.insert(obvDialog.uuid)
                dict[obvDialog.ownedCryptoId] = existingSet
            } else {
                dict[obvDialog.ownedCryptoId] = Set([obvDialog.uuid])
            }
        }

        do {
            
            // Get the owned identities within the app
            
            let ownedIdentities = try PersistedObvOwnedIdentity.getAll(within: obvContext.context)
            let ownedCryptoIdsWithApp = ownedIdentities.map({ $0.cryptoId })
            
            for ownedCryptoIdWithApp in ownedCryptoIdsWithApp {
                
                // Get the persisted invitations for this owned identity within the app within the app
                
                let invitations = try PersistedInvitation.getAll(ownedCryptoId: ownedCryptoIdWithApp, within: obvContext.context)
                
                // Determine the invitations for this owned identity within the engine
                
                let uuidsWithinEngine = uuidsWithinEngineForOwnedCryptoId[ownedCryptoIdWithApp] ?? Set()

                // Determine the invitations to create, delete, or update
                
                let uuidsWithinApp = Set(invitations.map { $0.uuid })
                let missingUuids = uuidsWithinEngine.subtracting(uuidsWithinApp)
                let uuidsToDelete = uuidsWithinApp.subtracting(uuidsWithinEngine)
                let uuidsToUpdate = uuidsWithinApp.subtracting(uuidsToDelete)

                // Create the missing invitations, leveraging the existing ProcessObvDialogOperation.
                
                do {
                    
                    let dialogsToProcess = obvDialogsFromEngine.filter({ missingUuids.contains($0.uuid) })
                    let ops = dialogsToProcess.map {
                        ProcessObvDialogOperation(obvDialog: $0,
                                                  obvEngine: obvEngine,
                                                  syncAtomRequestDelegate: syncAtomRequestDelegate)
                    }
                    
                    ops.forEach {
                        $0.obvContext = obvContext
                        $0.viewContext = viewContext
                        $0.main()
                    }
                    
                }
                
                // Update pre-existing invitations, leveraging the existing ProcessObvDialogOperation
                // Although the code is almost the same as the 'create' case, we separate it for clarity
                
                do {
                    
                    let dialogsToProcess = obvDialogsFromEngine.filter({ uuidsToUpdate.contains($0.uuid) })
                    let ops = dialogsToProcess.map {
                        ProcessObvDialogOperation(obvDialog: $0,
                                                  obvEngine: obvEngine,
                                                  syncAtomRequestDelegate: syncAtomRequestDelegate)
                    }
                    
                    ops.forEach {
                        $0.obvContext = obvContext
                        $0.viewContext = viewContext
                        $0.main()
                    }
                    
                }
                
                // Delete obsolete invitations
                
                uuidsToDelete.forEach { uuid in
                    do {
                        if let invitation = try PersistedInvitation.getPersistedInvitation(uuid: uuid, ownedCryptoId: ownedCryptoIdWithApp, within: obvContext.context) {
                            try invitation.delete()
                        }
                    } catch {
                        os_log("Could not delete obsolete PersistedInvitation during bootstrap: %{public}@", log: log, type: .fault, error.localizedDescription)
                        assertionFailure()
                        // Continue anyway
                    }
                }
                
            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
                
    }
    
}
