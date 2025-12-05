/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import OSLog
import ObvTypes
import ObvCrypto
import ObvMetaManager
import OlvidUtils

@objc(ContactGroupJoined)
final class ContactGroupJoined: ContactGroup, ObvErrorMaker {
    
    // MARK: Internal constants
    
    private static let entityName = "ContactGroupJoined"
    static let errorDomain = String(describing: ContactGroupJoined.self)
    private static var logSubsystem: String { delegateManager?.logSubsystem ?? ObvIdentityDelegateManager.defaultLogSubsystem }
    private static var logger: Logger = { Logger(subsystem: ContactGroupJoined.logSubsystem, category: "ContactGroupDetailsTrusted") }()

    // MARK: Relationships
    
    @NSManaged private(set) var groupOwner: ContactIdentity
    @NSManaged private(set) var trustedDetails: ContactGroupDetailsTrusted
    
    // MARK: Other variables
    
    private var notificationRelatedChanges: NotificationRelatedChanges = []
    
    // MARK: - Initializer
    
    convenience init(groupInformation: GroupInformation, ownedIdentity: ObvCryptoIdentity, groupOwnerCryptoIdentity: ObvCryptoIdentity, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>, within context: NSManagedObjectContext) throws {
        
        guard let groupOwner = try ContactIdentity.get(contactIdentity: groupInformation.groupOwnerIdentity, ownedIdentity: ownedIdentity, within: context) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned
        }
        
        guard let ownedIdentity = groupOwner.ownedIdentity else {
            throw Self.makeError(message: "Could not find owned identity associated with the group owner")
        }
        
        guard try ContactGroupJoined.get(groupUid: groupInformation.groupUid, groupOwnerCryptoIdentity: groupInformation.groupOwnerIdentity, ownedIdentity: ownedIdentity) == nil else {
            throw ObvIdentityManagerError.tryingToCreateContactGroupThatAlreadyExists
        }
        
        guard let groupOwnerCryptoIdentity = groupOwner.cryptoIdentity else {
            assertionFailure()
            throw Self.makeError(message: "Could not get group owner crypto identity")
        }
        
        let groupInformationWithPhoto = GroupInformationWithPhoto(groupInformation: groupInformation, photoURL: nil)
        // Note that this will include inactive contacts in the group members. There is not much we can do.
        try self.init(groupInformationWithPhoto: groupInformationWithPhoto,
                      ownedIdentity: ownedIdentity,
                      groupMembers: Set<ObvCryptoIdentity>([groupOwnerCryptoIdentity]),
                      pendingGroupMembers: pendingGroupMembers,
                      forEntityName: ContactGroupJoined.entityName)
        
