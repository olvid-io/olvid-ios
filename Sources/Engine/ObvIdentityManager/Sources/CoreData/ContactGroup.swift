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
@preconcurrency import ObvCrypto
import ObvMetaManager
import OlvidUtils

@objc(ContactGroup)
class ContactGroup: NSManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "ContactGroup"
    private static let errorDomain = String(describing: ContactGroup.self)

    private static func makeError(message: String) -> Error { NSError(domain: errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { Self.makeError(message: message) }

    static weak var delegateManager: ObvIdentityDelegateManager?
    
    private static var logSubsystem: String { delegateManager?.logSubsystem ?? ObvIdentityDelegateManager.defaultLogSubsystem }
    private static var logger: Logger = { Logger(subsystem: ContactGroup.logSubsystem, category: "ContactGroup") }()

    // MARK: Attributes
    
    @NSManaged private(set) var groupMembersVersion: Int
    @NSManaged private(set) var rawGroupUid: Data? // Primary key, non-optional in the model, raw value of an UID
    
    // MARK: Relationships
    
    @NSManaged private(set) var groupMembers: Set<ContactIdentity>
    @NSManaged private(set) var ownedIdentity: OwnedIdentity
    @NSManaged private(set) var pendingGroupMembers: Set<PendingGroupMember>
    @NSManaged private(set) var publishedDetails: ContactGroupDetailsPublished // Shall *not* be set outside of the subclasses of this class.

    // MARK: Other variables
    
    var groupUid: UID {
        get throws(ObvError) {
            guard let rawGroupUid else { assertionFailure(); throw .unexpectedNilValue }
            guard let groupUid = UID(uid: rawGroupUid) else { assertionFailure(); throw .couldNotParseValue }
            return groupUid
        }
    }
    
    private var ownedIdentityCryptoIdentityOnDeletion: ObvCryptoIdentity?
    private var groupOwnerCryptoIdentityOnDeletion: ObvCryptoIdentity?
    private var groupUidOnDeletion: UID?
    private var notificationRelatedChanges: NotificationRelatedChanges = []
    private var labelToDelete: UID?
    private var changedKeys = Set<String>()

    private(set) var isInsertedWhileRestoringSyncSnapshotOrBackup = false

    // MARK: - Initializer
    
    /// This initializer shall only be called from the intializer of one of concrete subclasses of `ContactGroup`.
    ///
    convenience init(groupInformationWithPhoto: GroupInformationWithPhoto, ownedIdentity: OwnedIdentity, groupMembers: Set<ObvCryptoIdentity>, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>, forEntityName entityName: String) throws {
        
        guard let context = ownedIdentity.managedObjectContext else {
            throw ObvIdentityManagerError.contextIsNil
        }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        self.rawGroupUid = groupInformationWithPhoto.groupUid.raw
        self.groupMembersVersion = 0
        
        self.groupMembers = Set<ContactIdentity>()
        for groupMember in groupMembers {
            guard let contact = try ContactIdentity.get(contactIdentity: groupMember, ownedIdentity: ownedIdentity.cryptoIdentity, within: context) else {
                throw ObvIdentityManagerError.cryptoIdentityIsNotContact
            }
            self.groupMembers.insert(contact)
        }
        self.ownedIdentity = ownedIdentity
        self.pendingGroupMembers = Set(try pendingGroupMembers.map { try PendingGroupMember(contactGroup: self, cryptoIdentityWithCoreDetails: $0) })
        let groupDetailsElementsWithPhoto = groupInformationWithPhoto.groupDetailsElementsWithPhoto
        self.publishedDetails = try ContactGroupDetailsPublished(contactGroup: self,
                                                                 groupDetailsElementsWithPhoto: groupDetailsElementsWithPhoto)
                
    }
    
    
    /// Used *exclusively* during a backup restore or a snapshot restore for creating an instance, relatioships are recreater in a second step
    convenience init(groupMembersVersion: Int, groupUid: UID, forEntityName entityName: String, within context: NSManagedObjectContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.groupMembersVersion = groupMembersVersion
        self.rawGroupUid = groupUid.raw
        self.isInsertedWhileRestoringSyncSnapshotOrBackup = true
    }
    
    func restoreRelationshipsOfContactGroup(groupMembers: Set<ContactIdentity>, pendingGroupMembers: Set<PendingGroupMember>, publishedDetails: ContactGroupDetailsPublished) {
        self.groupMembers = groupMembers
        /* ownedIdentity is set in OwnedIdentity  */
        self.pendingGroupMembers = pendingGroupMembers
        self.publishedDetails = publishedDetails
    }
    
    
    // MARK: - Observers
    
    private static var observersHolder = ObserversHolder()
    
    static func addObvObserver(_ newObserver: ContactGroupObserver) async {
        await observersHolder.addObserver(newObserver)
    }

}


// MARK: - Errors

extension ContactGroup {
    
    enum ObvError: Error {
        case unexpectedNilValue
        case couldNotParseValue
    }
    
}

// MARK: - Convenience methods

extension ContactGroup {
    
    func getPendingGroupMembersWithCoreDetails() throws -> Set<CryptoIdentityWithCoreDetails> {
        
        let pendingGroupMembersWithCoreDetails = try pendingGroupMembers.map {
            return CryptoIdentityWithCoreDetails(cryptoIdentity: try $0.cryptoIdentity, coreDetails: $0.identityCoreDetails)
        }
        
        return Set(pendingGroupMembersWithCoreDetails)
    }
    
    // This method is used both for joined and owned contact groups
    func updateDetailsPublished(with groupDetailsElements: GroupDetailsElements) throws {

        if groupDetailsElements.version <= self.publishedDetails.version { return }
        
        guard groupDetailsElements.version > self.publishedDetails.version else {
            throw ObvIdentityManagerError.invalidGroupDetailsVersion
        }
        
        let oldPublishedDetails = self.publishedDetails
        let groupDetailsElementsWithPhoto: GroupDetailsElementsWithPhoto
        if oldPublishedDetails.photoServerKeyAndLabel == groupDetailsElements.photoServerKeyAndLabel {
            self.labelToDelete = nil
            if oldPublishedDetails.photoServerKeyAndLabel == nil {
                groupDetailsElementsWithPhoto = GroupDetailsElementsWithPhoto(groupDetailsElements: groupDetailsElements, photoURL: nil)
            } else {
                let photoURL = try publishedDetails.getPhotoURL()
                groupDetailsElementsWithPhoto = GroupDetailsElementsWithPhoto(groupDetailsElements: groupDetailsElements, photoURL: photoURL)
            }
        } else {
            self.labelToDelete = oldPublishedDetails.photoServerLabel
            groupDetailsElementsWithPhoto = GroupDetailsElementsWithPhoto(groupDetailsElements: groupDetailsElements, photoURL: nil)
        }
        self.publishedDetails = try ContactGroupDetailsPublished(contactGroup: self,
                                                                 groupDetailsElementsWithPhoto: groupDetailsElementsWithPhoto)
        try oldPublishedDetails.delete()

        notificationRelatedChanges.insert(.publishedDetails)

    }
    
    
    func getGroupStructure() throws -> GroupStructure {
        if let ownedGroup = self as? ContactGroupOwned {
            return try ownedGroup.getOwnedGroupStructure()
        } else if let joinedGroup = self as? ContactGroupJoined {
            return try joinedGroup.getJoinedGroupStructure()
        } else {
            throw makeError(message: "Unknown ContactGroup subclass. This is a bug.")
        }
    }

    
    func getPublishedGroupInformation() throws -> GroupInformation {
        if let ownedGroup = self as? ContactGroupOwned {
            return try ownedGroup.getPublishedOwnedGroupInformation()
        } else if let joinedGroup = self as? ContactGroupJoined {
            return try joinedGroup.getPublishedJoinedGroupInformation()
        } else {
            throw makeError(message: "Unknown ContactGroup subclass. This is a bug.")
        }
    }

}

// MARK: - Managing pending members and group members

extension ContactGroup {
    
    
    func resetGroupMembersVersionOfContactGroupJoined() throws {
        guard self is ContactGroupJoined else {
            throw ObvIdentityManagerError.groupIsNotJoined
        }
        self.groupMembersVersion = 0
    }
    
    
    func transferPendingMemberToGroupMembersForGroupOwned(contactIdentity: ContactIdentity) throws {
        
        guard self is ContactGroupOwned else {
            throw ObvIdentityManagerError.groupIsNotOwned
        }

        guard self.managedObjectContext == contactIdentity.managedObjectContext else {
            throw ObvIdentityManagerError.contextMismatch
        }
        
        guard let context = self.managedObjectContext else {
            throw ObvIdentityManagerError.contextIsNil
        }

        // Remove the pending member from the list of pending group members
        
        if let pendingMemberObject = try self.pendingGroupMembers.filter({ try $0.cryptoIdentity == contactIdentity.cryptoIdentity }).first {
            self.pendingGroupMembers.remove(pendingMemberObject)
            context.delete(pendingMemberObject)
        }

        // Add this contact to the group members
        self.groupMembers.insert(contactIdentity)
        
        // Increment the group members version (note that self is an instance of ContactGroupOwned)
        self.groupMembersVersion += 1
        
        notificationRelatedChanges.insert(.pendingMembersAndGroupMembers)
    }
    
    func transferGroupMemberToPendingMembersForGroupOwned(contactCryptoIdentity: ObvCryptoIdentity) throws {
        
        guard self is ContactGroupOwned else {
            throw ObvIdentityManagerError.groupIsNotOwned
        }

        // Remove the group member from the list of group members
        
        if let contactIdentityObject = self.groupMembers.filter({ $0.cryptoIdentity == contactCryptoIdentity }).first {
            self.groupMembers.remove(contactIdentityObject)
            // We do *not* delete the contact, we only want to remove her from the group
        }
        
        // Add this contact to the pending members (note that this call increments the members version)

        try (self as! ContactGroupOwned).add(newPendingMembers: Set([contactCryptoIdentity]))
        
        notificationRelatedChanges.insert(.pendingMembersAndGroupMembers)

    }
    
    
    /// Method called from both `ContactGroupJoined` and `ContactGroupOwned`.
    ///
    /// If `groupMembersVersion` is `nil`, the change is enforced without checking if the new group member version is strictly larger than the current one.
    /// Setting this value to `nil` allows to remove a contact after she deleted her owned identiy, without waiting for the group owner to remove her from the group.
    func updatePendingMembersAndGroupMembers(newVersionOfGroupMembers: Set<ContactIdentity>, newVersionOfPendingMembers: Set<PendingGroupMember>, groupMembersVersion: Int?) throws {
        
        if let groupMembersVersion {
            guard groupMembersVersion > self.groupMembersVersion else { return }
        }

        guard let context = self.managedObjectContext else {
            throw ObvIdentityManagerError.contextIsNil
        }
        
        let currentPendingMembersToDelete = self.pendingGroupMembers.subtracting(newVersionOfPendingMembers)
        for pendingMemberToDelete in currentPendingMembersToDelete {
            context.delete(pendingMemberToDelete)
        }
        
        self.groupMembers = newVersionOfGroupMembers
        self.pendingGroupMembers = newVersionOfPendingMembers
        if let groupMembersVersion {
            self.groupMembersVersion = groupMembersVersion
        }

        notificationRelatedChanges.insert(.pendingMembersAndGroupMembers)

    }
    
}


// MARK: - Convenience DB getters

extension ContactGroup {
    
    struct Predicate {
        enum Key: String {
            // Attributes
            case groupMembersVersion = "groupMembersVersion"
            case rawGroupUid = "rawGroupUid"
            // Relationships
            case groupMembers = "groupMembers"
            case ownedIdentity = "ownedIdentity"
            case pendingGroupMembers = "pendingGroupMembers"
            case publishedDetails = "publishedDetails"
        }
        static func withOwnedIdentity(_ ownedIdentity: OwnedIdentity) -> NSPredicate {
            NSPredicate(Key.ownedIdentity, equalTo: ownedIdentity)
        }
        static func whereGroupMembersContain(_ contactIdentity: ContactIdentity) -> NSPredicate {
            NSPredicate(Key.groupMembers, contains: contactIdentity)
        }
        static func withGroupUid(_ groupUid: UID) -> NSPredicate {
            NSPredicate(Key.rawGroupUid, EqualToData: groupUid.raw)
        }
        static func withOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> NSPredicate {
            let key = [Key.ownedIdentity.rawValue, OwnedIdentity.Predicate.Key.rawCryptoIdentity.rawValue].joined(separator: ".")
            return NSPredicate(key, EqualToData: ownedCryptoId.getIdentity())
        }
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<ContactGroup> {
        return NSFetchRequest<ContactGroup>(entityName: entityName)
    }
    
    
    static func getAll(ownedIdentity: OwnedIdentity) throws -> Set<ContactGroup> {
        guard let context = ownedIdentity.managedObjectContext else { throw Self.makeError(message: "Could not find context") }
        let request: NSFetchRequest<ContactGroup> = ContactGroup.fetchRequest()
        request.predicate = Predicate.withOwnedIdentity(ownedIdentity)
        let items = try context.fetch(request)
        return Set(items)
    }
 
    
    static func getAllContactGroupWhereGroupMembersContainTheContact(_ contactIdentity: ContactIdentity) throws -> Set<ContactGroup> {
        guard let context = contactIdentity.managedObjectContext else { throw Self.makeError(message: "Could not find context") }
        guard let ownedIdentity = contactIdentity.ownedIdentity else { throw Self.makeError(message: "Could not find owned identity associated to contact") }
        let request: NSFetchRequest<ContactGroup> = ContactGroup.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedIdentity(ownedIdentity),
            Predicate.whereGroupMembersContain(contactIdentity),
        ])
        let items = try context.fetch(request)
        return Set(items)
    }

}


