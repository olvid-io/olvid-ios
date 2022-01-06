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

fileprivate let errorDomain = "MessengerMigrationV19ToV20"
fileprivate let debugPrintPrefix = "[\(errorDomain)][PersistedPendingGroupMemberToPersistedPendingGroupMemberMigrationPolicyV19ToV20]"


final class PersistedPendingGroupMemberToPersistedPendingGroupMemberMigrationPolicyV19ToV20: NSEntityMigrationPolicy {
    
    private func makeError(message: String) -> Error {
        let message = [debugPrintPrefix, message].joined(separator: " ")
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    
    override func begin(_ mapping: NSEntityMapping, with manager: NSMigrationManager) throws {
        try UtilsForAppMigrationV19ToV20.shared.enforceV20ConstraintsOnV19(manager: manager)
    }

    
    // Tested
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(debugPrintPrefix) createDestinationInstances ends")
        }
        
        let entityName = "PersistedPendingGroupMember"
        let dInstance = try initializeDestinationInstance(forEntityName: entityName,
                                                          forSource: sInstance,
                                                          in: mapping,
                                                          manager: manager,
                                                          errorDomain: errorDomain)
        
        // Note:
        // The migration from contactGroup --> rawContactGroup was set in the mapping model
    
        // We first get the contactGroup (PersistedContactGroup) from the source context
        
        guard let sPersistedContactGroupObject = sInstance.value(forKey: "contactGroup") as? NSManagedObject else {
            throw makeError(message: "Could not get the source PersistedContactGroup object")
        }
        
        // Use the group to get the group owner and the group uid
        
        guard let groupUidRaw = sPersistedContactGroupObject.value(forKey: "groupUidRaw") as? Data else {
            throw makeError(message: "Could not get the group uid")
        }
        
        guard let groupOwnerIdentity = sPersistedContactGroupObject.value(forKey: "ownerIdentity") as? Data else {
            throw makeError(message: "Could not get the group owner identity")
        }
        
        // Use the two previous values to set the variables rawGroupUidRaw and rawGroupOwnerIdentity
        
        dInstance.setValue(groupUidRaw, forKey: "rawGroupUidRaw")
        dInstance.setValue(groupOwnerIdentity, forKey: "rawGroupOwnerIdentity")

        // Get owned identity associated to the contact group and get its raw identity
        
        guard let sPersistedObvOwnedIdentityObject = sPersistedContactGroupObject.value(forKey: "ownedIdentity") as? NSManagedObject else {
            throw makeError(message: "Could not get the owned identity associated to the sPersistedContactGroupObject")
        }
        
        guard let rawOwnedIdentityIdentity = sPersistedObvOwnedIdentityObject.value(forKey: "identity") as? Data else {
            throw makeError(message: "Could not get the owned identity identity")
        }
        
        // Set the raw owned identity
        
        dInstance.setValue(rawOwnedIdentityIdentity, forKey: "rawOwnedIdentityIdentity")

        // The migration manager needs to know the connection between the source object, the newly created destination object, and the mapping.
        
        manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)

    }
    
}
