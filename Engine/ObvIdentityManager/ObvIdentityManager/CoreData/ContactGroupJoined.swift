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
import os.log
import ObvTypes
import ObvCrypto
import ObvMetaManager
import OlvidUtils

@objc(ContactGroupJoined)
final class ContactGroupJoined: ContactGroup {
    
    // MARK: Internal constants
    
    private static let entityName = "ContactGroupJoined"
    private static let errorDomain = String(describing: ContactGroupJoined.self)
    private static let groupOwnerKey = "groupOwner"
    private static let trustedDetailsKey = "trustedDetails"
    private static let groupOwnerCryptoIdentityKey = [groupOwnerKey, ContactIdentity.cryptoIdentityKey].joined(separator: ".")
    
    // MARK: Relationships
    
    private(set) var groupOwner: ContactIdentity {
        get {
            let item = kvoSafePrimitiveValue(forKey: ContactGroupJoined.groupOwnerKey) as! ContactIdentity
            item.obvContext = self.obvContext
            return item
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: ContactGroupJoined.groupOwnerKey)
        }
    }

    private(set) var trustedDetails: ContactGroupDetailsTrusted {
        get {
            let item = kvoSafePrimitiveValue(forKey: ContactGroupJoined.trustedDetailsKey) as! ContactGroupDetailsTrusted
            item.obvContext = self.obvContext
            return item
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: ContactGroupJoined.trustedDetailsKey)
        }
    }
    
    // MARK: Other variables
    
    private var notificationRelatedChanges: NotificationRelatedChanges = []
    
    // MARK: - Initializer
    
    convenience init(groupInformation: GroupInformation, ownedIdentity: ObvCryptoIdentity, groupOwnerCryptoIdentity: ObvCryptoIdentity, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>, delegateManager: ObvIdentityDelegateManager, within obvContext: ObvContext) throws {
        
        guard let groupOwner = try ContactIdentity.get(contactIdentity: groupInformation.groupOwnerIdentity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned.error(withDomain: ContactGroupJoined.errorDomain)
        }
        
        guard try ContactGroupJoined.get(groupUid: groupInformation.groupUid, groupOwnerCryptoIdentity: groupInformation.groupOwnerIdentity, ownedIdentity: groupOwner.ownedIdentity, delegateManager: delegateManager) == nil else {
            throw ObvIdentityManagerError.tryingToCreateContactGroupThatAlreadyExists.error(withDomain: ContactGroupJoined.errorDomain)
        }
        
        let groupInformationWithPhoto = GroupInformationWithPhoto(groupInformation: groupInformation, photoURL: nil)
        // Note that this will include inactive contacts in the group members. There is not much we can do.
        try self.init(groupInformationWithPhoto: groupInformationWithPhoto,
                      ownedIdentity: groupOwner.ownedIdentity,
                      groupMembers: Set<ObvCryptoIdentity>([groupOwner.cryptoIdentity]),
                      pendingGroupMembers: pendingGroupMembers,
                      delegateManager: delegateManager,
                      forEntityName: ContactGroupJoined.entityName)
        
        self.groupOwner = groupOwner
        self.trustedDetails = try ContactGroupDetailsTrusted(contactGroupJoined: self,
                                                             groupDetailsElementsWithPhoto: groupInformationWithPhoto.groupDetailsElementsWithPhoto,
                                                             identityPhotosDirectory: delegateManager.identityPhotosDirectory,
                                                             notificationDelegate: delegateManager.notificationDelegate)
        
    }
    
    
    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreater in a second step
    convenience init(backupItem: ContactGroupJoinedBackupItem, within obvContext: ObvContext) {
        self.init(groupMembersVersion: backupItem.groupMembersVersion,
                  groupUid: backupItem.groupUid,
                  forEntityName: ContactGroupJoined.entityName,
                  within: obvContext)
    }

    fileprivate func restoreRelationshipsOfContactGroupJoined(trustedDetails: ContactGroupDetailsTrusted, groupMembers: Set<ContactIdentity>, pendingGroupMembers: Set<PendingGroupMember>, publishedDetails: ContactGroupDetailsPublished) {
        /* groupOwner is set within ContactIdentity */
        self.trustedDetails = trustedDetails
        self.restoreRelationshipsOfContactGroup(groupMembers: groupMembers,
                                                pendingGroupMembers: pendingGroupMembers,
                                                publishedDetails: publishedDetails)
    }

    func updatePhotoURL(with url: URL?, ofDetailsWithVersion version: Int, delegateManager: ObvIdentityDelegateManager, within obvContext: ObvContext) throws {
        if self.publishedDetails.version == version {
            try self.publishedDetails.setPhotoURL(with: url, creatingNewFileIn: delegateManager.identityPhotosDirectory, notificationDelegate: delegateManager.notificationDelegate)
        }
        if self.trustedDetails.version == version {
            try self.trustedDetails.setPhotoURL(with: url, creatingNewFileIn: delegateManager.identityPhotosDirectory, notificationDelegate: delegateManager.notificationDelegate)
        }
    }

    func updatePhoto(withData photoData: Data, ofDetailsWithVersion version: Int, delegateManager: ObvIdentityDelegateManager, within obvContext: ObvContext) throws {
        if self.publishedDetails.version == version {
            try self.publishedDetails.setPhoto(data: photoData, creatingNewFileIn: delegateManager.identityPhotosDirectory, notificationDelegate: delegateManager.notificationDelegate)
        }
        if self.trustedDetails.version == version {
            try self.trustedDetails.setPhoto(data: photoData, creatingNewFileIn: delegateManager.identityPhotosDirectory, notificationDelegate: delegateManager.notificationDelegate)
        }
    }

}


