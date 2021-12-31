/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import ObvTypes
import ObvCrypto

fileprivate let errorDomain = "MessengerMigrationV12ToV13"
fileprivate let debugPrintPrefix = "[\(errorDomain)][PersistedObvContactIdentityToPersistedObvContactIdentityMigrationPolicyV12ToV13]"


final class PersistedObvContactIdentityToPersistedObvContactIdentityMigrationPolicyV12ToV13: NSEntityMigrationPolicy {
    
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {

        debugPrint("\(debugPrintPrefix) performCustomValidation starts")
        defer {
            debugPrint("\(debugPrintPrefix) performCustomValidation ends")
        }
        
        let entityName = "PersistedObvContactIdentity"
        let dInstance = try initializeDestinationInstance(forEntityName: entityName,
                                                          forSource: sInstance,
                                                          in: mapping,
                                                          manager: manager,
                                                          errorDomain: errorDomain)

        // Turn the newPublishedDetails Boolean into a rawStatus
        
        guard let newPublishedDetails = sInstance.value(forKey: "newPublishedDetails") as? Bool else {
            let message = "Could not get newPublishedDetails Boolean"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }

        let rawStatus = newPublishedDetails ? 1 : 0
        
        dInstance.setValue(rawStatus, forKey: "rawStatus")
        
        // The migration manager needs to know the connection between the source object, the newly created destination object, and the mapping.
        
        manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)

    }
    
}
