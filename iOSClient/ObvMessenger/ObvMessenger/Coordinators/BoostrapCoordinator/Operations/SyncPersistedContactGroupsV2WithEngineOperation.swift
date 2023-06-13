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
import ObvUICoreData


final class SyncPersistedContactGroupsV2WithEngineOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    private let obvEngine: ObvEngine
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: SyncPersistedContactGroupsV2WithEngineOperation.self))
    
    init(obvEngine: ObvEngine) {
        self.obvEngine = obvEngine
        super.init()
    }
    
    override func main() {
        
        os_log("Syncing Persisted Contact Groups V2 with Engine Contact Groups V2", log: log, type: .info)
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        obvContext.performAndWait {
            
            do {
                
                // Delete orphaned `PersistedGroupV2Member` entities
                
                try PersistedGroupV2Member.deleteOrphanedPersistedGroupV2Members(within: obvContext.context)
                
                // Loop over all owned identities
                
                let ownedIdentities = try PersistedObvOwnedIdentity.getAll(within: obvContext.context)
                
                try ownedIdentities.forEach { ownedIdentity in

                    let groups: Set<ObvGroupV2>
                    do {
                        groups = try obvEngine.getAllObvGroupV2OfOwnedIdentity(with: ownedIdentity.cryptoId)
                    } catch {
                        assertionFailure()
                        os_log("Could not get all group v2 from engine for an owned identity: %{public}@", log: log, type: .fault, error.localizedDescription)
                        return
                    }
                    
                    // Create or update the PersistedGroupV2 instances
                    
                    groups.forEach { obvGroupV2 in
                        do {
                            _ = try PersistedGroupV2.createOrUpdate(obvGroupV2: obvGroupV2,
                                                                    createdByMe: false,
                                                                    within: obvContext.context)
                        } catch {
                            os_log("Could not create or update a PersistedGroupV2: %{public}@", log: log, type: .fault, error.localizedDescription)
                            assertionFailure()
                            // Continue anyway
                        }
                    }
                    
                    // Remove any PersistedGroupV2 that does not exist within the engine

                    let persistedGroups = try PersistedGroupV2.getAllPersistedGroupV2(ownedIdentity: ownedIdentity)
                    let appGroupIdentifierToKeep = Set(groups.map({ $0.appGroupIdentifier }))
                    for persistedGroup in persistedGroups {
                        if appGroupIdentifierToKeep.contains(persistedGroup.groupIdentifier) { continue }
                        do {
                            try persistedGroup.delete()
                        } catch {
                            assertionFailure()
                            os_log("Could not delete one of the PersistedGroupV2 present within the app but not within the engine: %{public}@", log: log, type: .fault, error.localizedDescription)
                            continue
                        }
                    }
                     
                    // Make sure that all remaining persisted contact groups do have an associated display contact group.
                    // For those that have one, make sure it is in sync.
                    
                    for group in persistedGroups {
                        guard !group.isDeleted else { continue }
                        do {
                            try group.createOrUpdateTheAssociatedDisplayedContactGroup()
                        } catch {
                            os_log("Could not create or update the underlying displayed contact group of a persisted contact group: %{public}@", log: log, type: .fault, error.localizedDescription)
                            assertionFailure() // In production, continue anyway
                        }
                    }

                } // End ownedIdentities.forEach
                
            } catch {
                assertionFailure()
                return cancel(withReason: .coreDataError(error: error))
            }
                
        } // End obvContext.performAndWait
    }
    
}
