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


@objc(ContactGroupOwned)
final class ContactGroupOwned: ContactGroup {
    
    // MARK: Internal constants
    
    private static let entityName = "ContactGroupOwned"
    private static let errorDomain = String(describing: ContactGroupOwned.self)
    private static var logSubsystem: String { delegateManager?.logSubsystem ?? ObvIdentityDelegateManager.defaultLogSubsystem }
    private static var logger: Logger = { Logger(subsystem: ContactGroupOwned.logSubsystem, category: "ContactGroupOwned") }()

    // MARK: Relationships
    
    @NSManaged private(set) var latestDetails: ContactGroupDetailsLatest
    
    // MARK: Other variables
    
    private var notificationRelatedChanges: NotificationRelatedChanges = []
    
    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { ContactGroupOwned.makeError(message: message) }

    // MARK: - Initializer
    
    convenience init(groupInformationWithPhoto: GroupInformationWithPhoto, ownedIdentity: ObvCryptoIdentity, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>, within context: NSManagedObjectContext) throws {
        
        guard groupInformationWithPhoto.groupOwnerIdentity == ownedIdentity else {
            throw ObvIdentityManagerError.inappropriateGroupInformation
        }
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, within: context) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned
        }
        
        guard try ContactGroupOwned.get(groupUid: groupInformationWithPhoto.groupUid, ownedIdentity: ownedIdentityObject) == nil else {
            throw ObvIdentityManagerError.tryingToCreateContactGroupThatAlreadyExists
        }
        
        try self.init(groupInformationWithPhoto: groupInformationWithPhoto,
                      ownedIdentity: ownedIdentityObject,
                      groupMembers: Set<ObvCryptoIdentity>(), // No members yet when creating an owned group
                      pendingGroupMembers: pendingGroupMembers,
                      forEntityName: ContactGroupOwned.entityName)

        self.latestDetails = try ContactGroupDetailsLatest(
            contactGroupOwned: self,
            groupDetailsElementsWithPhoto: groupInformationWithPhoto.groupDetailsElementsWithPhoto)
        
    }

    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreater in a second step
    fileprivate convenience init(backupItem: ContactGroupOwnedBackupItem, within context: NSManagedObjectContext) {
        self.init(groupMembersVersion: backupItem.groupMembersVersion,
                  groupUid: backupItem.groupUid,
                  forEntityName: ContactGroupOwned.entityName,
                  within: context)
    }
    
    
    func restoreRelationshipsOfContactGroupOwned(latestDetails: ContactGroupDetailsLatest, groupMembers: Set<ContactIdentity>, pendingGroupMembers: Set<PendingGroupMember>, publishedDetails: ContactGroupDetailsPublished) {
        self.latestDetails = latestDetails
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
                  forEntityName: ContactGroupOwned.entityName,
                  within: context)
    }



    func updatePhoto(withData photoData: Data, ofDetailsWithVersion version: Int, within context: NSManagedObjectContext) throws {
        if self.publishedDetails.version == version {
            try self.publishedDetails.setGroupPhoto(data: photoData)
        }
        if self.latestDetails.version == version {
            try self.latestDetails.setGroupPhoto(data: photoData)
        }
    }
    
    
    func delete() throws {
        guard let context = self.managedObjectContext else { throw Self.makeError(message: "Could not find context") }
        try latestDetails.delete()
        try publishedDetails.delete()
        // Pending group members are cascade deleted
        context.delete(self)
    }

}


// MARK: - Updating the pending and group members

extension ContactGroupOwned {
    
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
        
