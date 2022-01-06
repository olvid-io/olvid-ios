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

import CoreData
import ObvTypes
import ObvCrypto

fileprivate let errorDomain = "MessengerMigrationV10ToV11"
fileprivate let debugPrintPrefix = "[\(errorDomain)][PersistedContactGroupOwnedToPersistedContactGroupOwnedMigrationPolicyV10ToV11]"


final class PersistedContactGroupOwnedToPersistedContactGroupOwnedMigrationPolicyV10ToV11: NSEntityMigrationPolicy {
    
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(debugPrintPrefix) createDestinationInstances ends")
        }
        
        let entityName = "PersistedContactGroupOwned"
        let dInstance = try initializeDestinationInstance(forEntityName: entityName,
                                                          forSource: sInstance,
                                                          in: mapping,
                                                          manager: manager,
                                                          errorDomain: errorDomain)

        // We need to set the groupUidRaw and the ownerIdentity
        
        guard let owner = sInstance.value(forKey: "owner") as? NSObject else {
            let message = "Could not get group owner"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        guard let ownerIdentity = owner.value(forKey: "identity") as? Data else {
            let message = "Could not get group owner identity"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        dInstance.setValue(ownerIdentity, forKey: "ownerIdentity")
        
        guard let groupId = sInstance.value(forKey: "groupId") as? Data else {
            let message = "Could not get group id"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        let groupUidRaw = groupId.subdata(in: groupId.count-32..<groupId.count)
        guard groupUidRaw.count == 32 else {
            let message = "Wrong data count"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        guard let groupUid = UID(uid: groupUidRaw) else {
            let message = "Could not get group seed"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        dInstance.setValue(groupUid.raw, forKey: "groupUidRaw")

        // The migration manager needs to know the connection between the source object, the newly created destination object, and the mapping.
        
        manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)

    }

}