        self.groupOwner = groupOwner
        self.trustedDetails = try ContactGroupDetailsTrusted(contactGroupJoined: self,
                                                             groupDetailsElementsWithPhoto: groupInformationWithPhoto.groupDetailsElementsWithPhoto)
        
    }
    
    
    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreater in a second step
    convenience init(backupItem: ContactGroupJoinedBackupItem, within context: NSManagedObjectContext) {
        self.init(groupMembersVersion: backupItem.groupMembersVersion,
                  groupUid: backupItem.groupUid,
                  forEntityName: ContactGroupJoined.entityName,
                  within: context)
    }


    /// Used when restoring a backup
    fileprivate func restoreRelationshipsOfContactGroupJoined(trustedDetails: ContactGroupDetailsTrusted, groupMembers: Set<ContactIdentity>, pendingGroupMembers: Set<PendingGroupMember>, publishedDetails: ContactGroupDetailsPublished) {
        /* groupOwner is set within ContactIdentity */
        self.trustedDetails = trustedDetails
        self.restoreRelationshipsOfContactGroup(groupMembers: groupMembers,
                                                pendingGroupMembers: pendingGroupMembers,
                                                publishedDetails: publishedDetails)
    }

    
    /// Used when restoring a snapshot
    func restoreRelationshipsOfContactGroupJoined(groupOwner: ContactIdentity, trustedDetails: ContactGroupDetailsTrusted, groupMembers: Set<ContactIdentity>, pendingGroupMembers: Set<PendingGroupMember>, publishedDetails: ContactGroupDetailsPublished) {
        self.groupOwner = groupOwner
        self.trustedDetails = trustedDetails
        self.restoreRelationshipsOfContactGroup(groupMembers: groupMembers,
                                                pendingGroupMembers: pendingGroupMembers,
                                                publishedDetails: publishedDetails)
    }

    
    /// Used *exclusively* during a snapshot restore for creating an instance, relatioships are recreater in a second step
    convenience init(snapshotNode: ContactGroupSyncSnapshotNode, groupUid: UID, within context: NSManagedObjectContext) throws {
        guard let groupMembersVersion = snapshotNode.groupMembersVersion else {
            assertionFailure()
            throw ContactGroupSyncSnapshotNode.ObvError.tryingToRestoreIncompleteNode
        }
        self.init(groupMembersVersion: groupMembersVersion,
                  groupUid: groupUid,
                  forEntityName: ContactGroupJoined.entityName,
                  within: context)
    }

    
    func updatePhoto(withData photoData: Data, ofDetailsWithVersion version: Int, within context: NSManagedObjectContext) throws {
        
        if self.publishedDetails.version == version {
            try self.publishedDetails.setGroupPhoto(data: photoData)
        }
        
        // In the following, if the photo was ok for the published details and if publishedDetails.photoServerLabel == trustedDetails.photoServerLabel, we use the photo for the trusted details.
        // Note that the equality test between keys and labels does deserialize keys to compare them.
        
        let trustedDetailsCanUseSamePhotoThanPublishedDetails: Bool
        if let tskl = self.trustedDetails.photoServerKeyAndLabel, let pskl = self.publishedDetails.photoServerKeyAndLabel, tskl == pskl,
           self.publishedDetails.version == version {
            trustedDetailsCanUseSamePhotoThanPublishedDetails = true
        } else {
            trustedDetailsCanUseSamePhotoThanPublishedDetails = false
        }
        
        if self.trustedDetails.version == version || trustedDetailsCanUseSamePhotoThanPublishedDetails {
            try self.trustedDetails.setGroupPhoto(data: photoData)
        }
        
    }
    
    
    func delete() throws {
        guard let context = self.managedObjectContext else { throw Self.makeError(message: "Could not find context") }
        try trustedDetails.delete()
        try publishedDetails.delete()
        context.delete(self)
    }

}


// MARK: - Updating the pending and group members

extension ContactGroupJoined {
    
