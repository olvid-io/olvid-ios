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

fileprivate let errorDomain = "MessengerMigrationV6ToV7"
fileprivate let debugPrintPrefix = "[\(errorDomain)][PersistedOneToOneDiscussionToPersistedOneToOneDiscussionMigrationPolicyV6ToV7]"

final class PersistedOneToOneDiscussionToPersistedOneToOneDiscussionMigrationPolicyV6ToV7: NSEntityMigrationPolicy {

    
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {

        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(debugPrintPrefix) createDestinationInstances ends")
        }

        // Create an instance of the destination object.
        let newPersistedOneToOneDiscussion: PersistedOneToOneDiscussion
        do {
            let entityName = "PersistedOneToOneDiscussion"
            guard let description = NSEntityDescription.entity(forEntityName: entityName, in: manager.destinationContext) else {
                let message = "Invalid entity name: \(entityName)"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            newPersistedOneToOneDiscussion = PersistedOneToOneDiscussion(entity: description, insertInto: manager.destinationContext)
        }
        
        // Create a method that performs the task of iterating over the property mappings if they are present in the migration. This method only controls the traversal while the next block of code will perform the operation required for each property mapping.
        func traversePropertyMappings(block: (NSPropertyMapping, String) -> Void) throws {
            guard let attributeMappings = mapping.attributeMappings else {
                let message = "No Attribute Mappings found!"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            for propertyMapping in attributeMappings {
                guard let destinationName = propertyMapping.name else {
                    let message = "Attribute destination not configured properly"
                    let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                    throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
                }
                block(propertyMapping, destinationName)
            }
        }

        // Most of the attributes migrations should be performed using the expressions defined in the mapping model. We use the previous traversal function and apply the value expression to the source instance and set the result to the new destination object.
        try traversePropertyMappings { (propertyMapping, destinationName) in
            if let valueExpression = propertyMapping.valueExpression {
                let context: NSMutableDictionary = ["source": sInstance]
                guard let destinationValue = valueExpression.expressionValue(with: sInstance, context: context) else {
                    return
                }
                newPersistedOneToOneDiscussion.setValue(destinationValue, forKey: destinationName)
            }
        }

        // For each PersistedOneToOneDiscussion we want to create a new PersistedDraft (we discard the previous Draft within this migration)
        
        do {
            let entityName = "PersistedDraft"
            guard let description = NSEntityDescription.entity(forEntityName: entityName, in: manager.destinationContext) else {
                let message = "Invalid entity name: \(entityName)"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            let persistedDraft = PersistedDraft(entity: description, insertInto: manager.destinationContext)
            persistedDraft.setValue("", forKey: "body")
            persistedDraft.setValue(false, forKey: "sendRequested")
            persistedDraft.setValue(newPersistedOneToOneDiscussion, forKey: "discussion")
        }
        
        // The migration manager needs to know the connection between the source object, the newly created destination object, and the mapping.
        
        manager.associate(sourceInstance: sInstance, withDestinationInstance: newPersistedOneToOneDiscussion, for: mapping)

    }
    
}