// MARK: - Updating the pending and group members

extension ContactGroupJoined {
    
    func updatePendingMembersAndGroupMembers(groupMembersWithCoreDetails: Set<CryptoIdentityWithCoreDetails>, pendingMembersWithCoreDetails: Set<CryptoIdentityWithCoreDetails>, groupMembersVersion: Int, delegateManager: ObvIdentityDelegateManager, flowId: FlowIdentifier) throws {
        
        guard groupMembersVersion > self.groupMembersVersion else { return }
        
        let errorDomain = ContactGroupJoined.errorDomain
        
        guard let obvContext = self.obvContext else {
            throw ObvIdentityManagerError.contextIsNil.error(withDomain: errorDomain)
        }
        
        // Check that no identity appears both within the (new) pending members and the (new) group members
        
        do {
            let groupMemberIdentitiesNew = Set(groupMembersWithCoreDetails.map { $0.cryptoIdentity })
            let pendingGroupMemberIdentitiesNew = Set(pendingMembersWithCoreDetails.map { $0.cryptoIdentity })
            guard groupMemberIdentitiesNew.intersection(pendingGroupMemberIdentitiesNew).isEmpty else {
                throw ObvIdentityManagerError.anIdentityAppearsBothWithinPendingMembersAndGroupMembers.error(withDomain: errorDomain)
            }
        }
        
        // Create a new version of the group members

        let newVersionOfGroupMembers: Set<ContactIdentity> = Set( try groupMembersWithCoreDetails.compactMap { (groupMemberWithCoreDetails) in
            guard groupMemberWithCoreDetails.cryptoIdentity != ownedIdentity.cryptoIdentity else { return nil }
            if let contact = try ContactIdentity.get(contactIdentity: groupMemberWithCoreDetails.cryptoIdentity, ownedIdentity: ownedIdentity.cryptoIdentity, delegateManager: delegateManager, within: obvContext) {
                // The identity is already a contact, we simply insert it in the list of group members
                return contact
            } else {
                // The identity is not a contact yet, we create the contact and insert it in the list of group members
                let trustOrigin = TrustOrigin.group(timestamp: Date(), groupOwner: groupOwner.cryptoIdentity)
                guard let contact = ContactIdentity(cryptoIdentity: groupMemberWithCoreDetails.cryptoIdentity,
                                                    identityCoreDetails: groupMemberWithCoreDetails.coreDetails,
                                                    trustOrigin: trustOrigin,
                                                    ownedIdentity: ownedIdentity,
                                                    delegateManager: delegateManager)
                    else {
                        throw ObvIdentityManagerError.contactCreationFailed.error(withDomain: errorDomain)
                }
                return contact
            }
        })
        
        // Create a new version of the pending group members
        
        let newVersionOfPendingMembers: Set<PendingGroupMember> = Set( try pendingMembersWithCoreDetails.map { (pendingMemberWithCoreDetails) in
            
            if let pendingMember = try PendingGroupMember.get(cryptoIdentity: pendingMemberWithCoreDetails.cryptoIdentity, contactGroup: self, delegateManager: delegateManager) {
                // The identity is already a pending member, we simply insert in the new list of pending members
                return pendingMember
            } else {
                // The identity is not yet a PendingMember, we create it and insert it
                let pendingMember = try PendingGroupMember(contactGroup: self, cryptoIdentityWithCoreDetails: pendingMemberWithCoreDetails, delegateManager: delegateManager)
                return pendingMember
            }
        })
        
        // Replace the old versions of the group members and of the pending members by the new ones and update the version number
        
        try super.updatePendingMembersAndGroupMembers(newVersionOfGroupMembers: newVersionOfGroupMembers,
                                                      newVersionOfPendingMembers: newVersionOfPendingMembers,
                                                      groupMembersVersion: groupMembersVersion)
        
    }
    
}