        let newVersionOfGroupMembers: Set<ContactIdentity> = Set( try groupMembersWithCoreDetails.compactMap { (groupMemberWithCoreDetails) in
            guard try groupMemberWithCoreDetails.cryptoIdentity != ownedIdentity.cryptoIdentity else { return nil }
            if let contact = try ContactIdentity.get(contactIdentity: groupMemberWithCoreDetails.cryptoIdentity, ownedIdentity: ownedIdentity.cryptoIdentity, within: context) {
                // The identity is already a contact, we simply insert it in the list of group members
                return contact
            } else {
                let trustOrigin = TrustOrigin.group(timestamp: Date.now, groupOwner: try ownedIdentity.cryptoIdentity)
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
    
}


// MARK: - Convenience methods

extension ContactGroupOwned {

    func getPublishedOwnedGroupInformation() throws -> GroupInformation {
        let groupDetailsElements = try publishedDetails.getGroupDetailsElements()
        let groupInformation = try GroupInformation(groupOwnerIdentity: ownedIdentity.cryptoIdentity,
                                                    groupUid: groupUid,
                                                    groupDetailsElements: groupDetailsElements)
        return groupInformation
    }

    
    func getPublishedOwnedGroupInformationWithPhoto() throws -> GroupInformationWithPhoto {
        let groupInformation = try getPublishedOwnedGroupInformation()
        let photoURL = try publishedDetails.getPhotoURL()
        let groupInformationWithPhoto = GroupInformationWithPhoto(groupInformation: groupInformation,
                                                                  photoURL: photoURL)
        return groupInformationWithPhoto
    }
    
    
    func updateDetailsLatest(with groupDetailsElementsWithPhoto: GroupDetailsElementsWithPhoto) throws {
        guard groupDetailsElementsWithPhoto.version >= 1 + publishedDetails.version else {
            throw ObvIdentityManagerError.invalidGroupDetailsVersion
        }
        try self.latestDetails.delete()
        self.latestDetails = try ContactGroupDetailsLatest(contactGroupOwned: self,
                                                           groupDetailsElementsWithPhoto: groupDetailsElementsWithPhoto)
        notificationRelatedChanges.insert(.updatedLatestDetails)
    }
    
    
    func discardDetailsLatest() throws {
        try self.latestDetails.delete()
        let groupDetailsElementsWithPhoto = try publishedDetails.getGroupDetailsElementsWithPhoto()
        self.latestDetails = try ContactGroupDetailsLatest(contactGroupOwned: self,
                                                           groupDetailsElementsWithPhoto: groupDetailsElementsWithPhoto)
        notificationRelatedChanges.insert(.discardedLatestDetails)
    }
    
    
    func publishDetailsLatest() throws {
        let groupDetailsElementsWithPhoto = try latestDetails.getGroupDetailsElementsWithPhoto()
        try super.updateDetailsPublished(with: groupDetailsElementsWithPhoto.groupDetailsElements)
        try publishedDetails.setGroupPhoto(with: groupDetailsElementsWithPhoto.photoURL)
    }
    
    
    func getDeclinedPendingGroupMembersWithCoreDetails() -> Set<ObvCryptoIdentity> {
        
        let declinedPendingGroupMembers = pendingGroupMembers.filter { $0.declined }
        
        let declinedPendingGroupMembersWithCoreDetails = declinedPendingGroupMembers.compactMap { try? $0.cryptoIdentity }
        
        return Set(declinedPendingGroupMembersWithCoreDetails)
    }

    
    func getOwnedGroupStructure() throws -> GroupStructure {
        
        let groupMembers = Set(self.groupMembers.compactMap { $0.cryptoIdentity })
        let pendingGroupMembers = try self.getPendingGroupMembersWithCoreDetails()
        let groupMembersVersion = self.groupMembersVersion
        let publishedGroupDetailsWithPhoto = try self.publishedDetails.getGroupDetailsElementsWithPhoto()
        
        let latestGroupDetailsWithPhoto = try self.latestDetails.getGroupDetailsElementsWithPhoto()
        let declinedPendingGroupMembers = self.getDeclinedPendingGroupMembersWithCoreDetails()
        let groupStructure = try GroupStructure.createOwnedGroupStructure(
            groupUid: groupUid,
            publishedGroupDetailsWithPhoto: publishedGroupDetailsWithPhoto,
            latestGroupDetailsWithPhoto: latestGroupDetailsWithPhoto,
            ownedIdentity: ownedIdentity.cryptoIdentity,
            groupMembers: groupMembers,
            pendingGroupMembers: pendingGroupMembers,
            declinedPendingGroupMembers: declinedPendingGroupMembers,
            groupMembersVersion: groupMembersVersion)
        
        return groupStructure
        
    }


}


// MARK: - Managing group members

extension ContactGroupOwned {

    func markPendingMemberAsDeclined(pendingGroupMember: ObvCryptoIdentity) throws {
        
        guard let pendingGroupMemberObject = try self.pendingGroupMembers.filter({ try $0.cryptoIdentity == pendingGroupMember }).first else {
            throw ObvIdentityManagerError.pendingGroupMemberDoesNotExist
        }
        
        pendingGroupMemberObject.markAsDeclined()
        
    }
    
    
    func unmarkDeclinedPendingMemberAsDeclined(pendingGroupMember: ObvCryptoIdentity) throws {
        
        guard let pendingGroupMemberObject = try self.pendingGroupMembers.filter({ try $0.cryptoIdentity == pendingGroupMember }).first else {
            throw ObvIdentityManagerError.pendingGroupMemberDoesNotExist
        }
        
        pendingGroupMemberObject.unmarkAsDeclined()
        
    }

    
    func add(newPendingMembers: Set<ObvCryptoIdentity>) throws {
        
        guard let context = self.managedObjectContext else {
            throw ObvIdentityManagerError.contextIsNil
        }
        
        // Filter out the "new" pending members that are already pending members. Also filter out the members.
        let cryptoIdentitiesOfCurrentPendingMembers = try Set(self.pendingGroupMembers.map { try $0.cryptoIdentity })
        let cryptoIdentitiesOfCurrentMembers = Set(self.groupMembers.compactMap { $0.cryptoIdentity })
        let reallyNewPendingMembers = newPendingMembers.subtracting(cryptoIdentitiesOfCurrentPendingMembers).subtracting(cryptoIdentitiesOfCurrentMembers)
        guard !reallyNewPendingMembers.isEmpty else { return }
        
        // Make sure the new pending members are indeed contacts of the owned identity
        let newPendingMemberIdentities: Set<ContactIdentity> = Set(try reallyNewPendingMembers.map { (cryptoIdentity) in
            guard let contact = try ContactIdentity.get(contactIdentity: cryptoIdentity,
                                                        ownedIdentity: self.ownedIdentity.cryptoIdentity,
                                                        within: context)
            else {
                    throw ObvIdentityManagerError.cryptoIdentityIsNotContact
            }
            return contact
            })
        
        let reallyNewPendingMemberObjects: Set<PendingGroupMember> = Set( try newPendingMemberIdentities.compactMap { (contact) in
            let publishedCoreDetails = try contact.publishedIdentityDetails?.getIdentityDetails().coreDetails
            guard let trustedCoreDetails = try contact.trustedIdentityDetails?.getIdentityDetails().coreDetails else {
                throw Self.makeError(message: "Could not get the trusted details of a contact")
            }
            let coreDetails = publishedCoreDetails ?? trustedCoreDetails
            guard let contactCryptoIdentity = contact.cryptoIdentity else { assertionFailure(); return nil }
            let cryptoIdentityWithCoreDetails = CryptoIdentityWithCoreDetails(cryptoIdentity: contactCryptoIdentity,
                                                                              coreDetails: coreDetails)
            return try PendingGroupMember(contactGroup: self,
                                          cryptoIdentityWithCoreDetails: cryptoIdentityWithCoreDetails)
            }
        )
        
        let newVersionOfGroupMembers = self.groupMembers // Does not change
        let newVersionOfPendingMembers = self.pendingGroupMembers.union(reallyNewPendingMemberObjects)
        let newGroupMembersVersion = self.groupMembersVersion + 1
        
        // Replace the old versions of the group members and of the pending members by the new ones and update the version number
        
        try super.updatePendingMembersAndGroupMembers(newVersionOfGroupMembers: newVersionOfGroupMembers,
                                                      newVersionOfPendingMembers: newVersionOfPendingMembers,
                                                      groupMembersVersion: newGroupMembersVersion)

    }
    
    
    func remove(pendingOrGroupMembers: Set<ObvCryptoIdentity>) throws {
        
        let groupMembersToRemove = Set(self.groupMembers.filter {
            guard let cryptoIdentity = $0.cryptoIdentity else { assertionFailure(); return false }
            return pendingOrGroupMembers.contains(cryptoIdentity)
        })
        let pendingMembersToRemove = try Set(self.pendingGroupMembers.filter { pendingOrGroupMembers.contains(try $0.cryptoIdentity) })
        
        let newVersionOfGroupMembers = self.groupMembers.subtracting(groupMembersToRemove)
        let newVersionOfPendingMembers = self.pendingGroupMembers.subtracting(pendingMembersToRemove)
        let newGroupMembersVersion = self.groupMembersVersion + 1
        
        // Replace the old versions of the group members and of the pending members by the new ones and update the version number
        
        try super.updatePendingMembersAndGroupMembers(newVersionOfGroupMembers: newVersionOfGroupMembers,
                                                      newVersionOfPendingMembers: newVersionOfPendingMembers,
                                                      groupMembersVersion: newGroupMembersVersion)

    }
}


// MARK: - Convenience DB getters

extension ContactGroupOwned {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<ContactGroupOwned> {
        return NSFetchRequest<ContactGroupOwned>(entityName: entityName)
    }
    
    private struct Predicate {
        enum Key: String {
            case latestDetails = "latestDetails"
        }
    }
    
    static func get(groupUid: UID, ownedIdentity: OwnedIdentity) throws -> ContactGroupOwned? {
        guard let context = ownedIdentity.managedObjectContext else {
            throw ObvIdentityManagerError.contextIsNil
        }
        let request: NSFetchRequest<ContactGroupOwned> = ContactGroupOwned.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            ContactGroup.Predicate.withGroupUid(groupUid),
            ContactGroup.Predicate.withOwnedIdentity(ownedIdentity),
        ])
        request.fetchLimit = 1
        let item = try context.fetch(request).first
        return item
    }

    
    static func getAllContactGroupOwned(ownedIdentity: OwnedIdentity) throws -> Set<ContactGroupOwned> {
        guard let context = ownedIdentity.managedObjectContext else { throw makeError(message: "An context is not set on an owned identity") }
        let request: NSFetchRequest<ContactGroupOwned> = ContactGroupOwned.fetchRequest()
        request.predicate = ContactGroup.Predicate.withOwnedIdentity(ownedIdentity)
        request.fetchBatchSize = 1_000
        let items = try context.fetch(request)
        return Set(items)
    }
}


// MARK: - Sending notifications

extension ContactGroupOwned {
    