// MARK: - Sending notifications

extension ContactGroup {
    
    private struct NotificationRelatedChanges: OptionSet {
        let rawValue: UInt8
        static let publishedDetails = NotificationRelatedChanges(rawValue: 1 << 0)
        static let pendingMembersAndGroupMembers = NotificationRelatedChanges(rawValue: 1 << 1)
    }
    
    
    override func prepareForDeletion() {
        super.prepareForDeletion()
        // This code shall *not* be move into the willSave() method, as, on deletion, self.ownedIdentity does not seem to be always available there.
        guard let managedObjectContext else { assertionFailure(); return }
        guard managedObjectContext.concurrencyType != .mainQueueConcurrencyType else { return }
        ownedIdentityCryptoIdentityOnDeletion = try? ownedIdentity.cryptoIdentity
        if let groupJoined = self as? ContactGroupJoined {
            groupOwnerCryptoIdentityOnDeletion = groupJoined.groupOwner.cryptoIdentity
        } else {
            groupOwnerCryptoIdentityOnDeletion = try? ownedIdentity.cryptoIdentity
        }
        groupUidOnDeletion = try? self.groupUid
        labelToDelete = publishedDetails.photoServerLabel
    }
    
    
    override func willSave() {
        super.willSave()
        if !isInserted {
            changedKeys = Set<String>(self.changedValues().keys)
        }
    }

    
    override func didSave() {
        super.didSave()
        
        defer {
            notificationRelatedChanges = []
            changedKeys.removeAll()
            isInsertedWhileRestoringSyncSnapshotOrBackup = false
        }
        
        guard let delegateManager = Self.delegateManager else {
            Self.logger.fault("The delegate manager is not set (2)")
            assertionFailure()
            return
        }
        
        if isInserted {
            
            // We do not send any notification after inserting an object during a snapshot restore or a backup restore
            guard !isInsertedWhileRestoringSyncSnapshotOrBackup else { assert(isInserted); return }

            if let joinedGroup = self as? ContactGroupJoined, let groupOwnerCryptoIdentity = joinedGroup.groupOwner.cryptoIdentity {
                
                do {
                    let NotificationType = ObvIdentityNotification.NewContactGroupJoined.self
                    let userInfo = [NotificationType.Key.groupUid: try self.groupUid,
                                    NotificationType.Key.groupOwner: groupOwnerCryptoIdentity,
                                    NotificationType.Key.ownedIdentity: try self.ownedIdentity.cryptoIdentity] as [String: Any]
                    delegateManager.notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
                } catch {
                    assertionFailure()
                }

            } else if self is ContactGroupOwned {
                
                do {
                    let NotificationType = ObvIdentityNotification.NewContactGroupOwned.self
                    let userInfo = [NotificationType.Key.groupUid: try self.groupUid,
                                    NotificationType.Key.ownedIdentity: try self.ownedIdentity.cryptoIdentity] as [String: Any]
                    delegateManager.notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
                } catch {
                    assertionFailure()
                }

            } else {
                
                assertionFailure()
                
            }
            
        }

        
        if isDeleted {
            
            if let groupUidOnDeletion, let groupOwnerCryptoIdentityOnDeletion, let ownedIdentityCryptoIdentityOnDeletion {
                let NotificationType = ObvIdentityNotification.ContactGroupDeleted.self
                let userInfo = [NotificationType.Key.groupUid: groupUidOnDeletion,
                                NotificationType.Key.groupOwner: groupOwnerCryptoIdentityOnDeletion,
                                NotificationType.Key.ownedIdentity: ownedIdentityCryptoIdentityOnDeletion] as [String: Any]
                delegateManager.notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
            } else {
                assertionFailure()
            }
            
        } else {
            
            if notificationRelatedChanges.contains(.publishedDetails) {
                
                if let groupOwned = self as? ContactGroupOwned {
                    
                    do {
                        let NotificationType = ObvIdentityNotification.ContactGroupOwnedHasUpdatedPublishedDetails.self
                        let userInfo = [NotificationType.Key.groupUid: try groupOwned.groupUid,
                                        NotificationType.Key.ownedIdentity: try groupOwned.ownedIdentity.cryptoIdentity] as [String: Any]
                        delegateManager.notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
                    } catch {
                        assertionFailure()
                    }

                } else if let groupJoined = self as? ContactGroupJoined, let groupOwner = groupJoined.groupOwner.cryptoIdentity {
                    
                    do {
                        let NotificationType = ObvIdentityNotification.ContactGroupJoinedHasUpdatedPublishedDetails.self
                        let userInfo = [NotificationType.Key.groupUid: try groupJoined.groupUid,
                                        NotificationType.Key.groupOwner: groupOwner,
                                        NotificationType.Key.ownedIdentity: try self.ownedIdentity.cryptoIdentity] as [String: Any]
                        delegateManager.notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
                    } catch {
                        assertionFailure()
                    }

                }
                
            }
            
            if notificationRelatedChanges.contains(.publishedDetails) || isDeleted {
                if isDeleted { assert(ownedIdentityCryptoIdentityOnDeletion != nil) }
                if let labelToDelete = self.labelToDelete {
                    do {
                        let ownedCryptoId = try ownedIdentityCryptoIdentityOnDeletion ?? ownedIdentity.cryptoIdentity
                        ObvIdentityNotificationNew.serverLabelHasBeenDeleted(ownedIdentity: ownedCryptoId, label: labelToDelete)
                            .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
                    } catch {
                        assertionFailure()
                    }
                }
            }
            
            
            if notificationRelatedChanges.contains(.pendingMembersAndGroupMembers) {
                
                if let groupOwned = self as? ContactGroupOwned {

                    do {
                        let NotificationType = ObvIdentityNotification.ContactGroupOwnedHasUpdatedPendingMembersAndGroupMembers.self
                        let userInfo = [NotificationType.Key.groupUid: try groupOwned.groupUid,
                                        NotificationType.Key.ownedIdentity: try groupOwned.ownedIdentity.cryptoIdentity] as [String: Any]
                        delegateManager.notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
                    } catch {
                        assertionFailure()
                    }

                } else if let groupJoined = self as? ContactGroupJoined, let groupOwner = groupJoined.groupOwner.cryptoIdentity {

                    do {
                        let NotificationType = ObvIdentityNotification.ContactGroupJoinedHasUpdatedPendingMembersAndGroupMembers.self
                        let userInfo = [NotificationType.Key.groupUid: try groupJoined.groupUid,
                                        NotificationType.Key.groupOwner: groupOwner,
                                        NotificationType.Key.ownedIdentity: try groupJoined.ownedIdentity.cryptoIdentity] as [String: Any]
                        delegateManager.notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
                    } catch {
                        assertionFailure()
                    }

                }
                
            }
            
        }
        
        // Send a backupableManagerDatabaseContentChanged notification
        do {
            ObvBackupNotification.backupableManagerDatabaseContentChanged
                .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
        }
        
        
        // Potentially notify that the previous backed up profile snapshot is obsolete
        // For a list of all the entities that can perform a similar notification, see `OwnedIdentity`
        
        if !isDeleted {
            let previousBackedUpProfileSnapShotIsObsolete: Bool
            if isInserted {
                previousBackedUpProfileSnapShotIsObsolete = true
            } else if changedKeys.contains(Predicate.Key.groupMembersVersion.rawValue) ||
                        changedKeys.contains(Predicate.Key.groupMembers.rawValue) ||
                        changedKeys.contains(Predicate.Key.pendingGroupMembers.rawValue) ||
                        changedKeys.contains(Predicate.Key.publishedDetails.rawValue) {
                previousBackedUpProfileSnapShotIsObsolete = true
            } else {
                previousBackedUpProfileSnapShotIsObsolete = false
            }
            if previousBackedUpProfileSnapShotIsObsolete {
                do {
                    let cryptoIdentity = try self.ownedIdentity.cryptoIdentity
                    let ownedCryptoId = ObvCryptoId(cryptoIdentity: cryptoIdentity)
                    Task { await Self.observersHolder.previousBackedUpProfileSnapShotIsObsoleteAsContactGroupChanged(ownedCryptoId: ownedCryptoId) }
                } catch {
                    assertionFailure()
                }
            }
        }

    }

}

