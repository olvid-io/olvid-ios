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

public extension NSEntityMigrationPolicy {
    
    func initializeDestinationInstance(forEntityName entityName: String, forSource sInstance: NSManagedObject, in mapping: NSEntityMapping?, manager: NSMigrationManager, errorDomain: String) throws -> NSManagedObject {
        
        // Create an instance of the destination object.
        let dObject: NSManagedObject
        do {
            guard let description = NSEntityDescription.entity(forEntityName: entityName, in: manager.destinationContext) else {
                let message = "Invalid entity name: \(entityName)"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            dObject = NSManagedObject(entity: description, insertInto: manager.destinationContext)
        }
        
        // Create a method that performs the task of iterating over the property mappings if they are present in the migration. This method only controls the traversal while the next block of code will perform the operation required for each property mapping.
        func traversePropertyMappings(block: (NSPropertyMapping, String) -> Void) throws {
            guard let mapping = mapping else { return }
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
                dObject.setValue(destinationValue, forKey: destinationName)
            }
        }
        
        return dObject
    }
    
}