// MARK: - Convenience methods

extension ContactGroupJoined {
    
    func getPublishedJoinedGroupInformation() throws -> GroupInformation {
        let groupDetailsElements = try publishedDetails.getGroupDetailsElements()
        let groupInformation = try GroupInformation(groupOwnerIdentity: groupOwner.cryptoIdentity,
                                                    groupUid: groupUid,
                                                    groupDetailsElements: groupDetailsElements)
        return groupInformation
    }

    
    func getPublishedJoinedGroupInformationWithPhoto() throws -> GroupInformationWithPhoto {
        let groupInformation = try getPublishedJoinedGroupInformation()
        let photoURL = publishedDetails.photoURL
        let groupInformationWithPhoto = GroupInformationWithPhoto(groupInformation: groupInformation,
                                                                  photoURL: photoURL)
        return groupInformationWithPhoto
    }

    
    func getTrustedJoinedGroupInformation() throws -> GroupInformation {
        let groupDetailsElements = try trustedDetails.getGroupDetailsElements()
        let groupInformation = try GroupInformation(groupOwnerIdentity: groupOwner.cryptoIdentity,
                                                    groupUid: groupUid,
                                                    groupDetailsElements: groupDetailsElements)
        return groupInformation
    }

    func getTrustedJoinedGroupInformationWithPhoto() throws -> GroupInformationWithPhoto {
        let groupInformation = try getTrustedJoinedGroupInformation()
        let photoURL = trustedDetails.photoURL
        let groupInformationWithPhoto = GroupInformationWithPhoto(groupInformation: groupInformation,
                                                                  photoURL: photoURL)
        return groupInformationWithPhoto
    }


    func trustDetailsPublished(within obvContext: ObvContext, delegateManager: ObvIdentityDelegateManager) throws {
        let errorDomain = ContactGroupJoined.errorDomain
        guard publishedDetails.version > trustedDetails.version else {
            throw ObvIdentityManagerError.invalidGroupDetailsVersion.error(withDomain: errorDomain)
        }
        let groupDetailsElementsWithPhoto = try publishedDetails.getGroupDetailsElementsWithPhoto()
        try self.trustedDetails.delete(within: obvContext)
        _ = try ContactGroupDetailsTrusted(contactGroupJoined: self,
                                           groupDetailsElementsWithPhoto: groupDetailsElementsWithPhoto,
                                           identityPhotosDirectory: delegateManager.identityPhotosDirectory,
                                           notificationDelegate: delegateManager.notificationDelegate)
        notificationRelatedChanges.insert(.updatedTrustedDetails)
    }

    
    func resetGroupDetailsWithAuthoritativeDetailsIfRequired(_ authoritativeDetailsElements: GroupDetailsElements, delegateManager: ObvIdentityDelegateManager, within obvContext: ObvContext) throws {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: String(describing: self))
  
        guard try self.publishedDetails.getGroupDetailsElementsWithPhoto().version != authoritativeDetailsElements.version else {
            os_log("No need to update the (local) published details of contact group joined since they are identical to the received authoritative details", log: log, type: .info)
            return
        }
        
        os_log("We received new authoritative details for a group joined, which are distinct from the (local) published details. We update the trusted details version and published details accordingly.", log: log, type: .info)
        