    func updatePendingMembersAndGroupMembers(groupMembersWithCoreDetails: Set<CryptoIdentityWithCoreDetails>, pendingMembersWithCoreDetails: Set<CryptoIdentityWithCoreDetails>, groupMembersVersion: Int, flowId: FlowIdentifier) throws {
        
        guard groupMembersVersion > self.groupMembersVersion else { return }
        
        guard let context = self.managedObjectContext else {
            throw ObvIdentityManagerError.contextIsNil
        }
        
        // Check that no identity appears both within the (new) pending members and the (new) group members
        
        do {
            let groupMemberIdentitiesNew = Set(groupMembersWithCoreDetails.map { $0.cryptoIdentity })
            let pendingGroupMemberIdentitiesNew = Set(pendingMembersWithCoreDetails.map { $0.cryptoIdentity })
            guard groupMemberIdentitiesNew.intersection(pendingGroupMemberIdentitiesNew).isEmpty else {
                throw ObvIdentityManagerError.anIdentityAppearsBothWithinPendingMembersAndGroupMembers
            }
        }
        
        // Create a new version of the group members

        let newVersionOfGroupMembers: Set<ContactIdentity> = Set(try groupMembersWithCoreDetails.compactMap { groupMemberWithCoreDetails in
            guard try groupMemberWithCoreDetails.cryptoIdentity != ownedIdentity.cryptoIdentity else { return nil }
            if let contact = try ContactIdentity.get(contactIdentity: groupMemberWithCoreDetails.cryptoIdentity, ownedIdentity: ownedIdentity.cryptoIdentity, within: context) {
                // The identity is already a contact, we simply insert it in the list of group members
                return contact
            } else {
                // The identity is not a contact yet, we create the contact and insert it in the list of group members
                guard let groupOwnerCryptoIdentity = groupOwner.cryptoIdentity else {
                    assertionFailure()
                    throw Self.makeError(message: "Could not get group owner crypto identity")
                }
                let trustOrigin = TrustOrigin.group(timestamp: Date.now, groupOwner: groupOwnerCryptoIdentity)
                guard let contact = ContactIdentity(cryptoIdentity: groupMemberWithCoreDetails.cryptoIdentity,
                                                    identityCoreDetails: groupMemberWithCoreDetails.coreDetails,
                                                    trustOrigin: trustOrigin,
                                                    ownedIdentity: ownedIdentity,
                                                    isKnownToBeOneToOne: false)
                    else {
                        throw ObvIdentityManagerError.contactCreationFailed
                }
                return contact
            }
        })
        
        // Create a new version of the pending group members
        
        let newVersionOfPendingMembers: Set<PendingGroupMember> = Set( try pendingMembersWithCoreDetails.map { (pendingMemberWithCoreDetails) in
            
            if let pendingMember = try PendingGroupMember.get(cryptoIdentity: pendingMemberWithCoreDetails.cryptoIdentity, contactGroup: self) {
                // The identity is already a pending member, we simply insert in the new list of pending members
                return pendingMember
            } else {
                // The identity is not yet a PendingMember, we create it and insert it
                let pendingMember = try PendingGroupMember(contactGroup: self, cryptoIdentityWithCoreDetails: pendingMemberWithCoreDetails)
                return pendingMember
            }
        })
        
        // Replace the old versions of the group members and of the pending members by the new ones and update the version number
        
        try super.updatePendingMembersAndGroupMembers(newVersionOfGroupMembers: newVersionOfGroupMembers,
                                                      newVersionOfPendingMembers: newVersionOfPendingMembers,
                                                      groupMembersVersion: groupMembersVersion)
        
    }
    
    
    /// When a contact deletes here owned identity, we call this method to remove her identity from pending and group members, without waiting for the group owner to update the group. For this reason, we do not check the `groupMembersVersion`.
    func removeContactFromPendingAndGroupMembers(contactCryptoIdentity: ObvCryptoIdentity) throws {
        
        let newVersionOfGroupMembers: Set<ContactIdentity> = groupMembers.filter({ $0.cryptoIdentity != contactCryptoIdentity })
        let newVersionOfPendingMembers: Set<PendingGroupMember> = try pendingGroupMembers.filter({ try $0.cryptoIdentity != contactCryptoIdentity })
        
        try updatePendingMembersAndGroupMembers(
            newVersionOfGroupMembers: newVersionOfGroupMembers,
            newVersionOfPendingMembers: newVersionOfPendingMembers,
            groupMembersVersion: nil)
        
    }
    
}

// MARK: - Convenience methods

extension ContactGroupJoined {
    
    func getPublishedJoinedGroupInformation() throws -> GroupInformation {
        let groupDetailsElements = try publishedDetails.getGroupDetailsElements()
        guard let groupOwnerCryptoIdentity = groupOwner.cryptoIdentity else {
            assertionFailure()
            throw Self.makeError(message: "Could not get group owner crypto identity")
        }
        let groupInformation = try GroupInformation(groupOwnerIdentity: groupOwnerCryptoIdentity,
                                                    groupUid: groupUid,
                                                    groupDetailsElements: groupDetailsElements)
        return groupInformation
    }

    
    func getPublishedJoinedGroupInformationWithPhoto() throws -> GroupInformationWithPhoto {
        let groupInformation = try getPublishedJoinedGroupInformation()
        let photoURL = try publishedDetails.getPhotoURL()
        let groupInformationWithPhoto = GroupInformationWithPhoto(groupInformation: groupInformation,
                                                                  photoURL: photoURL)
        return groupInformationWithPhoto
    }

    
    func getTrustedJoinedGroupInformation() throws -> GroupInformation {
        let groupDetailsElements = try trustedDetails.getGroupDetailsElements()
        guard let groupOwnerCryptoIdentity = groupOwner.cryptoIdentity else {
            assertionFailure()
            throw Self.makeError(message: "Could not get group owner crypto identity")
        }
        let groupInformation = try GroupInformation(groupOwnerIdentity: groupOwnerCryptoIdentity,
                                                    groupUid: groupUid,
                                                    groupDetailsElements: groupDetailsElements)
        return groupInformation
    }