// MARK: - Helpers for snapshots

extension ContactGroup {
    
    var groupV1Identifier: GroupV1Identifier? {
        guard let groupUid = try? self.groupUid else { assertionFailure(); return nil }
        if let groupJoined = self as? ContactGroupJoined {
            guard let groupOwner = groupJoined.groupOwner.cryptoIdentity else { assertionFailure(); return nil }
            return .init(groupUid: groupUid, groupOwner: ObvCryptoId(cryptoIdentity: groupOwner))
        } else if self is ContactGroupOwned {
            guard let groupOwner = try? ObvCryptoId(cryptoIdentity: ownedIdentity.cryptoIdentity) else { assertionFailure(); return nil }
            return .init(groupUid: groupUid, groupOwner: groupOwner)
        } else {
            assertionFailure()
            return nil
        }
    }
    
}


// MARK: - For Snapshot purposes


extension ContactGroup {
    
    var syncSnapshot: ContactGroupSyncSnapshotNode {
        get throws {
            try .init(groupMembersVersion: groupMembersVersion,
                      groupMembers: groupMembers,
                      pendingGroupMembers: pendingGroupMembers,
                      publishedDetails: publishedDetails,
                      trustedDetails: (self as? ContactGroupJoined)?.trustedDetails,
                      latestDetails: (self as? ContactGroupOwned)?.latestDetails)
        }
    }

}


