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

fileprivate let errorDomain = "MessengerMigrationV9ToV10"
fileprivate let debugPrintPrefix = "[\(errorDomain)][PersistedMessageReceivedToPersistedMessageReceivedMigrationPolicyV9ToV10]"


final class PersistedMessageReceivedToPersistedMessageReceivedMigrationPolicyV9ToV10: NSEntityMigrationPolicy {
    
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(debugPrintPrefix) createDestinationInstances ends")
        }
        
        let entityName = "PersistedMessageReceived"
        let dPersistedMessageReceived = try initializeDestinationInstance(forEntityName: entityName,
                                                                          forSource: sInstance,
                                                                          in: mapping,
                                                                          manager: manager,
                                                                          errorDomain: errorDomain)
        
        // We compute the new sectionIdentifier attribute using the current timeStamp
        
        guard let sTimeStamp = sInstance.value(forKey: "timestamp") as? Date else {
            let message = "Could not get timestamp"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        let dSectionIdentifier = MigrationUtilsV9ToV10.computeSectionIdentifier(fromTimestamp: sTimeStamp)
        dPersistedMessageReceived.setValue(dSectionIdentifier, forKey: "sectionIdentifier")
        
        // The migration manager needs to know the connection between the source object, the newly created destination object, and the mapping.
        
        manager.associate(sourceInstance: sInstance, withDestinationInstance: dPersistedMessageReceived, for: mapping)

    }
    
    
}
