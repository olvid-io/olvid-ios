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
import CoreData
import os.log
import ObvAppCoreConstants

fileprivate let errorDomain = "MessengerMigrationV44ToV45"
fileprivate let debugPrintPrefix = "[\(errorDomain)][PersistedGroupDiscussionToPersistedGroupDiscussionV44ToV45]"


final class PersistedGroupDiscussionToPersistedGroupDiscussionV44ToV45: NSEntityMigrationPolicy {

    private func makeError(message: String) -> Error {
        let message = [debugPrintPrefix, message].joined(separator: " ")
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "PersistedGroupDiscussionToPersistedGroupDiscussionV44ToV45")
        
    
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {

        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(debugPrintPrefix) createDestinationInstances ends")
        }

        do {

            let entityName = "PersistedGroupDiscussion"
            let dInstance = try initializeDestinationInstance(forEntityName: entityName,
                                                              forSource: sInstance,
                                                              in: mapping,
                                                              manager: manager,
                                                              errorDomain: errorDomain)
            
            // The migration manager eventually needs to know the connection between the source object, the newly created destination object, and the mapping.
            
            manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)
            
        } catch {
            os_log("Failed to migrate a PersistedGroupDiscussion: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
            throw error
        }

    }
    
    
    override func createRelationships(forDestination dInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        // Recover the source PersistedGroupDiscussion
        
        let sInstances = manager.sourceInstances(forEntityMappingName: mapping.name, destinationInstances: [dInstance])
        guard sInstances.count == 1, let sInstance = sInstances.first else {
            throw makeError(message: "Failed to retrieve an appropriate PersistedGroupDiscussion source instance")
        }
        
        // Map the contactGroup relationship to its new name (rawContactGroup). Use the relationship to set the rawGroupUID and rawOwnerIdentityIdentity attributes.
        
        guard let sContactGroup = sInstance.value(forKey: "contactGroup") as? NSManagedObject else {
            assertionFailure("Although the contactGroup is optional, we expect it to be set. We cannot throw in production though.")
            return
        }
        
        let dContactGroups: [NSManagedObject]
        switch sContactGroup.entity.name {
        case "PersistedContactGroupJoined":
            dContactGroups = manager.destinationInstances(forEntityMappingName: "PersistedContactGroupJoinedToPersistedContactGroupJoined", sourceInstances: [sContactGroup])
        case "PersistedContactGroupOwned":
            dContactGroups = manager.destinationInstances(forEntityMappingName: "PersistedContactGroupOwnedToPersistedContactGroupOwned", sourceInstances: [sContactGroup])
        default:
            assertionFailure("Although this should not happen in practice, we cannot throw in production for this sole reason")
            return
        }
        
        guard dContactGroups.count == 1, let dContactGroup = dContactGroups.first else {
            assertionFailure("This should not happen in practice but we cannot throw in production for the sole reason")
            return
        }

        dInstance.setValue(dContactGroup, forKey: "rawContactGroup")
        
        if let groupUidRaw = dContactGroup.value(forKey: "groupUidRaw") as? Data, let ownerIdentity = dContactGroup.value(forKey: "ownerIdentity") as? Data {
            dInstance.setValue(groupUidRaw, forKey: "rawGroupUID")
            dInstance.setValue(ownerIdentity, forKey: "rawOwnerIdentityIdentity")
        } else {
            assertionFailure("In production, we do not throw if we cannot recover the contact group data")
        }
        
    }
    
}
