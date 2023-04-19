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
import ObvTypes


final class SyncPersistedInvitationsWithEngineOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    let obvDialogsFromEngine: [ObvDialog]
    let obvEngine: ObvEngine
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: SyncPersistedInvitationsWithEngineOperation.self))

    // If this operation finishes, this variable stores the engine's dialog that should be processed
    private(set) var obvDialogsFromEngineToProcess = [ObvDialog]()
    
    init(obvDialogsFromEngine: [ObvDialog], obvEngine: ObvEngine) {
        self.obvDialogsFromEngine = obvDialogsFromEngine
        self.obvEngine = obvEngine
        super.init()
    }
    
    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

        guard let viewContext = self.viewContext else {
            return cancel(withReason: .contextIsNil)
        }

        let uuidsWithinEngineForOwnedCryptoID: [ObvCryptoId: Set<UUID>] = obvDialogsFromEngine.reduce(into: [ObvCryptoId: Set<UUID>]()) { dict, obvDialog in
            if var existingSet = dict[obvDialog.ownedCryptoId] {
                existingSet.insert(obvDialog.uuid)
                dict[obvDialog.ownedCryptoId] = existingSet
            } else {
                dict[obvDialog.ownedCryptoId] = Set([obvDialog.uuid])
            }
        }
        
        obvContext.performAndWait {
            
            for (ownedCryptoId, uuidsWithinEngine) in uuidsWithinEngineForOwnedCryptoID {
            
                // Get the persisted invitations within the app
                
                let invitations: [PersistedInvitation]
                do {
                    invitations = try PersistedInvitation.getAll(ownedCryptoId: ownedCryptoId, within: obvContext.context)
                } catch {
                    return cancel(withReason: .coreDataError(error: error))
                }
                
                // Determine the invitations to create, delete, or update

                let uuidsWithinApp = Set(invitations.map { $0.uuid })
                let missingUuids = uuidsWithinEngine.subtracting(uuidsWithinApp)
                let uuidsToDelete = uuidsWithinApp.subtracting(uuidsWithinEngine)
                let uuidsToUpdate = uuidsWithinApp.subtracting(uuidsToDelete)

                // Create the missing invitations, leveraging the existing ProcessObvDialogOperation.
                
                do {
                    
                    let dialogsToProcess = obvDialogsFromEngine.filter({ missingUuids.contains($0.uuid) })
                    let ops = dialogsToProcess.map { ProcessObvDialogOperation(obvDialog: $0, obvEngine: obvEngine) }
                    
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
                    let ops = dialogsToProcess.map { ProcessObvDialogOperation(obvDialog: $0, obvEngine: obvEngine) }
                    
                    ops.forEach {
                        $0.obvContext = obvContext
                        $0.viewContext = viewContext
                        $0.main()
                    }
                    
                }
                
                // Delete obsolete invitations
                
                uuidsToDelete.forEach { uuid in
                    do {
                        if let invitation = try PersistedInvitation.getPersistedInvitation(uuid: uuid, ownedCryptoId: ownedCryptoId, within: obvContext.context) {
                            try invitation.delete()
                        }
                    } catch {
                        os_log("Could not delete obsolete PersistedInvitation during bootstrap: %{public}@", log: log, type: .fault, error.localizedDescription)
                        assertionFailure()
                        // Continue anyway
                    }
                }

            }
            
        }
            
    }
    
}