struct ContactGroupSyncSnapshotNode: ObvSyncSnapshotNode, Sendable {
    
    private let domain: Set<CodingKeys>
    private let publishedDetails: ContactGroupDetailsSyncSnapshotNode?
    private let trustedDetails: ContactGroupDetailsSyncSnapshotNode? // Not for owned groups
    private let latestDetails: ContactGroupDetailsSyncSnapshotNode? // Not for joined groups, not used under Android, not serialized
    let groupMembersVersion: Int?
    private let groupMembers: Set<ObvCryptoIdentity>
    private let pendingGroupMembers: [ObvCryptoIdentity: PendingGroupMemberSyncSnapshotItem]
    
    let id = Self.generateIdentifier()
    
    enum CodingKeys: String, CodingKey, CaseIterable, Codable {
        case publishedDetails = "published_details"
        case trustedDetails = "trusted_details"
        case groupMembersVersion = "group_members_version"
        case groupMembers = "members"
        case pendingGroupMembers = "pending_members"
        case domain = "domain"
    }


    private static let defaultDomainForGroupOwned = Set(CodingKeys.allCases.filter({ $0 != .domain && $0 != .trustedDetails }))
    private static let defaultDomainForGroupJoined = Set(CodingKeys.allCases.filter({ $0 != .domain }))


