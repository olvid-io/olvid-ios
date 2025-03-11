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

fileprivate let errorDomain = "MessengerMigrationV54ToV55"
fileprivate let debugPrintPrefix = "[\(errorDomain)][PersistedDiscussionSharedConfigurationToPersistedDiscussionSharedConfigurationV54ToV55]"


final class PersistedDiscussionSharedConfigurationToPersistedDiscussionSharedConfigurationV54ToV55: NSEntityMigrationPolicy {

    let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "PersistedDiscussionSharedConfigurationToPersistedDiscussionSharedConfigurationV54ToV55")
            
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {

        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(debugPrintPrefix) createDestinationInstances ends")
        }

        do {
            let entityName = "PersistedDiscussionSharedConfiguration"
            let dInstance = try initializeDestinationInstance(forEntityName: entityName,
                                                              forSource: sInstance,
                                                              in: mapping,
                                                              manager: manager,
                                                              errorDomain: errorDomain)
            
            // The migration manager eventually needs to know the connection between the source object, the newly created destination object, and the mapping.
            
            manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)
        
            // The only attribute that is not specified in the mapping model is `readOnce`. If this value is set in the source, we map it as is. If it is nil (unlikely, but still), but map is as `false`.
            
            if let readOnce = sInstance.value(forKey: "readOnce") as? Bool {
                dInstance.setValue(readOnce, forKey: "readOnce")
            } else {
                dInstance.setValue(false, forKey: "readOnce")
            }

        } catch {
            os_log("Failed to migrate a PersistedDiscussionSharedConfiguration: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
            throw error
        }
        
    }
    
}
