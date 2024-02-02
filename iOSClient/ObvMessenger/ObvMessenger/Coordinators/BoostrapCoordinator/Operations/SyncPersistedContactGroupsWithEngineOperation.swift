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
import ObvUICoreData
import CoreData



final class SyncPersistedContactGroupsWithEngineOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    private let obvEngine: ObvEngine
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: SyncPersistedContactGroupsWithEngineOperation.self))
    
    init(obvEngine: ObvEngine) {
        self.obvEngine = obvEngine
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        os_log("Syncing Persisted Contact Groups with Engine Contact Groups", log: log, type: .info)
        
        let ownedIdentities: [PersistedObvOwnedIdentity]
        do {
            ownedIdentities = try PersistedObvOwnedIdentity.getAll(within: obvContext.context)
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
        ownedIdentities.forEach { ownedIdentity in
            
            let obvContactGroups: Set<ObvContactGroup>
            do {
                obvContactGroups = try obvEngine.getAllContactGroupsForOwnedIdentity(with: ownedIdentity.cryptoId)
            } catch {
                os_log("Could not get all group identifiers from engine: %{public}@", log: log, type: .fault, error.localizedDescription)
                return
            }
            
            // Split the set of obvContactGroups into missing and existing contact groups
            
            var missingObvContactGroups: Set<ObvContactGroup> // Groups that exist within the engine, but not within the app
            var existingObvContactGroups: Set<ObvContactGroup> // Groups that exist both within the engine and within the app
            do {
                missingObvContactGroups = try obvContactGroups.filter({
                    let groupIdentifier = $0.groupIdentifier
                    return (try PersistedContactGroup.getContactGroup(groupIdentifier: groupIdentifier, ownedIdentity: ownedIdentity)) == nil
                })
                existingObvContactGroups = obvContactGroups.subtracting(missingObvContactGroups)
            } catch {
                os_log("Could not construct a list of missing obv contact groups", log: log, type: .fault)
                return
            }
            
            os_log("Number of contact groups existing within the engine but missing within the app: %{public}d", log: log, type: .info, missingObvContactGroups.count)
            os_log("Number of contact groups existing within the engine and present within the app: %{public}d", log: log, type: .info, existingObvContactGroups.count)
            
            // Create a persisted contact group for each missing obv contact group.
            // Each time a contact group is created within the app, add this group to the list of existing contact group within the app
            
            while let obvContactGroup = missingObvContactGroups.popFirst() {
                switch obvContactGroup.groupType {
                case .joined:
                    guard (try? PersistedContactGroupJoined(contactGroup: obvContactGroup, within: obvContext.context)) != nil else {
                        os_log("Could not create a missing persisted contact group joined", log: log, type: .error)
                        continue
                    }
                case .owned:
                    guard (try? PersistedContactGroupOwned(contactGroup: obvContactGroup, within: obvContext.context)) != nil  else {
                        os_log("Could not create a missing persisted contact group owned", log: log, type: .error)
                        continue
                    }
                }
                // If we reach this line, a new contact group was created within the app. We can add it to the list of existingObvContactGroups.
                existingObvContactGroups.insert(obvContactGroup)
            }
            
            // Sync each existing persisted contact group with its engine's counterpart
            
            for obvContactGroup in existingObvContactGroups {
                let groupIdentifier = obvContactGroup.groupIdentifier
                guard let persistedContactGroup = try? PersistedContactGroup.getContactGroup(groupIdentifier: groupIdentifier, ownedIdentity: ownedIdentity) else { continue }
                do {
                    try persistedContactGroup.setContactIdentities(to: obvContactGroup.groupMembers)
                } catch let error {
                    os_log("Could not set the contacts of a contact group while bootstrapping: %{public}@", log: log, type: .fault, error.localizedDescription)
                }
                do {
                    try persistedContactGroup.setPendingMembers(to: obvContactGroup.pendingGroupMembers)
                } catch {
                    return cancel(withReason: .coreDataError(error: error))
                }
                persistedContactGroup.updatePhoto(with: obvContactGroup.trustedOrLatestPhotoURL)
                if let groupJoined = persistedContactGroup as? PersistedContactGroupJoined {
                    if obvContactGroup.publishedDetailsAndTrustedOrLatestDetailsAreEquivalentForTheUser() {
                        groupJoined.setStatus(to: .noNewPublishedDetails)
                    } else {
                        switch groupJoined.status {
                        case .noNewPublishedDetails:
                            groupJoined.setStatus(to: .unseenPublishedDetails)
                        case .unseenPublishedDetails, .seenPublishedDetails:
                            break // Don't change the status
                        }
                    }
                }
            }
            
            // Remove any persisted contact group that does not exist within the engine
            
            if let persistedGroups = try? PersistedContactGroup.getAllContactGroups(ownedIdentity: ownedIdentity, within: obvContext.context) {
                let uidsOfGroupsToKeep = existingObvContactGroups.map { $0.groupUid }
                let persistedGroupsToDelete = persistedGroups.filter { !uidsOfGroupsToKeep.contains($0.groupUid) }
                os_log("Number of contact groups existing within the app that must be deleted: %{public}d", log: log, type: .info, persistedGroupsToDelete.count)
                for group in persistedGroupsToDelete {
                    
                    let persistedGroupDiscussion = group.discussion
                    
                    do {
                        try persistedGroupDiscussion.setStatus(to: .locked)
                    } catch {
                        os_log("Could not lock the persisted group discussion", log: log, type: .error)
                        return
                    }
                    
                    do {
                        try group.delete()
                    } catch {
                        os_log("Could not delete one of the group present within the app but not within the engine: %{public}@", log: log, type: .fault, error.localizedDescription)
                        continue
                    }
                    
                }
            }
            
            // Make sure that all remaining persisted contact groups do have an associated display contact group.
            // For those that have one, make sure it is in sync.
            
            if let persistedGroups = try? PersistedContactGroup.getAllContactGroups(ownedIdentity: ownedIdentity, within: obvContext.context) {
                for group in persistedGroups {
                    guard !group.isDeleted else { continue }
                    do {
                        try group.createOrUpdateTheAssociatedDisplayedContactGroup()
                    } catch {
                        os_log("Could not create or update the underlying displayed contact group of a persisted contact group: %{public}@", log: log, type: .fault, error.localizedDescription)
                        assertionFailure() // In production, continue anyway
                    }
                }
            }
            
        } // End ownedIdentities.forEach
        
    }
    
}
