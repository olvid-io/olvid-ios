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

fileprivate let errorDomain = "MessengerMigrationV14ToV15"
fileprivate let debugPrintPrefix = "[\(errorDomain)][PersistedMessageSentToPersistedMessageSentMigrationPolicyV14ToV15]"


final class PersistedMessageSentToPersistedMessageSentMigrationPolicyV14ToV15: NSEntityMigrationPolicy {
    
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(debugPrintPrefix) createDestinationInstances ends")
        }
        
        let entityName = "PersistedMessageSent"
        let dInstance = try initializeDestinationInstance(forEntityName: entityName,
                                                          forSource: sInstance,
                                                          in: mapping,
                                                          manager: manager,
                                                          errorDomain: errorDomain)

        // Get the `replyTo` relationship, if it exists
        
        if let replyToAsAny = sInstance.value(forKey: "replyTo") {
            // Create the replyToJSON and set the appropriate value on the destination object
            let replyToJSON = try MigrationUtilsV14ToV15.mapReplyToToReplyToJSON(replyToAsAny: replyToAsAny, errorDomain: errorDomain)
            let encoder = JSONEncoder()
            let rawReplyToJSON = try encoder.encode(replyToJSON)
            dInstance.setValue(rawReplyToJSON, forKey: "rawReplyToJSON")
        }
        
        // The migration manager needs to know the connection between the source object, the newly created destination object, and the mapping.
        
        manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)

    }
    
}
