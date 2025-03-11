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

fileprivate let errorDomain = "MessengerMigrationV55ToV56"
fileprivate let debugPrintPrefix = "[\(errorDomain)][PersistedDraftToPersistedDraftV55ToV56]"

// Ok
final class PersistedDraftToPersistedDraftV55ToV56: NSEntityMigrationPolicy {

    let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "PersistedDraftToPersistedDraftV55ToV56")
            
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {

        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer { debugPrint("\(debugPrintPrefix) createDestinationInstances ends") }

        do {
            let entityName = "PersistedDraft"
            let dInstance = try initializeDestinationInstance(forEntityName: entityName,
                                                              forSource: sInstance,
                                                              in: mapping,
                                                              manager: manager,
                                                              errorDomain: errorDomain)
            
            // The migration manager eventually needs to know the connection between the source object, the newly created destination object, and the mapping.
            
            manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)
        
            // The only attribute that is not specified in the mapping model is `permanentUUID`. We choose one at random.
            
            dInstance.setValue(UUID(), forKey: "permanentUUID")
            
        } catch {
            os_log("Failed to migrate an instance: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
            throw error
        }
        
    }
    
}
