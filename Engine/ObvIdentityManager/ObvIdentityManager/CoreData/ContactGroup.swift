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
import os.log
import ObvTypes
import ObvCrypto
import ObvMetaManager
import OlvidUtils

@objc(ContactGroup)
class ContactGroup: NSManagedObject, ObvManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "ContactGroup"
    private static let errorDomain = String(describing: ContactGroup.self)
    static let groupUidKey = "groupUid"
    static let groupMembersKey = "groupMembers"
    static let ownedIdentityKey = "ownedIdentity"
    static let pendingGroupMembersKey = "pendingGroupMembers"
    static let publishedDetailsKey = "publishedDetails"

    private static func makeError(message: String) -> Error { NSError(domain: errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { Self.makeError(message: message) }

    // MARK: Attributes
    
    @NSManaged private(set) var groupUid: UID // Primary key
    @NSManaged private(set) var groupMembersVersion: Int
    
    // MARK: Relationships
    
    private(set) var groupMembers: Set<ContactIdentity> {
        get {
            let items = kvoSafePrimitiveValue(forKey: ContactGroup.groupMembersKey) as! Set<ContactIdentity>
            for item in items { item.obvContext = self.obvContext }
            return items
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: ContactGroup.groupMembersKey)
        }
    }

    private(set) var ownedIdentity: OwnedIdentity {
        get {
            let item = kvoSafePrimitiveValue(forKey: ContactGroup.ownedIdentityKey) as! OwnedIdentity
            item.obvContext = self.obvContext
            return item
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: ContactGroup.ownedIdentityKey)
        }
    }

    private(set) var pendingGroupMembers: Set<PendingGroupMember> {
        get {
            let items = kvoSafePrimitiveValue(forKey: ContactGroup.pendingGroupMembersKey) as! Set<PendingGroupMember>
            for item in items { item.obvContext = self.obvContext }
            return items
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: ContactGroup.pendingGroupMembersKey)
        }
    }

    // Shall *not* be set outside of the subclasses of this class.
    private(set) var publishedDetails: ContactGroupDetailsPublished {
        get {
            let item = kvoSafePrimitiveValue(forKey: ContactGroup.publishedDetailsKey) as! ContactGroupDetailsPublished
            item.obvContext = self.obvContext
            return item
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: ContactGroup.publishedDetailsKey)
        }
    }

    // MARK: Other variables
    
    weak var delegateManager: ObvIdentityDelegateManager?
    var obvContext: ObvContext?
    private var ownedIdentityCryptoIdentityOnDeletion: ObvCryptoIdentity?
    private var groupOwnerCryptoIdentityOnDeletion: ObvCryptoIdentity?
    private var notificationRelatedChanges: NotificationRelatedChanges = []
    private var labelToDelete: UID?

    // MARK: - Initializer
    
    /// This initializer shall only be called from the intializer of one of concrete subclasses of `ContactGroup`.
    ///
    convenience init(groupInformationWithPhoto: GroupInformationWithPhoto, ownedIdentity: OwnedIdentity, groupMembers: Set<ObvCryptoIdentity>, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>, delegateManager: ObvIdentityDelegateManager, forEntityName entityName: String) throws {
        
        guard let obvContext = ownedIdentity.obvContext else {
            throw ObvIdentityManagerError.contextIsNil.error(withDomain: ContactGroup.errorDomain)
        }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        
        self.groupUid = groupInformationWithPhoto.groupUid
        self.groupMembersVersion = 0
        
        self.groupMembers = Set<ContactIdentity>()
        for groupMember in groupMembers {
            guard let contact = try ContactIdentity.get(contactIdentity: groupMember, ownedIdentity: ownedIdentity.cryptoIdentity, delegateManager: delegateManager, within: obvContext) else {
                throw ObvIdentityManagerError.cryptoIdentityIsNotContact.error(withDomain: ContactGroup.errorDomain)
            }
            self.groupMembers.insert(contact)
        }
        self.ownedIdentity = ownedIdentity
        self.pendingGroupMembers = Set(try pendingGroupMembers.map { try PendingGroupMember(contactGroup: self, cryptoIdentityWithCoreDetails: $0, delegateManager: delegateManager) })
        let groupDetailsElementsWithPhoto = groupInformationWithPhoto.groupDetailsElementsWithPhoto
        self.publishedDetails = try ContactGroupDetailsPublished(contactGroup: self,
                                                                 groupDetailsElementsWithPhoto: groupDetailsElementsWithPhoto,
                                                                 delegateManager: delegateManager)
        
        self.delegateManager = delegateManager
        
    }
    
    
    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreater in a second step
    convenience init(groupMembersVersion: Int, groupUid: UID, forEntityName entityName: String, within obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.groupMembersVersion = groupMembersVersion
        self.groupUid = groupUid
    }
    
    func restoreRelationshipsOfContactGroup(groupMembers: Set<ContactIdentity>, pendingGroupMembers: Set<PendingGroupMember>, publishedDetails: ContactGroupDetailsPublished) {
        self.groupMembers = groupMembers
        /* ownedIdentity is set in OwnedIdentity  */
        self.pendingGroupMembers = pendingGroupMembers
        self.publishedDetails = publishedDetails
    }
}

