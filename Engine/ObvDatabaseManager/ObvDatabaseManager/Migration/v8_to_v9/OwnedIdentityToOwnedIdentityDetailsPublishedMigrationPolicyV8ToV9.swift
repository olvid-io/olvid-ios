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
fileprivate let debugPrintPrefix = "[\(errorDomain)][OwnedIdentityToOwnedIdentityDetailsPublishedMigrationPolicyV8ToV9]"


final class OwnedIdentityToOwnedIdentityDetailsPublishedMigrationPolicyV8ToV9: NSEntityMigrationPolicy {
    
    // In v8, OwnedIdentity has a displayName. Migrating to v9 implies to turn this displayName into an instance of OwnedIdentityDetailsPublished asssociated with the OwnedIdentity.
    
    
    // MARK: - createDestinationInstances
    
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(debugPrintPrefix) createDestinationInstances ends")
        }
        
        // Create an instance of the destination object.
        let dOwnedIdentityDetailsPublished: NSManagedObject
        do {
            let entityName = "OwnedIdentityDetailsPublished"
            guard let description = NSEntityDescription.entity(forEntityName: entityName, in: manager.destinationContext) else {
                let message = "Invalid entity name: \(entityName)"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            dOwnedIdentityDetailsPublished = NSManagedObject(entity: description, insertInto: manager.destinationContext)
        }

        // Get the displayName from the source OwnedIdentity instance
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

        // Populate the destination OwnedIdentityDetailsPublished instance
        dOwnedIdentityDetailsPublished.setValue(nil, forKey: "photoURL")
        dOwnedIdentityDetailsPublished.setValue(dSerializedIdentityCoreDetails, forKey: "serializedIdentityCoreDetails")
        dOwnedIdentityDetailsPublished.setValue(nil, forKey: "photoServerKeyEncoded")
        dOwnedIdentityDetailsPublished.setValue(nil, forKey: "photoServerLabel")
        dOwnedIdentityDetailsPublished.setValue(nil, forKey: "publicationDate")
        dOwnedIdentityDetailsPublished.setValue(0, forKey: "version")
        
        // Associate the destination OwnedIdentityDetailsPublished instance with the source OwnedIdentity instance
        
        manager.associate(sourceInstance: sInstance, withDestinationInstance: dOwnedIdentityDetailsPublished, for: mapping)

    }
    
    
    // MARK: - createRelationships
    
    override func createRelationships(forDestination dInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(debugPrintPrefix) createRelationships starts")
        defer {
            debugPrint("\(debugPrintPrefix) createRelationships ends")
        }
        
        let dOwnedIdentityDetailsPublished = dInstance

        // We get the destination OwnedIdentity in the destination context
        let dOwnedIdentity: NSManagedObject
        do {
            let _sOwnedIdentity = manager.sourceInstances(forEntityMappingName: mapping.name, destinationInstances: [dOwnedIdentityDetailsPublished])
            guard _sOwnedIdentity.count == 1 else {
                let message = "Failed to retrieve the OwnedIdentity source"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            let sOwnedIdentity = _sOwnedIdentity.first!
            let _dOwnedIdentity = manager.destinationInstances(forEntityMappingName: "OwnedIdentityToOwnedIdentity", sourceInstances: [sOwnedIdentity])
            guard _dOwnedIdentity.count == 1 else {
                let message = "Failed to retrieve the OwnedIdentity destination"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            dOwnedIdentity = _dOwnedIdentity.first!
        }
        
        // Associate the destination OwnedIdentity with the destination OwnedIdentityDetailsPublished
        
        dOwnedIdentityDetailsPublished.setValue(dOwnedIdentity, forKey: "ownedIdentity")
        
    }
}