        // If we reach this point, the (local) published details are distinct to the authoritative details.
        // We replace the local (published) details by the ones we just received.
        let currentTrustedDetails = try self.trustedDetails.getGroupDetailsElementsWithPhoto()
        let trustedDetailsWithResetVersionNumber = GroupDetailsElementsWithPhoto(coreDetails: currentTrustedDetails.coreDetails,
                                                                                 version: -1,
                                                                                 photoServerKeyAndLabel: currentTrustedDetails.photoServerKeyAndLabel,
                                                                                 photoURL: currentTrustedDetails.photoURL)
        try self.trustedDetails.delete(within: obvContext)
        try self.publishedDetails.delete(within: obvContext)
        
        let authoritativeDetailsElementsWithPhoto = GroupDetailsElementsWithPhoto(groupDetailsElements: authoritativeDetailsElements, photoURL: nil)
        _ = try ContactGroupDetailsPublished(contactGroup: self,
                                             groupDetailsElementsWithPhoto: authoritativeDetailsElementsWithPhoto,
                                             identityPhotosDirectory: delegateManager.identityPhotosDirectory,
                                             notificationDelegate: delegateManager.notificationDelegate)
        _ = try ContactGroupDetailsTrusted(contactGroupJoined: self,
                                           groupDetailsElementsWithPhoto: trustedDetailsWithResetVersionNumber,
                                           identityPhotosDirectory: delegateManager.identityPhotosDirectory,
                                           notificationDelegate: delegateManager.notificationDelegate)

    }
    
    
    func getJoinedGroupStructure() throws -> GroupStructure {
        
        let groupMembers = Set(self.groupMembers.map { $0.cryptoIdentity })
        let pendingGroupMembers = self.getPendingGroupMembersWithCoreDetails()
        let groupMembersVersion = self.groupMembersVersion
        let publishedGroupDetailsWithPhoto = try self.publishedDetails.getGroupDetailsElementsWithPhoto()
        let trustedGroupDetails = try self.trustedDetails.getGroupDetailsElementsWithPhoto()

        let groupStructure = GroupStructure.createJoinedGroupStructure(
            groupUid: groupUid,
            publishedGroupDetailsWithPhoto: publishedGroupDetailsWithPhoto,
            trustedGroupDetailsWithPhoto: trustedGroupDetails,
            ownedIdentity: ownedIdentity.cryptoIdentity,
            groupMembers: groupMembers,
            pendingGroupMembers: pendingGroupMembers,
            groupMembersVersion: groupMembersVersion,
            groupOwner: self.groupOwner.cryptoIdentity)

        return groupStructure

    }
    
}


// MARK: - Convenience DB getters

extension ContactGroupJoined {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<ContactGroupJoined> {
        return NSFetchRequest<ContactGroupJoined>(entityName: entityName)
    }

    static func get(groupUid: UID, groupOwnerCryptoIdentity: ObvCryptoIdentity, ownedIdentity: OwnedIdentity, delegateManager: ObvIdentityDelegateManager) throws -> ContactGroupJoined? {
        guard let obvContext = ownedIdentity.obvContext else {
            throw ObvIdentityManagerError.contextIsNil.error(withDomain: ContactGroupJoined.errorDomain)
        }
        let request: NSFetchRequest<ContactGroupJoined> = ContactGroupJoined.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@ AND %K == %@",
                                        ContactGroup.groupUidKey, groupUid,
                                        ContactGroupJoined.groupOwnerCryptoIdentityKey, groupOwnerCryptoIdentity,
                                        ContactGroup.ownedIdentityKey, ownedIdentity)
        request.fetchLimit = 1
        let item = (try obvContext.fetch(request)).first
        item?.delegateManager = delegateManager
        return item
    }
    
}


// MARK: - Sending notifications

extension ContactGroupJoined {
    
    private struct NotificationRelatedChanges: OptionSet {
        let rawValue: UInt8
        static let updatedTrustedDetails = NotificationRelatedChanges(rawValue: 1 << 0)
    }
    