    private struct NotificationRelatedChanges: OptionSet {
        let rawValue: UInt8
        static let updatedLatestDetails = NotificationRelatedChanges(rawValue: 1 << 0)
        static let discardedLatestDetails = NotificationRelatedChanges(rawValue: 1 << 1)
    }

    override func didSave() {
        super.didSave()
        
        guard let delegateManager = Self.delegateManager else {
            Self.logger.fault("The delegate manager is not set (2)")
            return
        }

        // We do not send any notification after inserting an object during a snapshot restore or a backup restore
        guard !isInsertedWhileRestoringSyncSnapshotOrBackup else { assert(isInserted); return }

        if notificationRelatedChanges.contains(.updatedLatestDetails) {
            
            do {
                let NotificationType = ObvIdentityNotification.ContactGroupOwnedHasUpdatedLatestDetails.self
                let userInfo = [NotificationType.Key.groupUid: try self.groupUid,
                                NotificationType.Key.ownedIdentity: try self.ownedIdentity.cryptoIdentity] as [String: Any]
                delegateManager.notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
            } catch {
                assertionFailure()
            }

        }
        
        if notificationRelatedChanges.contains(.discardedLatestDetails) {
            
            do {
                let NotificationType = ObvIdentityNotification.ContactGroupOwnedDiscardedLatestDetails.self
                let userInfo = [NotificationType.Key.groupUid: try self.groupUid,
                                NotificationType.Key.ownedIdentity: try self.ownedIdentity.cryptoIdentity] as [String: Any]
                delegateManager.notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
            } catch {
                assertionFailure()
            }

        }
        
        notificationRelatedChanges = []
    }
    
}


// MARK: - For Backup purposes

extension ContactGroupOwned {
    
