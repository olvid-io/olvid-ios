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
import ObvEncoder
import ObvCrypto
import ObvTypes

fileprivate let errorDomain = "ObvEngineMigrationV11ToV12"
fileprivate let debugPrintPrefix = "[\(errorDomain)][ContactGroupToContactGroupAndMoreMigrationPolicyV11ToV12]"


final class ContactGroupToContactGroupAndMoreMigrationPolicyV11ToV12: NSEntityMigrationPolicy {
    
    /// For each ContactGroup (v11), we do the following:
    ///
    /// - We create either an instance of ContactGroupJoined or an instance of ContactGroupOwned
    ///     - We set the groupMembersVersion to 0
    ///     - We change the name of contactIdentities into groupMembers
    ///     - We create an instance of ContactGroupDetailsPublished
    /// - If we created a ContactGroupJoined, we create an instance of ContactGroupDetailsTrusted identical the the ContactGroupDetailsPublished. We also look for the group owner among the contacts of the owned identity.
    /// - If we created a ContactGroupOwned, we create an instance of ContactGroupDetailsPublished identical the the ContactGroupDetailsPublished
    ///
    /// - Parameters:
    ///   - sInstance: a v11 instance of a `ContactGroup`
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(debugPrintPrefix) createDestinationInstances ends")
        }

        // Determine if we should create a ContactGroupJoined or a ContactGroupOwned
        let groupType = try getGroupType(forSource: sInstance)
        
        
        // Create either a ContactGroupJoined or a ContactGroupOwned
        
        var dContactGroup: NSManagedObject
        switch groupType {
        case .joined:
            dContactGroup = try initializeDestinationInstance(forEntityName: "ContactGroupJoined",
                                                              forSource: sInstance,
                                                              in: nil,
                                                              manager: manager,
                                                              errorDomain: errorDomain)
        case .owned:
            dContactGroup = try initializeDestinationInstance(forEntityName: "ContactGroupOwned",
                                                              forSource: sInstance,
                                                              in: nil,
                                                              manager: manager,
                                                              errorDomain: errorDomain)
        }
        
        // Since ContactGroupJoined and ContactGroupOwned are subclasses of the v12 version of ContactGroup, we can set the common attributes and relationships
        
        dContactGroup.setValue(0, forKey: "groupMembersVersion")
        guard let sGroupUid = sInstance.value(forKey: "groupUid") as? UID else {
            let message = "Could not get the group uid"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        dContactGroup.setValue(sGroupUid, forKey: "groupUid")
        // We do not compute the group members here, we do so in the `createRelationships` method.
        // Same thing for the owned identity
        
        
        // All the common attributes and relationships have been set, except publishedDetails that we create now
        // Then we set the publishedDetails relationship of the new ContactGroup instance
        
        let publishedDetails = try initializeDestinationInstance(forEntityName: "ContactGroupDetailsPublished",
                                                                 forSource: sInstance,
                                                                 in: nil,
                                                                 manager: manager,
                                                                 errorDomain: errorDomain)
        publishedDetails.setValue(nil, forKey: "photoServerKeyEncoded")
        publishedDetails.setValue(nil, forKey: "photoServerLabel")
        publishedDetails.setValue(nil, forKey: "photoURL")
        guard let groupName = sInstance.value(forKey: "groupName") as? String else {
            let message = "Could not get the group name"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        let coreDetails = ObvGroupCoreDetailsForMigrationTov12(name: groupName, description: nil)
        let serializedCoreDetails = try coreDetails.encode()
        publishedDetails.setValue(serializedCoreDetails, forKey: "serializedCoreDetails")
        publishedDetails.setValue(0, forKey: "version")
        
        dContactGroup.setValue(publishedDetails, forKey: "publishedDetails")
        
        
        // We deal with the two possible subclasses of ContactGroup
        
        switch groupType {
        case .joined:
            // The ContactGroup is a ContactGroupJoined. We can deal with the specific relationships
            let trustedDetails = try initializeDestinationInstance(forEntityName: "ContactGroupDetailsTrusted",
                                                                   forSource: sInstance,
                                                                   in: nil,
                                                                   manager: manager,
                                                                   errorDomain: errorDomain)
            trustedDetails.setValue(nil, forKey: "photoServerKeyEncoded")
            trustedDetails.setValue(nil, forKey: "photoServerLabel")
            trustedDetails.setValue(nil, forKey: "photoURL")
            trustedDetails.setValue(serializedCoreDetails, forKey: "serializedCoreDetails")
            trustedDetails.setValue(0, forKey: "version")
            dContactGroup.setValue(trustedDetails, forKey: "trustedDetails")
            // The group owner will be set in `createRelationships`
        case .owned:
            // The ContactGroup is a ContactGroupOwned. We can deal with the specific relationships
            let latestDetails = try initializeDestinationInstance(forEntityName: "ContactGroupDetailsLatest",
                                                                   forSource: sInstance,
                                                                   in: nil,
                                                                   manager: manager,
                                                                   errorDomain: errorDomain)
            latestDetails.setValue(nil, forKey: "photoServerKeyEncoded")
            latestDetails.setValue(nil, forKey: "photoServerLabel")
            latestDetails.setValue(nil, forKey: "photoURL")
            latestDetails.setValue(serializedCoreDetails, forKey: "serializedCoreDetails")
            latestDetails.setValue(0, forKey: "version")
            dContactGroup.setValue(latestDetails, forKey: "latestDetails")
        }

        // The migration manager needs to know the connection between the source object, the newly created destination object, and the mapping.
        
        manager.associate(sourceInstance: sInstance, withDestinationInstance: dContactGroup, for: mapping)

    }
    
    
    override func createRelationships(forDestination dInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(debugPrintPrefix) createRelationships starts")
        defer {
            debugPrint("\(debugPrintPrefix) createRelationships ends")
        }

        // Get the source instance
        
        let sInstance: NSManagedObject
        do {
            let sInstances = manager.sourceInstances(forEntityMappingName: mapping.name, destinationInstances: [dInstance])
            guard sInstances.count == 1 else {
                let message = "Could not get the source ContactGroup associated to the destination ContactGroup"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            sInstance = sInstances.first!
        }
        
        let groupType = try getGroupType(forSource: sInstance)
        

        // Specific action for a contact group that is joined...
        // Get the group owner from the source instance, get the corresponding contact in the destination context, and set the groupOwner of the destination instance

        if groupType == .joined {
            guard let groupOwnerCryptoIdentity = sInstance.value(forKey: "groupOwner") as? ObvCryptoIdentity else {
                let message = "Could not get the group owner crypto identity"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "ContactIdentity")
            request.predicate = NSPredicate(format: "%K == %@", "cryptoIdentity", groupOwnerCryptoIdentity)
            let _contactIdentity = try manager.destinationContext.fetch(request)
            guard _contactIdentity.count == 1 else {
                let message = "Failed to retrieve a contact identity to be set as the owner of a ContactGroupJoined"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            let contactIdentity = _contactIdentity.first!
            dInstance.setValue(contactIdentity, forKey: "groupOwner")
        }
        
        // For both kinds of groups, we must map the group members
        
        guard let sGroupMembers = sInstance.value(forKey: "contactIdentities") as? Set<NSManagedObject> else {
            let message = "Could not get the group members"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        let dGroupMembers = manager.destinationInstances(forEntityMappingName: "ContactIdentityToContactIdentity", sourceInstances: Array(sGroupMembers))
        guard dGroupMembers.count == sGroupMembers.count else {
            let message = "Wrong count of group members"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        dInstance.setValue(Set(dGroupMembers), forKey: "groupMembers")
        
        // Finally, we set the owned identity
        
        guard let sOwnedIdentity = sInstance.value(forKey: "ownedIdentity") as? NSManagedObject else {
            let message = "Could not get the owned identity associated with a contact group"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        let dOwnedIdentity: NSManagedObject
        do {
            let _dOwnedIdentities = manager.destinationInstances(forEntityMappingName: "OwnedIdentityToOwnedIdentity", sourceInstances: [sOwnedIdentity])
            guard _dOwnedIdentities.count == 1 else {
                let message = "Could not map the source owned identity to the destination owned identity"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            dOwnedIdentity = _dOwnedIdentities.first!
        }
        dInstance.setValue(dOwnedIdentity, forKey: "ownedIdentity")
        
    }
    
    
    private enum GroupType {
        case joined
        case owned
    }
    
    
    private func getGroupType(forSource sInstance: NSManagedObject) throws -> GroupType {
        // Determine if we should create a ContactGroupJoined or a ContactGroupOwned
        let groupType: GroupType
        do {
            guard let groupOwner = sInstance.value(forKey: "groupOwner") as? ObvCryptoIdentity else {
                let message = "Could not get group owner crypto identity"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            guard let ownedIdentity = sInstance.value(forKey: "ownedIdentity") as? NSManagedObject else {
                let message = "Could not get owned identity"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            guard let ownedIdentityCryptoIdentity = ownedIdentity.value(forKey: "cryptoIdentity") as? ObvCryptoIdentity else {
                let message = "Could not get the crypto identity of the owned identity"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            if groupOwner == ownedIdentityCryptoIdentity {
                groupType = .owned
            } else {
                groupType = .joined
            }
        }
        return groupType
    }
    
}