    override func didSave() {
        super.didSave()
        
        defer {
            notificationRelatedChanges = []
        }
        
        guard let delegateManager = delegateManager else {
            let log = OSLog.init(subsystem: ObvIdentityDelegateManager.defaultLogSubsystem, category: String(describing: Self.self))
            os_log("The delegate manager is not set (2)", log: log, type: .fault)
            return
        }
        
        if isInserted {
            
            let NotificationType = ObvIdentityNotification.NewContactGroupJoined.self
            let userInfo = [NotificationType.Key.groupUid: self.groupUid,
                            NotificationType.Key.groupOwner: self.groupOwner.cryptoIdentity,
                            NotificationType.Key.ownedIdentity: self.ownedIdentity.cryptoIdentity] as [String: Any]
            delegateManager.notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
            
        }

        if notificationRelatedChanges.contains(.updatedTrustedDetails) {
            
            let NotificationType = ObvIdentityNotification.ContactGroupJoinedHasUpdatedTrustedDetails.self
            let userInfo = [NotificationType.Key.groupUid: self.groupUid,
                            NotificationType.Key.groupOwner: self.groupOwner.cryptoIdentity,
                            NotificationType.Key.ownedIdentity: self.ownedIdentity.cryptoIdentity] as [String: Any]
            delegateManager.notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
            
        }
        
    }
    
}


// MARK: - For Backup purposes

extension ContactGroupJoined {
    
    var backupItem: ContactGroupJoinedBackupItem {
        return ContactGroupJoinedBackupItem(groupMembersVersion: groupMembersVersion,
                                            groupUid: groupUid,
                                            groupMembers: groupMembers,
                                            pendingGroupMembers: pendingGroupMembers,
                                            publishedDetails: publishedDetails,
                                            trustedDetails: trustedDetails)
    }

}

fileprivate struct GroupMemberBackupItem: Codable, Hashable {
    
    // Identity and contact_identity
    fileprivate let memberIdentity: Data
    
    fileprivate init(memberIdentity: Data) {
        self.memberIdentity = memberIdentity
    }
    
    enum CodingKeys: String, CodingKey {
        case memberIdentity = "contact_identity"
    }
    
}

struct ContactGroupJoinedBackupItem: Codable, Hashable {
    
    // Inherited from ContactGroup
    fileprivate let groupMembersVersion: Int
    fileprivate let groupUid: UID
    fileprivate let groupMembers: Set<GroupMemberBackupItem>
    fileprivate let pendingGroupMembers: Set<PendingGroupMemberBackupItem>
    fileprivate let publishedDetails: ContactGroupDetailsBackupItem?
    // Local
    fileprivate let trustedDetails: ContactGroupDetailsBackupItem
    
    private static let errorDomain = String(describing: Self.self)

    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    fileprivate init(groupMembersVersion: Int, groupUid: UID, groupMembers: Set<ContactIdentity>, pendingGroupMembers: Set<PendingGroupMember>, publishedDetails: ContactGroupDetailsPublished, trustedDetails: ContactGroupDetailsTrusted) {
        self.groupMembersVersion = groupMembersVersion
        self.groupUid = groupUid
        self.groupMembers = Set(groupMembers.map({ GroupMemberBackupItem(memberIdentity: $0.cryptoIdentity.getIdentity()) }))
        self.pendingGroupMembers = Set(pendingGroupMembers.map { $0.backupItem })
        // If the published details are identical to the trusted details, we do not include them in the json file
        if publishedDetails.version == trustedDetails.version {
            self.publishedDetails = nil
        } else {
            self.publishedDetails = publishedDetails.backupItem
        }
        self.trustedDetails = trustedDetails.backupItem
    }
    
    
    enum CodingKeys: String, CodingKey {
        // Inherited from ContactGroup
        case groupMembersVersion = "group_members_version"
        case groupUid = "group_uid"
        case groupMembers = "members"
        case pendingGroupMembers = "pending_members"
        case publishedDetails = "published_details"
        // Local
        case trustedDetails = "trusted_details"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Inherited from ContactGroup
        try container.encode(groupMembersVersion, forKey: .groupMembersVersion)
        try container.encode(groupUid.raw, forKey: .groupUid)
        try container.encode(groupMembers, forKey: .groupMembers)
        try container.encode(pendingGroupMembers, forKey: .pendingGroupMembers)
        try container.encodeIfPresent(publishedDetails, forKey: .publishedDetails)
        try container.encode(trustedDetails, forKey: .trustedDetails)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.groupMembersVersion = try values.decode(Int.self, forKey: .groupMembersVersion)
        let groupUidRaw = try values.decode(Data.self, forKey: .groupUid)
        guard let groupUid = UID(uid: groupUidRaw) else {
            throw ContactGroupJoinedBackupItem.makeError(message: "Could get group uid")
        }
        self.groupUid = groupUid
        self.pendingGroupMembers = try values.decode(Set<PendingGroupMemberBackupItem>.self, forKey: .pendingGroupMembers)
        self.groupMembers = try values.decode(Set<GroupMemberBackupItem>.self, forKey: .groupMembers)
        let trustedDetails = try values.decode(ContactGroupDetailsBackupItem.self, forKey: .trustedDetails)
        self.trustedDetails = trustedDetails
        // We ensure that publishedDetails are non nil, since this is required by the database
        // If we cannot find published details in the json, we use the trusted details instead.
        self.publishedDetails = try values.decodeIfPresent(ContactGroupDetailsBackupItem.self, forKey: .publishedDetails) ?? trustedDetails.duplicate()
    }
 