    fileprivate init(groupMembersVersion: Int, groupMembers: Set<ContactIdentity>, pendingGroupMembers: Set<PendingGroupMember>, publishedDetails: ContactGroupDetailsPublished, trustedDetails: ContactGroupDetailsTrusted?, latestDetails: ContactGroupDetailsLatest?) throws {
        self.publishedDetails = publishedDetails.syncSnapshot
        if let trustedDetails, trustedDetails.version != publishedDetails.version {
            self.trustedDetails = trustedDetails.syncSnapshot
        } else {
            self.trustedDetails = nil
        }
        self.latestDetails = latestDetails?.syncSnapshot
        self.groupMembersVersion = groupMembersVersion
        self.groupMembers = Set(groupMembers.compactMap({ $0.cryptoIdentity }))
        do {
            let pairs: [(ObvCryptoIdentity, PendingGroupMemberSyncSnapshotItem)] = try pendingGroupMembers.map { (try $0.cryptoIdentity, $0.syncSnapshot) }
            self.pendingGroupMembers = Dictionary(pairs, uniquingKeysWith: { (first, _) in assertionFailure(); return first })
        }
        self.domain = Self.defaultDomainForGroupJoined
    }

    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(publishedDetails, forKey: .publishedDetails)
        try container.encodeIfPresent(trustedDetails, forKey: .trustedDetails)
        try container.encodeIfPresent(groupMembersVersion, forKey: .groupMembersVersion)
        try container.encode(groupMembers.map({ $0.getIdentity() }), forKey: .groupMembers)
        // Encode pendingGroupMembers using ObvCryptoIdentity as JSON keys
        do {
            let dict: [String: PendingGroupMemberSyncSnapshotItem] = .init(pendingGroupMembers, keyMapping: { $0.getIdentity().base64EncodedString() }, valueMapping: { $0 })
            try container.encode(dict, forKey: .pendingGroupMembers)
        }
        try container.encode(domain, forKey: .domain)
    }

    
    init(from decoder: Decoder) throws {
        do {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let rawKeys = try values.decode(Set<String>.self, forKey: .domain)
            self.domain = Set(rawKeys.compactMap({ CodingKeys(rawValue: $0) }))
            self.groupMembersVersion = try values.decodeIfPresent(Int.self, forKey: .groupMembersVersion)
            self.groupMembers = Set((try values.decodeIfPresent([Data].self, forKey: .groupMembers) ?? [Data]()).compactMap({ ObvCryptoIdentity(from: $0) }))
            // Decode pendingGroupMembers using ObvCryptoIdentity as JSON keys
            do {
                let dict = try values.decodeIfPresent([String: PendingGroupMemberSyncSnapshotItem].self, forKey: .pendingGroupMembers) ?? [:]
                self.pendingGroupMembers = .init(dict, keyMapping: { $0.base64EncodedToData?.identityToObvCryptoIdentity }, valueMapping: { $0 })
            }
            // Special treatment for details.
            // At this point, we don't know whether we are decoding a snapshot concerning an owned or a joined group, so we need to consider both cases.
            do {
                let publishedDetailsFromJSON = try values.decodeIfPresent(ContactGroupDetailsSyncSnapshotNode.self, forKey: .publishedDetails)
                let trustedDetailsFromJSON = try values.decodeIfPresent(ContactGroupDetailsSyncSnapshotNode.self, forKey: .trustedDetails)
                self.publishedDetails = publishedDetailsFromJSON ?? trustedDetailsFromJSON?.copyWithNewId()
                self.trustedDetails = trustedDetailsFromJSON ?? publishedDetailsFromJSON?.copyWithNewId()
                self.latestDetails = publishedDetailsFromJSON?.copyWithNewId() // Will be ignored if the group is joined
            }
        } catch {
            assertionFailure()
            throw error
        }
    }


    func restoreInstance(within context: NSManagedObjectContext, ownedCryptoIdentity: ObvCryptoIdentity, groupV1Identifier: GroupV1Identifier, associations: inout SnapshotNodeManagedObjectAssociations) throws {
        
        let minimumDomain: Set<CodingKeys>
        do {
            let commonMinimumDomain: Set<CodingKeys> = Set([.groupMembersVersion, .groupMembers, .pendingGroupMembers])
            if ownedCryptoIdentity == groupV1Identifier.groupOwner.cryptoIdentity {
                // Owned group
                minimumDomain = commonMinimumDomain.union(Set([.publishedDetails]))
            } else {
                // Joined group
                minimumDomain = commonMinimumDomain.union(Set([.trustedDetails]))
            }
        }
        
        guard minimumDomain.isSubset(of: domain) else {
            assertionFailure()
            throw ObvError.tryingToRestoreIncompleteNode
        }
        
        // Details
        
        if ownedCryptoIdentity == groupV1Identifier.groupOwner.cryptoIdentity {

            // Owned group need both published and latest details

            guard let publishedDetails, let latestDetails else {
                throw ObvError.tryingToRestoreIncompleteNode
            }
            
            let contactGroupOwned = try ContactGroupOwned(snapshotNode: self, groupUid: groupV1Identifier.groupUid, within: context)
            try associations.associate(contactGroupOwned, to: self)
            
            try publishedDetails.restoreContactGroupDetailsPublishedInstance(within: context, associations: &associations)
            try latestDetails.restoreContactGroupDetailsLatestInstance(within: context, associations: &associations)
            
        } else {
            
            // Joined group need both published and trusted details
            
            guard let publishedDetails, let trustedDetails else {
                throw ObvError.tryingToRestoreIncompleteNode
            }

            let contactGroupJoined = try ContactGroupJoined(snapshotNode: self, groupUid: groupV1Identifier.groupUid, within: context)
            try associations.associate(contactGroupJoined, to: self)
            
            try publishedDetails.restoreContactGroupDetailsPublishedInstance(within: context, associations: &associations)
            try trustedDetails.restoreContactGroupDetailsTrustedInstance(within: context, associations: &associations)

        }
        
        // Group members do not need to be restored here: they are restored as contacts and will eventually be included in the associations
        
        // pending members
        
        if domain.contains(.pendingGroupMembers) {
            try pendingGroupMembers.forEach { (cryptoIdentity, snapshotItem) in
                try snapshotItem.restoreInstance(within: context, cryptoIdentity: cryptoIdentity, associations: &associations)
            }
        }
        
    }
    

    func restoreRelationships(associations: SnapshotNodeManagedObjectAssociations, groupV1Identifier: GroupV1Identifier, contactIdentities: [ObvCryptoIdentity: ContactIdentity], within context: NSManagedObjectContext) throws {
        
        let contactGroup: ContactGroup = try associations.getObject(associatedTo: self, within: context)
        
        // Restore the relationships of this instance
        
        let groupMembers: Set<ContactIdentity> = Set(try self.groupMembers.map { contactCryptoIdentity in
            guard let contactIdentity = contactIdentities[contactCryptoIdentity] else {
                throw ObvError.groupMemberNotFoundInContacts
            }
            return contactIdentity
        })
        
        let pendingGroupMembers: Set<PendingGroupMember> = Set(try self.pendingGroupMembers.values.map { try associations.getObject(associatedTo: $0, within: context) })

        if let contactGroupOwned = contactGroup as? ContactGroupOwned {
            
            // Owned group need both published and latest details

            guard let publishedDetails, let latestDetails else {
                throw ObvError.tryingToRestoreIncompleteNode
            }

            let contactGroupDetailsPublished: ContactGroupDetailsPublished = try associations.getObject(associatedTo: publishedDetails, within: context)
            let contactGroupDetailsLatest: ContactGroupDetailsLatest = try associations.getObject(associatedTo: latestDetails, within: context)

            contactGroupOwned.restoreRelationshipsOfContactGroupOwned(
                latestDetails: contactGroupDetailsLatest,
                groupMembers: groupMembers,
                pendingGroupMembers: pendingGroupMembers,
                publishedDetails: contactGroupDetailsPublished)

            // Restore the relationships of this instance relationships

            try publishedDetails.restoreRelationships(associations: associations, within: context)
            try latestDetails.restoreRelationships(associations: associations, within: context)

        } else if let contactGroupJoined = contactGroup as? ContactGroupJoined {
            
            // Joined group need both published and trusted details
            
            guard let publishedDetails, let trustedDetails else {
                throw ObvError.tryingToRestoreIncompleteNode
            }

            let contactGroupDetailsPublished: ContactGroupDetailsPublished = try associations.getObject(associatedTo: publishedDetails, within: context)
            let contactGroupDetailsTrusted: ContactGroupDetailsTrusted = try associations.getObject(associatedTo: trustedDetails, within: context)

            guard let groupOwner = contactIdentities[groupV1Identifier.groupOwner.cryptoIdentity] else {
                assertionFailure()
                throw ObvError.groupOwnerNotFoundInContacts
            }
            
            contactGroupJoined.restoreRelationshipsOfContactGroupJoined(
                groupOwner: groupOwner,
                trustedDetails: contactGroupDetailsTrusted,
                groupMembers: groupMembers,
                pendingGroupMembers: pendingGroupMembers,
                publishedDetails: contactGroupDetailsPublished)

            // Restore the relationships of this instance relationships

            try publishedDetails.restoreRelationships(associations: associations, within: context)
            try trustedDetails.restoreRelationships(associations: associations, within: context)

        }

        try self.pendingGroupMembers.forEach { (cryptoIdentity, pendingMemberNode) in
            try pendingMemberNode.restoreRelationships(associations: associations, within: context)
        }

    }
    
    
    enum ObvError: Error {
        case groupMemberNotFoundInContacts
        case groupOwnerNotFoundInContacts
        case tryingToRestoreIncompleteNode
    }
    
}