    var backupItem: ContactGroupOwnedBackupItem {
        get throws {
            return try ContactGroupOwnedBackupItem(groupMembersVersion: groupMembersVersion,
                                                   groupUid: try groupUid,
                                                   groupMembers: groupMembers,
                                                   pendingGroupMembers: pendingGroupMembers,
                                                   publishedDetails: publishedDetails,
                                                   latestDetails: latestDetails)
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

struct ContactGroupOwnedBackupItem: Codable, Hashable {
    
    // Inherited from ContactGroup
    fileprivate let groupMembersVersion: Int
    fileprivate let groupUid: UID
    fileprivate let groupMembers: Set<GroupMemberBackupItem>
    fileprivate let pendingGroupMembers: Set<PendingGroupMemberBackupItem>
    fileprivate let publishedDetails: ContactGroupDetailsBackupItem
    // Local
    fileprivate let latestDetails: ContactGroupDetailsBackupItem?
    
    private static let errorDomain = String(describing: Self.self)

    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    fileprivate init(groupMembersVersion: Int, groupUid: UID, groupMembers: Set<ContactIdentity>, pendingGroupMembers: Set<PendingGroupMember>, publishedDetails: ContactGroupDetailsPublished, latestDetails: ContactGroupDetailsLatest) throws {
        self.groupMembersVersion = groupMembersVersion
        self.groupUid = groupUid
        self.groupMembers = Set(groupMembers.map({ GroupMemberBackupItem(memberIdentity: $0.identity) }))
        self.pendingGroupMembers = try Set(pendingGroupMembers.map { try $0.backupItem })
        self.publishedDetails = publishedDetails.backupItem
        // If the latest details are identical to the published details, we do not include them in the json file
        if publishedDetails.version == latestDetails.version {
            self.latestDetails = nil
        } else {
            self.latestDetails = latestDetails.backupItem
        }
    }
    
    
    enum CodingKeys: String, CodingKey {
        // Inherited from ContactGroup
        case groupMembersVersion = "group_members_version"
        case groupUid = "group_uid"
        case groupMembers = "members"
        case pendingGroupMembers = "pending_members"
        case publishedDetails = "published_details"
        // Local
        case latestDetails = "latest_details"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Inherited from ContactGroup
        try container.encode(groupMembersVersion, forKey: .groupMembersVersion)
        try container.encode(groupUid.raw, forKey: .groupUid)
        try container.encode(groupMembers, forKey: .groupMembers)
        try container.encode(pendingGroupMembers, forKey: .pendingGroupMembers)
        try container.encode(publishedDetails, forKey: .publishedDetails)
        try container.encodeIfPresent(latestDetails, forKey: .latestDetails)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.groupMembersVersion = try values.decode(Int.self, forKey: .groupMembersVersion)
        let groupUidRaw = try values.decode(Data.self, forKey: .groupUid)
        guard let groupUid = UID(uid: groupUidRaw) else {
            throw ContactGroupOwnedBackupItem.makeError(message: "Could get group uid")
        }
        self.groupUid = groupUid
        self.pendingGroupMembers = try values.decode(Set<PendingGroupMemberBackupItem>.self, forKey: .pendingGroupMembers)
        self.groupMembers = try values.decode(Set<GroupMemberBackupItem>.self, forKey: .groupMembers)
        let publishedDetails = try values.decode(ContactGroupDetailsBackupItem.self, forKey: .publishedDetails)
        self.publishedDetails = publishedDetails
        // We ensure that latestDetails are non nil, since this is required by the database
        // If we cannot find latestDetails details in the json, we use the publishedDetails instead.
        self.latestDetails = try values.decodeIfPresent(ContactGroupDetailsBackupItem.self, forKey: .latestDetails) ?? publishedDetails.duplicate()
    }

    func restoreInstance(within context: NSManagedObjectContext, associations: inout BackupItemObjectAssociations) throws {
        let contactGroupOwned = ContactGroupOwned(backupItem: self, within: context)
        try associations.associate(contactGroupOwned, to: self)
        _ = try pendingGroupMembers.map { try $0.restoreInstance(within: context, associations: &associations) }
        try publishedDetails.restoreContactGroupDetailsPublishedInstance(within: context, associations: &associations)
        // If there is no latest details in the json, we use the published details instead
        guard let latestDetailsBackupItem = self.latestDetails else {
            throw ContactGroupOwnedBackupItem.makeError(message: "self.latestDetails is expected to be non-nil at this point")
        }
        try latestDetailsBackupItem.restoreContactGroupDetailsLatestInstance(within: context, associations: &associations)
    }

    func restoreRelationships(associations: BackupItemObjectAssociations, within context: NSManagedObjectContext) throws {
        let contactGroupOwned: ContactGroupOwned = try associations.getObject(associatedTo: self, within: context)
        
        // Restore the relationships of this instance
        
        guard let latestDetailsBackupItem = self.latestDetails else {
            throw ContactGroupOwnedBackupItem.makeError(message: "self.latestDetails is expected to be non-nil at this point")
        }
        let latestDetails: ContactGroupDetailsLatest = try associations.getObject(associatedTo: latestDetailsBackupItem, within: context)
        
        var groupMembers = Set<ContactIdentity>()
        do {
            let allContacts = context.registeredObjects.filter({ $0 is ContactIdentity }) as! Set<ContactIdentity>
            for groupMember in self.groupMembers {
                guard let groupMemberAsContact = allContacts.first(where: { $0.identity == groupMember.memberIdentity }) else {
                    throw ContactGroupOwnedBackupItem.makeError(message: "Could not find the contact identity instance corresponding to the group member")
                }
                groupMembers.insert(groupMemberAsContact)
            }
            guard groupMembers.count == self.groupMembers.count else {
                throw ContactGroupOwnedBackupItem.makeError(message: "Unexpected number of group members")
            }
        }
        
        let pendingGroupMembers: Set<PendingGroupMember> = Set(try self.pendingGroupMembers.map({ try associations.getObject(associatedTo: $0, within: context) }))
        let publishedDetails: ContactGroupDetailsPublished = try associations.getObject(associatedTo: self.publishedDetails, within: context)
        contactGroupOwned.restoreRelationshipsOfContactGroupOwned(latestDetails: latestDetails,
                                                                  groupMembers: groupMembers,
                                                                  pendingGroupMembers: pendingGroupMembers,
                                                                  publishedDetails: publishedDetails)
        
        // Restore the relationships of this instance relationships
        
        _ = try self.pendingGroupMembers.map({ try $0.restoreRelationships(associations: associations, within: context) })
        try self.publishedDetails.restoreRelationships(associations: associations, within: context)
        try self.latestDetails?.restoreRelationships(associations: associations, within: context)

    }

}