    func getTrustedJoinedGroupInformationWithPhoto() throws -> GroupInformationWithPhoto {
        let groupInformation = try getTrustedJoinedGroupInformation()
        let photoURL = try trustedDetails.getPhotoURL()
        let groupInformationWithPhoto = GroupInformationWithPhoto(groupInformation: groupInformation,
                                                                  photoURL: photoURL)
        return groupInformationWithPhoto
    }


    func trustDetailsPublished(within context: NSManagedObjectContext) throws {
        let groupDetailsElementsWithPhoto = try publishedDetails.getGroupDetailsElementsWithPhoto()
        try self.trustedDetails.delete()
        _ = try ContactGroupDetailsTrusted(contactGroupJoined: self,
                                           groupDetailsElementsWithPhoto: groupDetailsElementsWithPhoto)
        notificationRelatedChanges.insert(.updatedTrustedDetails)
    }

    
    func resetGroupDetailsWithAuthoritativeDetailsIfRequired(_ authoritativeDetailsElements: GroupDetailsElements, within context: NSManagedObjectContext) throws {
        
        let publishedGroupDetailsElementsWithPhoto = try self.publishedDetails.getGroupDetailsElementsWithPhoto()
        guard publishedGroupDetailsElementsWithPhoto.version != authoritativeDetailsElements.version else {
            Self.logger.info("No need to update the (local) published details of contact group joined since they are identical to the received authoritative details")
            return
        }

        Self.logger.info("We received new authoritative details for a group joined, which are distinct from the (local) published details. We update the trusted details version and published details accordingly.")
        
        // If we reach this point, the (local) published details are distinct to the authoritative details.
        // We replace the local (published) details by the ones we just received.
        let currentTrustedDetails = try self.trustedDetails.getGroupDetailsElementsWithPhoto()
        let trustedDetailsWithResetVersionNumber = GroupDetailsElementsWithPhoto(coreDetails: currentTrustedDetails.coreDetails,
                                                                                 version: -1,
                                                                                 photoServerKeyAndLabel: currentTrustedDetails.photoServerKeyAndLabel,
                                                                                 photoURL: currentTrustedDetails.photoURL)
        try self.trustedDetails.delete()
        try self.publishedDetails.delete()
        
        let authoritativeDetailsElementsWithPhoto = GroupDetailsElementsWithPhoto(groupDetailsElements: authoritativeDetailsElements, photoURL: nil)
        _ = try ContactGroupDetailsPublished(contactGroup: self,
                                             groupDetailsElementsWithPhoto: authoritativeDetailsElementsWithPhoto)
        _ = try ContactGroupDetailsTrusted(contactGroupJoined: self,
                                           groupDetailsElementsWithPhoto: trustedDetailsWithResetVersionNumber)

    }
    
    
    func getJoinedGroupStructure() throws -> GroupStructure {
        
        let groupMembers = Set(self.groupMembers.compactMap { $0.cryptoIdentity })
        let pendingGroupMembers = try self.getPendingGroupMembersWithCoreDetails()
        let groupMembersVersion = self.groupMembersVersion
        let publishedGroupDetailsWithPhoto = try self.publishedDetails.getGroupDetailsElementsWithPhoto()
        let trustedGroupDetails = try self.trustedDetails.getGroupDetailsElementsWithPhoto()

        guard let groupOwnerCryptoIdentity = groupOwner.cryptoIdentity else {
            assertionFailure()
            throw Self.makeError(message: "Could not get group owner crypto identity")
        }

        let groupStructure = GroupStructure.createJoinedGroupStructure(
            groupUid: try groupUid,
            publishedGroupDetailsWithPhoto: publishedGroupDetailsWithPhoto,
            trustedGroupDetailsWithPhoto: trustedGroupDetails,
            ownedIdentity: try ownedIdentity.cryptoIdentity,
            groupMembers: groupMembers,
            pendingGroupMembers: pendingGroupMembers,
            groupMembersVersion: groupMembersVersion,
            groupOwner: groupOwnerCryptoIdentity)

        return groupStructure

    }
    
}


// MARK: - Processing sync Atoms

extension ContactGroupJoined {
 
