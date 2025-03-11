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
import OlvidUtils


final class OutboxMessageToOutboxMessageMigrationPolicyV41ToV42: NSEntityMigrationPolicy, ObvErrorMaker {
    
    static let errorDomain = "ObvEngineMigrationV41ToV42"
    static let debugPrintPrefix = "[\(errorDomain)][OutboxMessageToOutboxMessageMigrationPolicyV41ToV42]"

    // Tested
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(Self.debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(Self.debugPrintPrefix) createDestinationInstances ends")
        }
        
        let dInstance = try initializeDestinationInstance(forEntityName: "OutboxMessage",
                                                          forSource: sInstance,
                                                          in: mapping,
                                                          manager: manager,
                                                          errorDomain: Self.errorDomain)
        defer {
            manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)
        }

        // We only need to set creationDate to the current date
        
        dInstance.setValue(Date(), forKey: "creationDate")
                
    }
    
}
