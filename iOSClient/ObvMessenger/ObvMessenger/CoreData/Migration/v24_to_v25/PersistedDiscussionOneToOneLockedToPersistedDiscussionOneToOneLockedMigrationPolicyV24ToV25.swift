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

fileprivate let errorDomain = "MessengerMigrationV24ToV25"
fileprivate let debugPrintPrefix = "[\(errorDomain)][PersistedDiscussionOneToOneLockedToPersistedDiscussionOneToOneLockedMigrationPolicyV24ToV25]"


// Tested
final class PersistedDiscussionOneToOneLockedToPersistedDiscussionOneToOneLockedMigrationPolicyV24ToV25: NSEntityMigrationPolicy {
    
    private func makeError(message: String) -> Error {
        let message = [debugPrintPrefix, message].joined(separator: " ")
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(debugPrintPrefix) createDestinationInstances ends")
        }
        
        let entityName = "PersistedDiscussionOneToOneLocked"
        let dInstance = try initializeDestinationInstance(forEntityName: entityName,
                                                          forSource: sInstance,
                                                          in: mapping,
                                                          manager: manager,
                                                          errorDomain: errorDomain)

        // Everything was handled on the mapping model, except the two new relationship:
        //    @NSManaged private(set) var sharedConfiguration: PersistedDiscussionSharedConfiguration
        //    @NSManaged private(set) var localConfiguration: PersistedDiscussionLocalConfiguration
        
        try UtilsForAppMigrationV24ToV25.createDefaultPersistedDiscussionSharedConfiguration(forDiscussion: dInstance, destinationContext: manager.destinationContext)
        
        try UtilsForAppMigrationV24ToV25.createDefaultPersistedDiscussionLocalConfiguration(forDiscussion: dInstance, destinationContext: manager.destinationContext, sDiscussionURL: sInstance.objectID.uriRepresentation())

        // The migration manager needs to know the connection between the source object, the newly created destination object, and the mapping.
        
        manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)

    }
    
}
