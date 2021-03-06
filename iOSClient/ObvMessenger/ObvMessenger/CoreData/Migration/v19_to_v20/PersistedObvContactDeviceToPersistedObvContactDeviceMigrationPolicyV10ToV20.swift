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
fileprivate let debugPrintPrefix = "[\(errorDomain)][PersistedObvContactDeviceToPersistedObvContactDeviceMigrationPolicyV10ToV20]"


final class PersistedObvContactDeviceToPersistedObvContactDeviceMigrationPolicyV10ToV20: NSEntityMigrationPolicy {
    
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
        
        let entityName = "PersistedObvContactDevice"
        let dInstance = try initializeDestinationInstance(forEntityName: entityName,
                                                          forSource: sInstance,
                                                          in: mapping,
                                                          manager: manager,
                                                          errorDomain: errorDomain)
        
        // Note:
        // This migration identity (PersistedObvContactIdentity) --> rawIdentity (PersistedObvContactIdentity) was set in the mapping model

        // Get the (only) owned identity and use it to set 
        
        let rawOwnedIdentity = try UtilsForAppMigrationV19ToV20.shared.findOwnedIdentityRawIdentityInSourceContext(manager: manager)
        dInstance.setValue(rawOwnedIdentity, forKey: "rawIdentityIdentity")
        
        // The migration manager needs to know the connection between the source object, the newly created destination object, and the mapping.
        
        manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)

    }
    
}