    func processTrustGroupV1DetailsSyncAtom(serializedGroupDetailsElements: Data) throws {
        
        guard let context = self.managedObjectContext else {
            assertionFailure()
            throw ObvIdentityManagerError.contextIsNil
        }
        
        let atomGroupDetailsElements = try GroupDetailsElements(serializedGroupDetailsElements)
        let localPublishedGroupDetailsElements = try self.publishedDetails.getGroupDetailsElements()
        
        // We compare the details that the owned identity trusted on another owned device with the local, published details for the group (without considering versions).
        // If there is a match, we can immediately trust the local published details
        if atomGroupDetailsElements.fieldsAreTheSameButVersionIsNotConsidered(than: localPublishedGroupDetailsElements) {
            try trustDetailsPublished(within: context)
        }
        
    }

}


// MARK: - Convenience DB getters

extension ContactGroupJoined {
    
    struct Predicate {
        enum Key: String {
            case groupOwner = "groupOwner"
            case trustedDetails = "trustedDetails"
        }
        static func withGroupOwnerCryptoIdentity(_ groupOwnerCryptoIdentity: ObvCryptoIdentity) -> NSPredicate {
            let rawKey: String = [
                Key.groupOwner.rawValue,
                ContactIdentity.Predicate.Key.rawIdentity.rawValue,
            ].joined(separator: ".")
            return NSPredicate(rawKey, EqualToData: groupOwnerCryptoIdentity.getIdentity())
        }
        static func withGroupV1Identifier(_ groupV1Identifier: GroupV1Identifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.withGroupOwnerCryptoIdentity(groupV1Identifier.groupOwner.cryptoIdentity),
                ContactGroup.Predicate.withGroupUid(groupV1Identifier.groupUid),
            ])
        }
        static func withGroupIdentifier(_ groupIdentifier: ObvGroupV1Identifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                ContactGroup.Predicate.withOwnedCryptoId(groupIdentifier.ownedCryptoId),
                Self.withGroupV1Identifier(groupIdentifier.groupV1Identifier),
            ])
        }
    }
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<ContactGroupJoined> {
        return NSFetchRequest<ContactGroupJoined>(entityName: entityName)
    }

    static func get(groupUid: UID, groupOwnerCryptoIdentity: ObvCryptoIdentity, ownedIdentity: OwnedIdentity) throws -> ContactGroupJoined? {
        guard let context = ownedIdentity.managedObjectContext else {
            throw ObvIdentityManagerError.contextIsNil
        }
        let request: NSFetchRequest<ContactGroupJoined> = ContactGroupJoined.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            ContactGroup.Predicate.withGroupUid(groupUid),
            Predicate.withGroupOwnerCryptoIdentity(groupOwnerCryptoIdentity),
            ContactGroup.Predicate.withOwnedIdentity(ownedIdentity),
        ])
        request.fetchLimit = 1
        let item = try context.fetch(request).first
        return item
    }
    
    static func getFetchedResultsController(groupIdentifier: ObvGroupV1Identifier, within context: NSManagedObjectContext) -> NSFetchedResultsController<ContactGroupJoined> {
        let request: NSFetchRequest<ContactGroupJoined> = ContactGroupJoined.fetchRequest()
        request.predicate = Self.Predicate.withGroupIdentifier(groupIdentifier)
        request.sortDescriptors = []
        request.fetchLimit = 1
        let frc = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil)
        return frc
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
        
        guard let delegateManager = Self.delegateManager else {
            Self.logger.fault("The delegate manager is not set (2)")
            assertionFailure()
            return
        }
        
        // We do not send any notification after inserting an object during a snapshot restore or a backup restore
        guard !isInsertedWhileRestoringSyncSnapshotOrBackup else { assert(isInserted); return }

        if notificationRelatedChanges.contains(.updatedTrustedDetails), let groupOwnerCryptoIdentity = groupOwner.cryptoIdentity {
            
            do {
                let NotificationType = ObvIdentityNotification.ContactGroupJoinedHasUpdatedTrustedDetails.self
                let userInfo = [NotificationType.Key.groupUid: try self.groupUid,
                                NotificationType.Key.groupOwner: groupOwnerCryptoIdentity,
                                NotificationType.Key.ownedIdentity: try self.ownedIdentity.cryptoIdentity] as [String: Any]
                delegateManager.notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
            } catch {
                assertionFailure()
            }
            
        }
        
    }
    
}


