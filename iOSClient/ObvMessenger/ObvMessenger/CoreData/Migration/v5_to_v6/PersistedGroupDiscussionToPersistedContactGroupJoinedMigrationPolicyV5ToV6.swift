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
import ObvEngine
import ObvEncoder
import ObvTypes

fileprivate let errorDomain = "MessengerMigrationV5ToV6"
fileprivate let debugPrintPrefix = "[\(errorDomain)][PersistedGroupDiscussionToPersistedContactGroupJoinedMigrationPolicyV5ToV6]"

final class PersistedGroupDiscussionToPersistedContactGroupJoinedMigrationPolicyV5ToV6: NSEntityMigrationPolicy {
    

    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(debugPrintPrefix) createDestinationInstances ends")
        }

        // We only create the destination instance (an "joined" PersistedContactGroup) if the source (a PersistedGroupDiscussion) is *not* owned. We check this first
        
        guard let title = sInstance.value(forKey: "title") as? String else {
            let message = "Failed to retrieve the title of a PersistedGroupDiscussion"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        guard let groupId = sInstance.value(forKey: "groupId") as? Data else {
            let message = "Failed to retrieve the groupId of a PersistedGroupDiscussion"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        guard let ownedIdentity = sInstance.value(forKeyPath: "ownedIdentity.identity") as? Data else {
            let message = "Failed to retrieve the ownedIdentity's identity of a PersistedGroupDiscussion"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        
        guard !groupId.starts(with: ownedIdentity) else {
            debugPrint("\(debugPrintPrefix) The PersistedGroupDiscussion [\(title)] is owned. We skip it.")
            return
        }

        // If we reach this point, the PersistedGroupDiscussion is one we joined. So we must create a corresponding PersistedContactGroupJoined
        
        // Create an instance of the destination object.
        let entityName = "PersistedContactGroupJoined"
        guard let description = NSEntityDescription.entity(forEntityName: entityName, in: manager.destinationContext) else {
            let message = "Invalid entity name: \(entityName)"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        let newPersistedContactGroupJoined = PersistedContactGroupJoined(entity: description, insertInto: manager.destinationContext)

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
                newPersistedContactGroupJoined.setValue(destinationValue, forKey: destinationName)
            }
        }

        // It is time to perform the complex mappings

        // We set the pending members to an empty set
        
        newPersistedContactGroupJoined.setValue(Set<PersistedPendingGroupMember>(), forKey: "pendingMembers")

        // We set the proper PersistedContactGroup.Category
        
        newPersistedContactGroupJoined.setValue(PersistedContactGroup.Category.joined.rawValue, forKey: "rawCategory")

        // The migration manager needs to know the connection between the source object, the newly created destination object, and the mapping.

        manager.associate(sourceInstance: sInstance, withDestinationInstance: newPersistedContactGroupJoined, for: mapping)

    }
    
    
    override func createRelationships(forDestination dInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(debugPrintPrefix) createRelationships starts")
        defer {
            debugPrint("\(debugPrintPrefix) createRelationships ends")
        }

        // We get the associated PersistedGroupDiscussion as it exists in the destination context
        // We also get the owned identity of the PersistedGroupDiscussion
        // We also get the contact identities of the PersistedGroupDiscussion

        let dPersistedGroupDiscussion: NSManagedObject
        let dPersistedOwnedIdentity: NSManagedObject
        let dPersistedObvContactIdentities: Set<NSManagedObject>
        do {
            let _sPersistedGroupDiscussion = manager.sourceInstances(forEntityMappingName: mapping.name, destinationInstances: [dInstance])
            guard _sPersistedGroupDiscussion.count == 1 else {
                let message = "Failed to retrieve the PersistedGroupDiscussion source"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            let sPersistedGroupDiscussion = _sPersistedGroupDiscussion.first!
            // Get the destination PersistedGroupDiscussion using the PersistedGroupDiscussionToPersistedGroupDiscussion mapping
            let _dPersistedGroupDiscussion = manager.destinationInstances(forEntityMappingName: "PersistedGroupDiscussionToPersistedGroupDiscussion", sourceInstances: [sPersistedGroupDiscussion])
            guard _dPersistedGroupDiscussion.count == 1 else {
                let message = "Unexpected number of PersistedGroupDiscussion in new context (\(_dPersistedGroupDiscussion.count))"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            dPersistedGroupDiscussion = _dPersistedGroupDiscussion.first!
            // Get the owned identity using the PersistedObvOwnedIdentityToPersistedObvOwnedIdentity mapping
            guard let sOwnedIdentity = sPersistedGroupDiscussion.value(forKey: "ownedIdentity") as? NSManagedObject else {
                let message = "Failed to retrieve the owned identity associated with a PersistedGroupDiscussion"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            let _dOwnedIdentity = manager.destinationInstances(forEntityMappingName: "PersistedObvOwnedIdentityToPersistedObvOwnedIdentity", sourceInstances: [sOwnedIdentity])
            guard _dOwnedIdentity.count == 1 else {
                let message = "Unexpected number of PersistedOwnedIdentity in new context (\(_dOwnedIdentity.count))"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            dPersistedOwnedIdentity = _dOwnedIdentity.first!
            // Get the contact identities using the PersistedObvContactIdentityToPersistedObvContactIdentity mapping
            guard let sContactIdentities = sPersistedGroupDiscussion.value(forKey: "contactIdentities") as? Set<NSManagedObject> else {
                let message = "Failed to retrieve the contact identities associated with a PersistedGroupDiscussion"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            let _dContactIdentities = manager.destinationInstances(forEntityMappingName: "PersistedObvContactIdentityToPersistedObvContactIdentity", sourceInstances: Array(sContactIdentities))
            guard _dContactIdentities.count == sContactIdentities.count else {
                let message = "Unexpected number of PersistedObvContactIdentity in new context (\(_dContactIdentities.count) != \(sContactIdentities.count))"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            dPersistedObvContactIdentities = Set(_dContactIdentities)
        }
        
        // We want to set the 'discussion' relation on the target PersistedContactGroup to the related instance of PersistedGroupDiscussion
        
        dInstance.setValue(dPersistedGroupDiscussion, forKey: "discussion")
        
        // We set the 'ownedIdentity" relation on the target PersistedContactGroupOwned to the ownedIdentity we retrieved
        
        dInstance.setValue(dPersistedOwnedIdentity, forKey: "ownedIdentity")
        
        // We set the 'contactIdentities' relation

        dInstance.setValue(dPersistedObvContactIdentities, forKey: "contactIdentities")

        // We look for the identity stored at the begining of the groupId on the target PersistedContactGroupOwned to the contactIdentities we retrieved
        
        guard let groupId = dInstance.value(forKey: "groupId") as? Data else {
            let message = "Failed to retrieve the groupId of a PersistedGroupDiscussion"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        let identity = groupId[groupId.startIndex..<groupId.endIndex - 32]

        // We fetch the PersistedObvContactIdentity corresponding to the identity we just found and satisfy the 'owner' relationship
        
        let request = NSFetchRequest<NSManagedObject>(entityName: "PersistedObvContactIdentity")
        request.predicate = NSPredicate(format: "%K == %@", "identity", identity as NSData)
        let _contactIdentity = try manager.destinationContext.fetch(request)
        guard _contactIdentity.count == 1 else {
            let message = "Failed to retrieve an contact identity to be set a the owner of a PersistedContactGroupJoined"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        let contactIdentity = _contactIdentity.first!
        dInstance.setValue(contactIdentity, forKey: "owner")

    }
}