// MARK: - Private Helpers

private extension String {
    
    var base64EncodedToData: Data? {
        guard let data = Data(base64Encoded: self) else { assertionFailure(); return nil }
        return data
    }
    
}


private extension Data {
    
    var identityToObvCryptoIdentity: ObvCryptoIdentity? {
        guard let cryptoIdentity = ObvCryptoIdentity(from: self) else { assertionFailure(); return nil }
        return cryptoIdentity
    }
    
}


// MARK: - ContactGroup observers

protocol ContactGroupObserver: AnyObject {
    func previousBackedUpProfileSnapShotIsObsoleteAsContactGroupChanged(ownedCryptoId: ObvCryptoId) async
}


private actor ObserversHolder: ContactGroupObserver {
    
    private var observers = [WeakObserver]()
    
    private final class WeakObserver {
        private(set) weak var value: ContactGroupObserver?
        init(value: ContactGroupObserver?) {
            self.value = value
        }
    }

    func addObserver(_ newObserver: ContactGroupObserver) {
        self.observers.append(.init(value: newObserver))
    }

    // Implementing OwnedIdentityObserver

    func previousBackedUpProfileSnapShotIsObsoleteAsContactGroupChanged(ownedCryptoId: ObvCryptoId) async {
        await withTaskGroup(of: Void.self) { taskGroup in
            for observer in observers.compactMap(\.value) {
                taskGroup.addTask { await observer.previousBackedUpProfileSnapShotIsObsoleteAsContactGroupChanged(ownedCryptoId: ownedCryptoId) }
            }
        }
    }
    
}
