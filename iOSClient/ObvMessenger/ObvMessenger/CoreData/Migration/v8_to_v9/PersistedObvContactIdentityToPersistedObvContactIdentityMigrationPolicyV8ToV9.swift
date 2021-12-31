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

fileprivate let errorDomain = "MessengerMigrationV8ToV9"
fileprivate let debugPrintPrefix = "[\(errorDomain)][PersistedObvContactIdentityToPersistedObvContactIdentityMigrationPolicyV8ToV9]"


final class PersistedObvContactIdentityToPersistedObvContactIdentityMigrationPolicyV8ToV9: NSEntityMigrationPolicy {
    
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(debugPrintPrefix) createDestinationInstances ends")
        }
        
        // Create an instance of the destination object.
        let dPersistedObvContactIdentity: NSManagedObject
        do {
            let entityName = "PersistedObvContactIdentity"
            guard let description = NSEntityDescription.entity(forEntityName: entityName, in: manager.destinationContext) else {
                let message = "Invalid entity name: \(entityName)"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            dPersistedObvContactIdentity = NSManagedObject(entity: description, insertInto: manager.destinationContext)
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
                dPersistedObvContactIdentity.setValue(destinationValue, forKey: destinationName)
            }
        }

        // We set the customDisplayName to nil and the sortDisplayName to the full display name of the contact
        
        guard let sSerializedIdentityCoreDetails = sInstance.value(forKey: "serializedIdentityCoreDetails") as? Data else {
            let message = "Could not get serialized core details"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        guard let identityCoreDetails = try? ObvIdentityCoreDetailsForMigrationV8ToV9(sSerializedIdentityCoreDetails) else {
            let message = "Could not de-serialize core details"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        let sortDisplayName = identityCoreDetails.getDisplayNameWithStyle(.full)
        dPersistedObvContactIdentity.setValue(sortDisplayName, forKey: "sortDisplayName")
        dPersistedObvContactIdentity.setValue(nil, forKey: "customDisplayName")

        // The migration manager needs to know the connection between the source object, the newly created destination object, and the mapping.
        
        manager.associate(sourceInstance: sInstance, withDestinationInstance: dPersistedObvContactIdentity, for: mapping)
        
    }

    
}
