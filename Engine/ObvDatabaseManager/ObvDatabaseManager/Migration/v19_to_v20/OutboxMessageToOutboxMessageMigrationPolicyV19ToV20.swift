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
import ObvTypes

fileprivate let errorDomain = "ObvEngineMigrationV19ToV20"
fileprivate let debugPrintPrefix = "[\(errorDomain)][OutboxMessageToOutboxMessageMigrationPolicyV19ToV20]"

final class OutboxMessageToOutboxMessageMigrationPolicyV19ToV20: NSEntityMigrationPolicy {

    
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(debugPrintPrefix) createDestinationInstances ends")
        }
        
        let dInstance = try initializeDestinationInstance(forEntityName: "OutboxMessage",
                                                          forSource: sInstance,
                                                          in: mapping,
                                                          manager: manager,
                                                          errorDomain: errorDomain)
        
        // If the dInstance has no messageIdFromServer then there is nothing to do.
        // Otherwise, it now requires a timestampFromServer. For this migration, we simply set this value to the current date
        
        guard let messageIdFromServer = dInstance.value(forKey: "messageIdFromServer") as? UID? else {
            let message = "Could not get the messageIdFromServer value"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        
        if messageIdFromServer != nil {
            dInstance.setValue(Date(), forKey: "timestampFromServer")
        }
        
        // The migration manager needs to know the connection between the source object, the newly created destination object, and the mapping.
        
        manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)

    }
    
}
