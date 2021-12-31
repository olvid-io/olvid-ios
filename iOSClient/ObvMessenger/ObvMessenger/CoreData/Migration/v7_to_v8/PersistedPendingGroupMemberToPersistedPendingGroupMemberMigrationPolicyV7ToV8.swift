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

fileprivate let errorDomain = "MessengerMigrationV7ToV8"
fileprivate let debugPrintPrefix = "[\(errorDomain)][PersistedPendingGroupMemberToPersistedPendingGroupMemberMigrationPolicyV7ToV8]"


final class PersistedPendingGroupMemberToPersistedPendingGroupMemberMigrationPolicyV7ToV8: NSEntityMigrationPolicy {
    
    
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(debugPrintPrefix) createDestinationInstances ends")
        }
        
        // Create an instance of the destination object.
        let dPersistedPendingGroupMember: NSManagedObject
        do {
            let entityName = "PersistedPendingGroupMember"
            guard let description = NSEntityDescription.entity(forEntityName: entityName, in: manager.destinationContext) else {
                let message = "Invalid entity name: \(entityName)"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            dPersistedPendingGroupMember = NSManagedObject(entity: description, insertInto: manager.destinationContext)
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
                dPersistedPendingGroupMember.setValue(destinationValue, forKey: destinationName)
            }
        }
        
        // We map the displayName that existed to a (serialized) ObvIdentityCoreDetails and to a fullDisplayName
        
        guard let sDisplayName = sInstance.value(forKey: "displayName") as? String else {
            let message = "Could not get displayName"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        let dObvIdentityCoreDetails = ObvIdentityCoreDetailsForMigrationV7ToV8(displayName: sDisplayName)
        guard let dSerializedIdentityCoreDetails = try? dObvIdentityCoreDetails.encode() else {
            let message = "Could not serialize ObvIdentityCoreDetailsForMigrationV8ToV9"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        dPersistedPendingGroupMember.setValue(dSerializedIdentityCoreDetails, forKey: "serializedIdentityCoreDetails")
        dPersistedPendingGroupMember.setValue(dObvIdentityCoreDetails.getDisplayNameWithStyle(ObvDisplayNameStyleForMigrationV7ToV8.full), forKey: "fullDisplayName")
        
        // The migration manager needs to know the connection between the source object, the newly created destination object, and the mapping.
        
        manager.associate(sourceInstance: sInstance, withDestinationInstance: dPersistedPendingGroupMember, for: mapping)

    }

}