// MARK: - For Backup purposes

extension ContactGroupJoined {
    
    var backupItem: ContactGroupJoinedBackupItem {
        get throws {
            return try ContactGroupJoinedBackupItem(groupMembersVersion: groupMembersVersion,
                                                    groupUid: try groupUid,
                                                    groupMembers: groupMembers,
                                                    pendingGroupMembers: pendingGroupMembers,
                                                    publishedDetails: publishedDetails,
                                                    trustedDetails: trustedDetails)
        }
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

    fileprivate init(groupMembersVersion: Int, groupUid: UID, groupMembers: Set<ContactIdentity>, pendingGroupMembers: Set<PendingGroupMember>, publishedDetails: ContactGroupDetailsPublished, trustedDetails: ContactGroupDetailsTrusted) throws {
        self.groupMembersVersion = groupMembersVersion
        self.groupUid = groupUid
        self.groupMembers = Set(groupMembers.compactMap {
            guard let memberIdentity = $0.cryptoIdentity?.getIdentity() else { assertionFailure(); return nil }
            return GroupMemberBackupItem(memberIdentity: memberIdentity)
        })
        self.pendingGroupMembers = try Set(pendingGroupMembers.map { try $0.backupItem })
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
 
    func restoreInstance(within context: NSManagedObjectContext, associations: inout BackupItemObjectAssociations) throws {
        let contactGroupJoined = ContactGroupJoined(backupItem: self, within: context)
        try associations.associate(contactGroupJoined, to: self)
        _ = try pendingGroupMembers.map { try $0.restoreInstance(within: context, associations: &associations) }
        guard let publishedDetailsBackupItem = self.publishedDetails else {
            throw ContactGroupJoinedBackupItem.makeError(message: "self.publishedDetails must be non-nil at this point")
        }
        try publishedDetailsBackupItem.restoreContactGroupDetailsPublishedInstance(within: context, associations: &associations)
        try trustedDetails.restoreContactGroupDetailsTrustedInstance(within: context, associations: &associations)
    }
    
    func restoreRelationships(associations: BackupItemObjectAssociations, within context: NSManagedObjectContext) throws {
        let contactGroupJoined: ContactGroupJoined = try associations.getObject(associatedTo: self, within: context)
        // Restore the relationships of this instance
        let trustedDetails: ContactGroupDetailsTrusted = try associations.getObject(associatedTo: self.trustedDetails, within: context)
        
        var groupMembers = Set<ContactIdentity>()
        do {
            let allContacts = context.registeredObjects.filter({ $0 is ContactIdentity }) as! Set<ContactIdentity>
            for groupMember in self.groupMembers {
                guard let groupMemberAsContact = allContacts.first(where: { $0.cryptoIdentity?.getIdentity() == groupMember.memberIdentity }) else {
                    throw ContactGroupJoinedBackupItem.makeError(message: "Could not find the contact identity instance corresponding to the group member")
                }
                groupMembers.insert(groupMemberAsContact)
            }
            guard groupMembers.count == self.groupMembers.count else {
                throw ContactGroupJoinedBackupItem.makeError(message: "Unexpected number of group members")
            }
        }
        
        let pendingGroupMembers: Set<PendingGroupMember> = Set(try self.pendingGroupMembers.map({ try associations.getObject(associatedTo: $0, within: context) }))
        guard let publishedDetailsBackupItem = self.publishedDetails else {
            throw ContactGroupJoinedBackupItem.makeError(message: "self.publishedDetails must be non-nil at this point")
        }
        let publishedDetails: ContactGroupDetailsPublished = try associations.getObject(associatedTo: publishedDetailsBackupItem, within: context)
        contactGroupJoined.restoreRelationshipsOfContactGroupJoined(trustedDetails: trustedDetails,
                                                                    groupMembers: groupMembers,
                                                                    pendingGroupMembers: pendingGroupMembers,
                                                                    publishedDetails: publishedDetails)
        // Restore the relationships with this instance relationships
        _ = try self.pendingGroupMembers.map({ try $0.restoreRelationships(associations: associations, within: context) })
        try publishedDetailsBackupItem.restoreRelationships(associations: associations, within: context)
        try self.trustedDetails.restoreRelationships(associations: associations, within: context)
    }

}
