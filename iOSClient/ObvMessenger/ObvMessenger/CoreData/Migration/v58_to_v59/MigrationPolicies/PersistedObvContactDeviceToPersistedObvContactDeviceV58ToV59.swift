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

fileprivate let errorDomain = "MessengerMigrationV58ToV59"
fileprivate let debugPrintPrefix = "[\(errorDomain)][PersistedObvContactDeviceToPersistedObvContactDeviceV58ToV59]"

// Ok
final class PersistedObvContactDeviceToPersistedObvContactDeviceV58ToV59: NSEntityMigrationPolicy {

    let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "PersistedObvContactDeviceToPersistedObvContactDeviceV58ToV59")
            
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {

        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer { debugPrint("\(debugPrintPrefix) createDestinationInstances ends") }

        do {
            let entityName = "PersistedObvContactDevice"
            let dInstance = try initializeDestinationInstance(forEntityName: entityName,
                                                              forSource: sInstance,
                                                              in: mapping,
                                                              manager: manager,
                                                              errorDomain: errorDomain)

            // Look for the owned identity so as to set the rawOwnedIdentityIdentity attribute

            guard let persistedObvContactIdentity = sInstance.value(forKey: "rawIdentity") as? NSManagedObject else {
                assertionFailure()
                // Discard this device
                return
            }
            
            guard let rawOwnedIdentityIdentity = persistedObvContactIdentity.value(forKey: "rawOwnedIdentityIdentity") as? Data else {
                assertionFailure()
                // Discard this device
                return
            }

            dInstance.setValue(rawOwnedIdentityIdentity, forKey: "rawOwnedIdentityIdentity")
            
            // The migration manager eventually needs to know the connection between the source object, the newly created destination object, and the mapping.
            
            manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)
            
        } catch {
            os_log("Failed to migrate an instance: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
            throw error
        }
        
    }
    
}