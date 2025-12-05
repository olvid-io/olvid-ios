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

fileprivate let errorDomain = "ObvEngineMigrationV8ToV9"
fileprivate let debugPrintPrefix = "[\(errorDomain)][ContactIdentityToContactIdentityDetailsTrustedMigrationPolicyV8ToV9]"


final class ContactIdentityToContactIdentityDetailsTrustedMigrationPolicyV8ToV9: NSEntityMigrationPolicy {
    
    // In v8, ContactIdentity has a displayName. Migrating to v9 implies to turn this displayName into an instance of ContactIdentityDetailsTrusted asssociated with the ContactIdentity.
    
    
    // MARK: - createDestinationInstances
    
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(debugPrintPrefix) createDestinationInstances ends")
        }
        
        // Create an instance of the destination object.
        let dContactIdentityDetailsTrusted: NSManagedObject
        do {
            let entityName = "ContactIdentityDetailsTrusted"
            guard let description = NSEntityDescription.entity(forEntityName: entityName, in: manager.destinationContext) else {
                let message = "Invalid entity name: \(entityName)"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            dContactIdentityDetailsTrusted = NSManagedObject(entity: description, insertInto: manager.destinationContext)
        }

        // Get the displayName from the source ContactIdentity instance
        guard let sDisplayName = sInstance.value(forKey: "displayName") as? String else {
            let message = "Could not get displayName"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        
        // Map this displayName onto CoreDetails
        let dObvIdentityCoreDetails = ObvIdentityCoreDetailsForMigrationV8ToV9(displayName: sDisplayName)
        guard let dSerializedIdentityCoreDetails = try? dObvIdentityCoreDetails.jsonEncode() else {
            let message = "Could not serialize ObvIdentityCoreDetailsForMigrationV8ToV9"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }

        // Populate the destination ContactIdentityDetailsTrusted instance

        dContactIdentityDetailsTrusted.setValue(nil, forKey: "photoURL")
        dContactIdentityDetailsTrusted.setValue(dSerializedIdentityCoreDetails, forKey: "serializedIdentityCoreDetails")

        // Associate the destination ContactIdentityDetailsTrusted instance with the source ContactIdentity instance
        
        manager.associate(sourceInstance: sInstance, withDestinationInstance: dContactIdentityDetailsTrusted, for: mapping)

    }
    
    
    // MARK: - createRelationships
    
    override func createRelationships(forDestination dInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(debugPrintPrefix) createRelationships starts")
        defer {
            debugPrint("\(debugPrintPrefix) createRelationships ends")
        }
        
        let dContactIdentityDetailsTrusted = dInstance

        // We get the destination ContactIdentity in the destination context
        let dContactIdentity: NSManagedObject
        do {
            let _sContactIdentity = manager.sourceInstances(forEntityMappingName: mapping.name, destinationInstances: [dContactIdentityDetailsTrusted])
            guard _sContactIdentity.count == 1 else {
                let message = "Failed to retrieve the ContactIdentity source"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            let sContactIdentity = _sContactIdentity.first!
            let _dContactIdentity = manager.destinationInstances(forEntityMappingName: "ContactIdentityToContactIdentity", sourceInstances: [sContactIdentity])
            guard _dContactIdentity.count == 1 else {
                let message = "Failed to retrieve the ContactIdentity destination"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            dContactIdentity = _dContactIdentity.first!
        }

        // Associate the destination ContactIdentity with the destination ContactIdentityDetailsTrusted
        
        dContactIdentityDetailsTrusted.setValue(dContactIdentity, forKey: "contactIdentity")

        
    }
}