    func restoreInstance(within obvContext: ObvContext, associations: inout BackupItemObjectAssociations) throws {
        let contactGroupJoined = ContactGroupJoined(backupItem: self, within: obvContext)
        try associations.associate(contactGroupJoined, to: self)
        _ = try pendingGroupMembers.map { try $0.restoreInstance(within: obvContext, associations: &associations) }
        guard let publishedDetailsBackupItem = self.publishedDetails else {
            throw ContactGroupJoinedBackupItem.makeError(message: "self.publishedDetails must be non-nil at this point")
        }
        try publishedDetailsBackupItem.restoreContactGroupDetailsPublishedInstance(within: obvContext, associations: &associations)
        try trustedDetails.restoreContactGroupDetailsTrustedInstance(within: obvContext, associations: &associations)
    }
    
    func restoreRelationships(associations: BackupItemObjectAssociations, within obvContext: ObvContext) throws {
        let contactGroupJoined: ContactGroupJoined = try associations.getObject(associatedTo: self, within: obvContext)
        // Restore the relationships of this instance
        let trustedDetails: ContactGroupDetailsTrusted = try associations.getObject(associatedTo: self.trustedDetails, within: obvContext)
        
        var groupMembers = Set<ContactIdentity>()
        do {
            let allContacts = obvContext.registeredObjects.filter({ $0 is ContactIdentity }) as! Set<ContactIdentity>
            for groupMember in self.groupMembers {
                guard let groupMemberAsContact = allContacts.first(where: { $0.cryptoIdentity.getIdentity() == groupMember.memberIdentity }) else {
                    throw ContactGroupJoinedBackupItem.makeError(message: "Could not find the contact identity instance corresponding to the group member")
                }
                groupMembers.insert(groupMemberAsContact)
            }
            guard groupMembers.count == self.groupMembers.count else {
                throw ContactGroupJoinedBackupItem.makeError(message: "Unexpected number of group members")
            }
        }
        
        let pendingGroupMembers: Set<PendingGroupMember> = Set(try self.pendingGroupMembers.map({ try associations.getObject(associatedTo: $0, within: obvContext) }))
        guard let publishedDetailsBackupItem = self.publishedDetails else {
            throw ContactGroupJoinedBackupItem.makeError(message: "self.publishedDetails must be non-nil at this point")
        }
        let publishedDetails: ContactGroupDetailsPublished = try associations.getObject(associatedTo: publishedDetailsBackupItem, within: obvContext)
        contactGroupJoined.restoreRelationshipsOfContactGroupJoined(trustedDetails: trustedDetails,
                                                                    groupMembers: groupMembers,
                                                                    pendingGroupMembers: pendingGroupMembers,
                                                                    publishedDetails: publishedDetails)
        // Restore the relationships with this instance relationships
        _ = try self.pendingGroupMembers.map({ try $0.restoreRelationships(associations: associations, within: obvContext) })
        try publishedDetailsBackupItem.restoreRelationships(associations: associations, within: obvContext)
        try self.trustedDetails.restoreRelationships(associations: associations, within: obvContext)
    }

}