// MARK: - Convenience methods

extension ContactGroup {
    
    func getPendingGroupMembersWithCoreDetails() -> Set<CryptoIdentityWithCoreDetails> {
        
        let pendingGroupMembersWithCoreDetails = pendingGroupMembers.map {
            return CryptoIdentityWithCoreDetails(cryptoIdentity: $0.cryptoIdentity, coreDetails: $0.identityCoreDetails)
        }
        
        return Set(pendingGroupMembersWithCoreDetails)
    }
    
    // This method is used both for joined and owned contact groups
    func updateDetailsPublished(with groupDetailsElements: GroupDetailsElements, delegateManager: ObvIdentityDelegateManager) throws {

        if groupDetailsElements.version <= self.publishedDetails.version { return }
        
        guard groupDetailsElements.version > self.publishedDetails.version else {
            throw ObvIdentityManagerError.invalidGroupDetailsVersion.error(withDomain: ContactGroup.errorDomain)
        }
        
        let errorDomain = ContactGroup.errorDomain

        guard let obvContext = self.obvContext else {
            throw ObvIdentityManagerError.contextIsNil.error(withDomain: errorDomain)
        }
        
        let oldPublishedDetails = self.publishedDetails
        let groupDetailsElementsWithPhoto: GroupDetailsElementsWithPhoto
        if oldPublishedDetails.photoServerKeyAndLabel == groupDetailsElements.photoServerKeyAndLabel {
            self.labelToDelete = nil
            if oldPublishedDetails.photoServerKeyAndLabel == nil {
                groupDetailsElementsWithPhoto = GroupDetailsElementsWithPhoto(groupDetailsElements: groupDetailsElements, photoURL: nil)
            } else {
                let photoURL = publishedDetails.getPhotoURL(identityPhotosDirectory: delegateManager.identityPhotosDirectory)
                groupDetailsElementsWithPhoto = GroupDetailsElementsWithPhoto(groupDetailsElements: groupDetailsElements, photoURL: photoURL)
            }
        } else {
            self.labelToDelete = oldPublishedDetails.photoServerLabel
            groupDetailsElementsWithPhoto = GroupDetailsElementsWithPhoto(groupDetailsElements: groupDetailsElements, photoURL: nil)
        }
        self.publishedDetails = try ContactGroupDetailsPublished(contactGroup: self,
                                                                 groupDetailsElementsWithPhoto: groupDetailsElementsWithPhoto,
                                                                 delegateManager: delegateManager)
        try oldPublishedDetails.delete(identityPhotosDirectory: delegateManager.identityPhotosDirectory, within: obvContext)

        notificationRelatedChanges.insert(.publishedDetails)

    }
    
    
    func getGroupStructure(identityPhotosDirectory: URL) throws -> GroupStructure {
        if let ownedGroup = self as? ContactGroupOwned {
            return try ownedGroup.getOwnedGroupStructure(identityPhotosDirectory: identityPhotosDirectory)
        } else if let joinedGroup = self as? ContactGroupJoined {
            return try joinedGroup.getJoinedGroupStructure(identityPhotosDirectory: identityPhotosDirectory)
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
            throw ObvIdentityManagerError.groupIsNotJoined.error(withDomain: ContactGroup.errorDomain)
        }
        self.groupMembersVersion = 0
    }
    
    
    func transferPendingMemberToGroupMembersForGroupOwned(contactIdentity: ContactIdentity) throws {
        
        guard self is ContactGroupOwned else {
            throw ObvIdentityManagerError.groupIsNotOwned.error(withDomain: ContactGroup.errorDomain)
        }

        guard self.obvContext == contactIdentity.obvContext else {
            throw ObvIdentityManagerError.contextMismatch.error(withDomain: ContactGroup.errorDomain)
        }
        
        guard let obvContext = self.obvContext else {
            throw ObvIdentityManagerError.contextIsNil.error(withDomain: ContactGroup.errorDomain)
        }

        // Remove the pending member from the list of pending group members
        
        if let pendingMemberObject = self.pendingGroupMembers.filter({ $0.cryptoIdentity == contactIdentity.cryptoIdentity }).first {
            self.pendingGroupMembers.remove(pendingMemberObject)
            obvContext.delete(pendingMemberObject)
        }

        // Add this contact to the group members
        self.groupMembers.insert(contactIdentity)
        
        // Increment the group members version (note that self is an instance of ContactGroupOwned)
        self.groupMembersVersion += 1
        
        notificationRelatedChanges.insert(.pendingMembersAndGroupMembers)
    }
    
