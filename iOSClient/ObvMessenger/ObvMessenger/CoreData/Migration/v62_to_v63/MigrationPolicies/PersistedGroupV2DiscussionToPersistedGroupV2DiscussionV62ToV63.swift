/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import OlvidUtils


final class PersistedGroupV2DiscussionToPersistedGroupV2DiscussionV62ToV63: NSEntityMigrationPolicy, ObvErrorMaker {
    
    static let errorDomain = "MessengerMigrationV62ToV63"
    static let debugPrintPrefix = "[\(errorDomain)][PersistedGroupV2DiscussionToPersistedGroupV2DiscussionV62ToV63]"

    override func end(_ mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        // This method is called once for this entity, after all relationships of all entities have been re-created.

        debugPrint("\(Self.debugPrintPrefix) end(_ mapping: NSEntityMapping, manager: NSMigrationManager) starts")
        defer {
            debugPrint("\(Self.debugPrintPrefix) end(_ mapping: NSEntityMapping, manager: NSMigrationManager) ends")
        }
        
        let entityName = "PersistedGroupV2Discussion"

        let discussions = manager.destinationContext.registeredObjects.filter { $0.entity.name == entityName }
        
        for discussion in discussions {
            
            guard let messages = discussion.value(forKey: "messages") as? Set<NSManagedObject> else {
                assertionFailure("Could not get messages from \(entityName)")
                throw Self.makeError(message: "Could not get messages from \(entityName)")
            }
            
            discussion.setValue(messages.isEmpty, forKey: "isArchived")
            
        }
                
    }
    
}
