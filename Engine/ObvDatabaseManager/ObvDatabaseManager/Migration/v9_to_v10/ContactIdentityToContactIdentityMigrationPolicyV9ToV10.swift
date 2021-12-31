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
import ObvEncoder

fileprivate let errorDomain = "ObvEngineMigrationV9ToV10"
fileprivate let debugPrintPrefix = "[\(errorDomain)][ContactIdentityToContactIdentityMigrationPolicyV9ToV10]"


final class ContactIdentityToContactIdentityMigrationPolicyV9ToV10: NSEntityMigrationPolicy {
    
    
    // Within `createDestinationInstances`, we only compute and associate the contact identity TrustLevel. The PersistedTrustLevel instances are created within `createRelationships`.

    
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(debugPrintPrefix) createDestinationInstances ends")
        }
        
        let entityName = "ContactIdentity"
        let dContactIdentity = try initializeDestinationInstance(forEntityName: entityName,
                                                                 forSource: sInstance,
                                                                 in: mapping,
                                                                 manager: manager,
                                                                 errorDomain: errorDomain)
        
        // We get the (old) TrustOrigins and use them to compute the TrustLevel of this contact. We do not use these TrustOrigins to populate the PersistedTrustOrigin table: We do this in another subclass of NSEntityMigrationPolicy
        
        guard let sRawTrustOrigins = sInstance.value(forKey: "trustOrigins") as? Data else {
            let message = "Could not get serialized trust origins"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        guard let sEncodedTrustOrigins = ObvEncoded(withRawData: sRawTrustOrigins) else {
            let message = "Could not decode de serialized trust origins"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        guard let sTrustOriginsAsArrayOfEncoded = [ObvEncoded](sEncodedTrustOrigins) else {
            let message = "Could not decode de serialized trust origins as an array of encoded elements"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        let sTrustOrigins = sTrustOriginsAsArrayOfEncoded.compactMap { TrustOriginForMigrationV9ToV10($0) }
        guard sTrustOrigins.count == sTrustOriginsAsArrayOfEncoded.count else {
            let message = "Could not decode all the trust origins"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        // Compute the trust level of the contact identity
        var dContactIdentityTrustLevel = TrustLevelForMigrationV9ToV10.forGroupOrIntroduction(withMinor: 4) // The least we may have at this point
        for trustOrigin in sTrustOrigins {
            let trustLevel: TrustLevelForMigrationV9ToV10
            switch trustOrigin {
            case .direct:
                trustLevel = .forDirect()
            case .group,
                 .introduction:
                trustLevel = .forGroupOrIntroduction(withMinor: 4) // Within this migration, we do not bother...
            }
            if dContactIdentityTrustLevel < trustLevel {
               dContactIdentityTrustLevel = trustLevel
            }
        }
        // Set the trust level of the contact identity object
        dContactIdentity.setValue(dContactIdentityTrustLevel.rawValue, forKey: "trustLevelRaw")
        
        // The migration manager needs to know the connection between the source object, the newly created destination object, and the mapping.
        
        manager.associate(sourceInstance: sInstance, withDestinationInstance: dContactIdentity, for: mapping)

    }
    
    
    
    
    override func createRelationships(forDestination dInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(debugPrintPrefix) createRelationships starts")
        defer {
            debugPrint("\(debugPrintPrefix) createRelationships ends")
        }

        // We get both the source and destination contact identity
        
        let dContactIdentity = dInstance
        let sContactIdentity: NSManagedObject
        do {
            let sInstances = manager.sourceInstances(forEntityMappingName: mapping.name, destinationInstances: [dContactIdentity])
            guard sInstances.count == 1 else {
                let message = "Could not recover source contact identity"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            sContactIdentity = sInstances.first!
        }

        // Recover and decode the trust origins from the source contact identity
        
        let sTrustOrigins: [TrustOriginForMigrationV9ToV10]
        do {
            guard let sRawTrustOrigins = sContactIdentity.value(forKey: "trustOrigins") as? Data else {
                let message = "Could not get serialized trust origins"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            guard let sEncodedTrustOrigins = ObvEncoded(withRawData: sRawTrustOrigins) else {
                let message = "Could not decode de serialized trust origins"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            guard let sTrustOriginsAsArrayOfEncoded = [ObvEncoded](sEncodedTrustOrigins) else {
                let message = "Could not decode de serialized trust origins as an array of encoded elements"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            let _sTrustOrigins = sTrustOriginsAsArrayOfEncoded.compactMap { TrustOriginForMigrationV9ToV10($0) }
            guard _sTrustOrigins.count == sTrustOriginsAsArrayOfEncoded.count else {
                let message = "Could not decode all the trust origins"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            sTrustOrigins = _sTrustOrigins
        }

        guard !sTrustOrigins.isEmpty else {
            let message = "Could not find any trust origin"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        
        // Create a table of persisted trust origins
        
        for sTrustOrigin in sTrustOrigins {
            
            // Create a PersistedTrustOrigin from the trust origin
            let dPersistedTrustOrigin: NSManagedObject
            do {
                let entityName = "PersistedTrustOrigin"
                guard let description = NSEntityDescription.entity(forEntityName: entityName, in: manager.destinationContext) else {
                    let message = "Invalid entity name: \(entityName)"
                    let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                    throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
                }
                dPersistedTrustOrigin = NSManagedObject(entity: description, insertInto: manager.destinationContext)
            }

            // Set the attributes of the destination PersistedTrustOrigin
            dPersistedTrustOrigin.setValue(nil, forKey: "identityServer")
            switch sTrustOrigin {
            case .direct(timestamp: let timestamp):
                dPersistedTrustOrigin.setValue(nil, forKey: "mediatorOrGroupOwnerCryptoIdentity")
                dPersistedTrustOrigin.setValue(nil, forKey: "mediatorOrGroupOwnerTrustLevelMajor")
                dPersistedTrustOrigin.setValue(timestamp, forKey: "timestamp")
                dPersistedTrustOrigin.setValue(0, forKey: "trustTypeRaw")
            case .group(timestamp: let timestamp, groupId: let groupId):
                dPersistedTrustOrigin.setValue(groupId.ownerIdentity, forKey: "mediatorOrGroupOwnerCryptoIdentity")
                dPersistedTrustOrigin.setValue(4, forKey: "mediatorOrGroupOwnerTrustLevelMajor")
                dPersistedTrustOrigin.setValue(timestamp, forKey: "timestamp")
                dPersistedTrustOrigin.setValue(1, forKey: "trustTypeRaw")
            case .introduction(timestamp: let timestamp, mediator: let mediator):
                dPersistedTrustOrigin.setValue(mediator, forKey: "mediatorOrGroupOwnerCryptoIdentity")
                dPersistedTrustOrigin.setValue(4, forKey: "mediatorOrGroupOwnerTrustLevelMajor")
                dPersistedTrustOrigin.setValue(timestamp, forKey: "timestamp")
                dPersistedTrustOrigin.setValue(2, forKey: "trustTypeRaw")
            }
            
            // Associate the destination PersistedTrustOrigin with the destination contact identity
            dPersistedTrustOrigin.setValue(dContactIdentity, forKey: "contact")
            
        }
        
    }
}