    func transferGroupMemberToPendingMembersForGroupOwned(contactCryptoIdentity: ObvCryptoIdentity) throws {
        
        guard let delegateManager = self.delegateManager else {
            throw ObvIdentityManagerError.delegateManagerIsNotSet.error(withDomain: ContactGroup.errorDomain)
        }
        
        guard self is ContactGroupOwned else {
            throw ObvIdentityManagerError.groupIsNotOwned.error(withDomain: ContactGroup.errorDomain)
        }

        // Remove the group member from the list of group members
        
        if let contactIdentityObject = self.groupMembers.filter({ $0.cryptoIdentity == contactCryptoIdentity }).first {
            self.groupMembers.remove(contactIdentityObject)
            // We do *not* delete the contact, we only want to remove her from the group
        }
        
        // Add this contact to the pending members (note that this call increments the members version)

        try (self as! ContactGroupOwned).add(newPendingMembers: Set([contactCryptoIdentity]), delegateManager: delegateManager)
        
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

        guard let obvContext = self.obvContext else {
            throw ObvIdentityManagerError.contextIsNil.error(withDomain: ContactGroup.errorDomain)
        }
        
        let currentPendingMembersToDelete = self.pendingGroupMembers.subtracting(newVersionOfPendingMembers)
        for pendingMemberToDelete in currentPendingMembersToDelete {
            obvContext.delete(pendingMemberToDelete)
        }
        
        // In order to avoid an error within the logs, we set the delegateManager on all past and new group members
        for member in self.groupMembers {
            member.delegateManager = self.delegateManager
        }
        for member in newVersionOfGroupMembers {
            member.delegateManager = self.delegateManager
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

    @nonobjc class func fetchRequest() -> NSFetchRequest<ContactGroup> {
        return NSFetchRequest<ContactGroup>(entityName: entityName)
    }
    
    
    static func getAll(ownedIdentity: OwnedIdentity, delegateManager: ObvIdentityDelegateManager) throws -> Set<ContactGroup> {
        guard let obvContext = ownedIdentity.obvContext else { throw Self.makeError(message: "Could not find context") }
        let request: NSFetchRequest<ContactGroup> = ContactGroup.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", ContactGroup.ownedIdentityKey, ownedIdentity)
        let items = (try obvContext.fetch(request))
        items.forEach { $0.delegateManager = delegateManager }
        return Set(items)
    }
 
    
    static func getAllContactGroupWhereGroupMembersContainTheContact(_ contactIdentity: ContactIdentity, delegateManager: ObvIdentityDelegateManager) throws -> Set<ContactGroup> {
        guard let obvContext = contactIdentity.obvContext else { throw Self.makeError(message: "Could not find context") }
        guard let ownedIdentity = contactIdentity.ownedIdentity else { throw Self.makeError(message: "Could not find owned identity associated to contact") }
        let request: NSFetchRequest<ContactGroup> = ContactGroup.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %@ IN %K",
                                        ContactGroup.ownedIdentityKey, ownedIdentity,
                                        contactIdentity, ContactGroup.groupMembersKey)
        let items = (try obvContext.fetch(request))
        items.forEach { $0.delegateManager = delegateManager }
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
        ownedIdentityCryptoIdentityOnDeletion = ownedIdentity.cryptoIdentity
        if let groupJoined = self as? ContactGroupJoined {
            groupOwnerCryptoIdentityOnDeletion = groupJoined.groupOwner.cryptoIdentity
        } else {
            groupOwnerCryptoIdentityOnDeletion = ownedIdentity.cryptoIdentity
        }
        labelToDelete = publishedDetails.photoServerLabel
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
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: String(describing: Self.self))
        
        if isDeleted {
            
            let NotificationType = ObvIdentityNotification.ContactGroupDeleted.self
            let userInfo = [NotificationType.Key.groupUid: self.groupUid,
                            NotificationType.Key.groupOwner: groupOwnerCryptoIdentityOnDeletion!,
                            NotificationType.Key.ownedIdentity: ownedIdentityCryptoIdentityOnDeletion!] as [String: Any]
            delegateManager.notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
            
        } else {
            
            if notificationRelatedChanges.contains(.publishedDetails) {
                
                if let groupOwned = self as? ContactGroupOwned {
                    
                    let NotificationType = ObvIdentityNotification.ContactGroupOwnedHasUpdatedPublishedDetails.self
                    let userInfo = [NotificationType.Key.groupUid: groupOwned.groupUid,
                                    NotificationType.Key.ownedIdentity: groupOwned.ownedIdentity.cryptoIdentity] as [String: Any]
                    delegateManager.notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
                    
                } else if let groupJoined = self as? ContactGroupJoined {
                    
                    let NotificationType = ObvIdentityNotification.ContactGroupJoinedHasUpdatedPublishedDetails.self
                    let userInfo = [NotificationType.Key.groupUid: groupJoined.groupUid,
                                    NotificationType.Key.groupOwner: groupJoined.groupOwner.cryptoIdentity,
                                    NotificationType.Key.ownedIdentity: self.ownedIdentity.cryptoIdentity] as [String: Any]
                    delegateManager.notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
                    
                }
                
            }
            
            if notificationRelatedChanges.contains(.publishedDetails) || isDeleted {
                if isDeleted { assert(ownedIdentityCryptoIdentityOnDeletion != nil) }
                let ownedCryptoId = ownedIdentityCryptoIdentityOnDeletion ?? ownedIdentity.cryptoIdentity
                if let labelToDelete = self.labelToDelete {
                    let notification = ObvIdentityNotificationNew.serverLabelHasBeenDeleted(ownedIdentity: ownedCryptoId, label: labelToDelete)
                    notification.postOnBackgroundQueue(within: delegateManager.notificationDelegate)
                }
            }
            
            
            if notificationRelatedChanges.contains(.pendingMembersAndGroupMembers) {
                
                if let groupOwned = self as? ContactGroupOwned {
                    
                    let NotificationType = ObvIdentityNotification.ContactGroupOwnedHasUpdatedPendingMembersAndGroupMembers.self
                    let userInfo = [NotificationType.Key.groupUid: groupOwned.groupUid,
                                    NotificationType.Key.ownedIdentity: groupOwned.ownedIdentity.cryptoIdentity] as [String: Any]
                    delegateManager.notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
                    
                } else if let groupJoined = self as? ContactGroupJoined {
                    
                    let NotificationType = ObvIdentityNotification.ContactGroupJoinedHasUpdatedPendingMembersAndGroupMembers.self
                    let userInfo = [NotificationType.Key.groupUid: groupJoined.groupUid,
                                    NotificationType.Key.groupOwner: groupJoined.groupOwner.cryptoIdentity,
                                    NotificationType.Key.ownedIdentity: groupJoined.ownedIdentity.cryptoIdentity] as [String: Any]
                    delegateManager.notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
                    
                }
                
            }
            
        }
        
        // Send a backupableManagerDatabaseContentChanged notification
        do {
            guard let flowId = obvContext?.flowId else {
                os_log("Could not notify that this backupable manager database content changed", log: log, type: .fault)
                assertionFailure()
                return
            }
            ObvBackupNotification.backupableManagerDatabaseContentChanged(flowId: flowId)
                .postOnBackgroundQueue(within: delegateManager.notificationDelegate)
        }
        
    }

    
}
