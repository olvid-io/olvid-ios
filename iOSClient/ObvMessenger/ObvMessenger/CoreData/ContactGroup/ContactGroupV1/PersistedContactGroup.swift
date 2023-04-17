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
import ObvEngine
import ObvTypes
import os.log
import ObvCrypto

@objc(PersistedContactGroup)
class PersistedContactGroup: NSManagedObject {
    
    private static let entityName = "PersistedContactGroup"

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "PersistedContactGroup")

    static let groupNameKey = "groupName"
    private static let groupUidRawKey = "groupUidRaw"
    private static let ownerIdentityKey = "ownerIdentity"
    private static let rawCategoryKey = "rawCategory"
    private static let rawOwnedIdentityKey = "rawOwnedIdentity"
    static let ownedIdentityIdentityKey = [rawOwnedIdentityKey, PersistedObvOwnedIdentity.identityKey].joined(separator: ".")
    private static let pendingMembersKey = "pendingMembers"
    private static let errorDomain = "PersistedContactGroup"
    
    private static func makeError(message: String) -> Error { NSError(domain: errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { Self.makeError(message: message) }

    // MARK: - Attributes
    
    @NSManaged private(set) var groupName: String
    @NSManaged private var groupUidRaw: Data
    @NSManaged private(set) var ownerIdentity: Data // MUST be kept in sync with the owner relationship of subclasses
    @NSManaged private var rawCategory: Int
    @NSManaged private(set) var rawOwnedIdentityIdentity: Data // Required for core data constraints
    @NSManaged private var photoURL: URL? // Reset with the engine photo URL when it changes and during bootstrap

    // MARK: - Relationships
    
    @NSManaged private(set) var contactIdentities: Set<PersistedObvContactIdentity>
    @NSManaged private(set) var discussion: PersistedGroupDiscussion
    @NSManaged private(set) var displayedContactGroup: DisplayedContactGroup? // Expected to be non nil
    // If nil, the following relationship will eventually be cascade-deleted
    @NSManaged private var rawOwnedIdentity: PersistedObvOwnedIdentity? // *Never* accessed directly
    @NSManaged private(set) var pendingMembers: Set<PersistedPendingGroupMember>

    // MARK: - Other variables
    
    private var changedKeys = Set<String>()
    private var insertedContacts = Set<PersistedObvContactIdentity>()
    private var removedContacts = Set<PersistedObvContactIdentity>()
    private var insertedPendingMembers = Set<PersistedPendingGroupMember>()
    
    private(set) var ownedIdentity: PersistedObvOwnedIdentity? {
        get {
            return self.rawOwnedIdentity
        }
        set {
            assert(newValue != nil)
            if let value = newValue {
                self.rawOwnedIdentityIdentity = value.cryptoId.getIdentity()
            }
            self.rawOwnedIdentity = newValue
        }
    }
        
    var category: Category {
        return Category(rawValue: rawCategory)!
    }
    
    enum Category: Int {
        case owned = 0
        case joined = 1
    }
    
    var groupUid: UID {
        return UID(uid: groupUidRaw)!
    }
    
    var displayName: String {
        if let groupJoined = self as? PersistedContactGroupJoined {
            return groupJoined.groupNameCustom ?? self.groupName
        } else {
            return self.groupName
        }
    }

    var displayPhotoURL: URL? {
        if let groupJoined = self as? PersistedContactGroupJoined {
            return groupJoined.customPhotoURL ?? self.photoURL
        } else {
            return self.photoURL
        }
    }
    
    func getGroupId() throws -> (groupUid: UID, groupOwner: ObvCryptoId) {
        let groupOwner = try ObvCryptoId(identity: self.ownerIdentity)
        return (self.groupUid, groupOwner)
    }
    
    var sortedContactIdentities: [PersistedObvContactIdentity] {
        contactIdentities.sorted(by: { $0.sortDisplayName < $1.sortDisplayName })
    }
    
    
    func hasAtLeastOneRemoteContactDevice() -> Bool {
        for contact in self.contactIdentities {
            if !contact.devices.isEmpty {
                return true
            }
        }
        return false
    }

}


// MARK: - Errors

extension PersistedContactGroup {
    
    struct ObvError: LocalizedError {
        
        let kind: Kind
        
        enum Kind {
            case unexpecterCountOfOwnedIdentities(expected: Int, received: Int)
        }
        
        var errorDescription: String? {
            switch kind {
            case .unexpecterCountOfOwnedIdentities(expected: let expected, received: let received):
                return "Unexpected number of owned identites. Expecting \(expected), got \(received)."
            }
        }
        
    }
    
}

// MARK: - Initializer

extension PersistedContactGroup {
    
    convenience init(contactGroup: ObvContactGroup, groupName: String, category: Category, forEntityName entityName: String, within context: NSManagedObjectContext) throws {

        guard let ownedIdentity = try PersistedObvOwnedIdentity.get(persisted: contactGroup.ownedIdentity, within: context) else {
            throw Self.makeError(message: "Could not find owned identity")
        }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.rawCategory = category.rawValue
        self.groupName = groupName
        self.groupUidRaw = contactGroup.groupUid.raw
        self.ownerIdentity = contactGroup.groupOwner.cryptoId.getIdentity()
        self.photoURL = contactGroup.trustedOrLatestPhotoURL

        let _contactIdentities = try contactGroup.groupMembers.compactMap { try PersistedObvContactIdentity.get(persisted: $0, whereOneToOneStatusIs: .any, within: context) }
        self.contactIdentities = Set(_contactIdentities)
        
        if let discussion = try PersistedGroupDiscussion.getWithGroupUID(contactGroup.groupUid,
                                                                         groupOwnerCryptoId: contactGroup.groupOwner.cryptoId,
                                                                         ownedCryptoId: ownedIdentity.cryptoId,
                                                                         within: context) {
            try discussion.setStatus(to: .active)
            self.discussion = discussion
        } else {
            self.discussion = try PersistedGroupDiscussion(contactGroup: self,
                                                           groupName: groupName,
                                                           ownedIdentity: ownedIdentity,
                                                           status: .active)
        }
        self.rawOwnedIdentityIdentity = ownedIdentity.cryptoId.getIdentity()
        self.ownedIdentity = ownedIdentity
        let _pendingMembers = try contactGroup.pendingGroupMembers.compactMap { try PersistedPendingGroupMember(genericIdentity: $0, contactGroup: self) }
        self.pendingMembers = Set(_pendingMembers)
        
        // Create or update the DisplayedContactGroup
        
        try createOrUpdateTheAssociatedDisplayedContactGroup()

    }
    
    
    func createOrUpdateTheAssociatedDisplayedContactGroup() throws {
        if let displayedContactGroup = self.displayedContactGroup {
            displayedContactGroup.updateUsingUnderlyingGroup()
        } else {
            self.displayedContactGroup = try DisplayedContactGroup(groupV1: self)
        }
    }
    
    
    func delete() throws {
        guard let context = self.managedObjectContext else { throw PersistedContactGroup.makeError(message: "Could not find context") }
        context.delete(self)
    }
    
    
    func resetDiscussionTitle() throws {
        try self.discussion.resetTitle(to: displayName)
    }
    
    
    // Shall only be called from a subclass
    func resetGroupName(to groupName: String) throws {
        let newGroupName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newGroupName.isEmpty else { throw makeError(message: "Trying to reset group name with an empty string") }
        self.groupName = groupName
        try resetDiscussionTitle()
        displayedContactGroup?.updateUsingUnderlyingGroup()
    }

    func updatePhoto(with photo: URL?) {
        self.photoURL = photo
        self.discussion.setHasUpdates()
        displayedContactGroup?.updateUsingUnderlyingGroup()
    }
}


// MARK: - Managing contact identities

extension PersistedContactGroup {
    
    private func insert(_ contactIdentity: PersistedObvContactIdentity) {
        if !self.contactIdentities.contains(contactIdentity) {
            self.contactIdentities.insert(contactIdentity)
            self.insertedContacts.insert(contactIdentity)
        }
        displayedContactGroup?.updateUsingUnderlyingGroup()
    }
    
    private func remove(_ contactIdentity: PersistedObvContactIdentity) {
        if self.contactIdentities.contains(contactIdentity) {
            self.contactIdentities.remove(contactIdentity)
            self.removedContacts.insert(contactIdentity)
        }
        displayedContactGroup?.updateUsingUnderlyingGroup()
    }
    
    func set(_ contactIdentities: Set<PersistedObvContactIdentity>) {
        let contactsToAdd = contactIdentities.subtracting(self.contactIdentities)
        let contactsToRemove = self.contactIdentities.subtracting(contactIdentities)
        for contact in contactsToAdd {
            self.insert(contact)
        }
        for contact in contactsToRemove {
            self.remove(contact)
        }
        displayedContactGroup?.updateUsingUnderlyingGroup()
    }
    
    func setContactIdentities(to contactIdentities: Set<ObvContactIdentity>) throws {
        guard let context = managedObjectContext else { return }
        guard !contactIdentities.isEmpty else { return }
        // We make sure all contact identities concern the same owned identity
        let ownedIdentities = Set(contactIdentities.map { $0.ownedIdentity })
        guard ownedIdentities.count == 1 else {
            throw ObvError(kind: .unexpecterCountOfOwnedIdentities(expected: 1, received: ownedIdentities.count))
        }
        let ownedIdentity = ownedIdentities.first!.cryptoId
        // Get the persisted contacts corresponding to the contact identities
        let cryptoIds = Set(contactIdentities.map { $0.cryptoId })
        let persistedContact = try PersistedObvContactIdentity.getAllContactsWithCryptoId(in: cryptoIds, ofOwnedIdentity: ownedIdentity, whereOneToOneStatusIs: .any, within: context)
        self.set(persistedContact)
    }

}


// MARK: - Managing PersistedPendingGroupMember

extension PersistedContactGroup {
    
    func setPendingMembers(to pendingIdentities: Set<ObvGenericIdentity>) throws {
        guard let context = managedObjectContext else {
            throw Self.makeError(message: "Could not find context")
        }
        let pendingMembers: Set<PersistedPendingGroupMember> = try Set(pendingIdentities.map { (obvGenericIdentity) in
            if let pendingMember = (self.pendingMembers.filter { $0.cryptoId == obvGenericIdentity.cryptoId }).first {
                return pendingMember
            } else {
                let newPendingMember = try PersistedPendingGroupMember(genericIdentity: obvGenericIdentity, contactGroup: self)
                self.insertedPendingMembers.insert(newPendingMember)
                return newPendingMember
            }
        })
        let pendingMembersToRemove = self.pendingMembers.subtracting(pendingMembers)
        for pendingMember in pendingMembersToRemove {
            context.delete(pendingMember)
        }
        displayedContactGroup?.updateUsingUnderlyingGroup()
    }

}


// MARK: - Convenience DB getters

extension PersistedContactGroup {
    
    struct Predicate {
        enum Key: String {
            case contactIdentities = "contactIdentities"
        }
        static func withOwnCryptoId(_ ownedIdentity: ObvCryptoId) -> NSPredicate {
            NSPredicate(format: "%K == %@", ownedIdentityIdentityKey, ownedIdentity.getIdentity() as NSData)
        }
        static func withPersistedObvOwnedIdentity(_ ownedIdentity: PersistedObvOwnedIdentity) -> NSPredicate {
            NSPredicate(format: "%K == %@", rawOwnedIdentityKey, ownedIdentity)
        }
        static func withContactIdentity(_ contactIdentity: PersistedObvContactIdentity) -> NSPredicate {
            NSPredicate(format: "%@ IN %K", contactIdentity, Predicate.Key.contactIdentities.rawValue)
        }
        static func withGroupId(_ groupId: (groupUid: UID, groupOwner: ObvCryptoId)) -> NSPredicate {
            NSPredicate(format: "%K == %@ AND %K == %@",
                        groupUidRawKey, groupId.groupUid.raw as NSData,
                        ownerIdentityKey, groupId.groupOwner.getIdentity() as NSData)
        }
    }
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedContactGroup> {
        return NSFetchRequest<PersistedContactGroup>(entityName: PersistedContactGroup.entityName)
    }


    static func getContactGroup(groupId: (groupUid: UID, groupOwner: ObvCryptoId), ownedIdentity: PersistedObvOwnedIdentity) throws -> PersistedContactGroup? {
        guard let context = ownedIdentity.managedObjectContext else { throw makeError(message: "Context is nil") }
        let request: NSFetchRequest<PersistedContactGroup> = PersistedContactGroup.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withGroupId(groupId),
            Predicate.withPersistedObvOwnedIdentity(ownedIdentity),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    static func getContactGroup(groupId: (groupUid: UID, groupOwner: ObvCryptoId), ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> PersistedContactGroup? {
        let request: NSFetchRequest<PersistedContactGroup> = PersistedContactGroup.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withGroupId(groupId),
            Predicate.withOwnCryptoId(ownedCryptoId),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    static func getPredicateForAllContactGroups(ownedIdentity: ObvCryptoId) -> NSPredicate {
        Predicate.withOwnCryptoId(ownedIdentity)
    }
    
    static func getFetchRequestForAllContactGroups(ownedIdentity: ObvCryptoId, andPredicate: NSPredicate?) -> NSFetchRequest<PersistedContactGroup> {
        var predicates = [getPredicateForAllContactGroups(ownedIdentity: ownedIdentity)]
        if andPredicate != nil {
            predicates.append(andPredicate!)
        }
        let request: NSFetchRequest<PersistedContactGroup> = PersistedContactGroup.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [
            NSSortDescriptor(key: rawCategoryKey, ascending: true),
            NSSortDescriptor(key: groupNameKey, ascending: true)
        ]
        return request
    }
    
    static func getFetchRequestForAllContactGroupsOfContact(_ persistedContact: PersistedObvContactIdentity) -> NSFetchRequest<PersistedContactGroup> {
        let request: NSFetchRequest<PersistedContactGroup> = PersistedContactGroup.fetchRequest()
        request.predicate = Predicate.withContactIdentity(persistedContact)
        request.sortDescriptors = [
            NSSortDescriptor(key: rawCategoryKey, ascending: true),
            NSSortDescriptor(key: groupNameKey, ascending: true)
        ]
        return request
    }

    static func getAllContactGroups(ownedIdentity: PersistedObvOwnedIdentity, within context: NSManagedObjectContext) throws -> Set<PersistedContactGroup> {
        let request: NSFetchRequest<PersistedContactGroup> = PersistedContactGroup.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", rawOwnedIdentityKey, ownedIdentity)
        return Set(try context.fetch(request))
    }
    
    
    static func getAllContactGroups(wherePendingMembersInclude contactIdentity: PersistedObvContactIdentity, within context: NSManagedObjectContext) throws -> Set<PersistedContactGroup> {
        let request: NSFetchRequest<PersistedContactGroup> = PersistedContactGroup.fetchRequest()
        request.predicate = NSPredicate(format: "%K.@count > 0", pendingMembersKey)
        let groups = Set(try context.fetch(request))
        return groups.filter { $0.pendingMembers.map({ $0.cryptoId }).contains(contactIdentity.cryptoId) }
    }
    
    static func getAllContactGroups(whereContactIdentitiesInclude contactIdentity: PersistedObvContactIdentity, within context: NSManagedObjectContext) throws -> Set<PersistedContactGroup> {
        let request: NSFetchRequest<PersistedContactGroup> = PersistedContactGroup.fetchRequest()
        request.predicate = NSPredicate(format: "%@ IN %K", contactIdentity, Predicate.Key.contactIdentities.rawValue)
        return Set(try context.fetch(request))
    }

    static func get(objectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> PersistedContactGroup? {
        return try context.existingObject(with: objectID) as? PersistedContactGroup
    }
    
}


// MARK: - Convenience NSFetchedResultsController creators

extension PersistedContactGroup {
    
    static func getFetchedResultsControllerForAllContactGroupsOfOwnedIdentity(with ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedContactGroup> {
        
        let fetchRequest: NSFetchRequest<PersistedContactGroup> = PersistedContactGroup.fetchRequest()
        
        fetchRequest.predicate = NSPredicate(format: "%K == %@",
                                             ownedIdentityIdentityKey, ownedCryptoId.getIdentity() as NSData)
        
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: rawCategoryKey, ascending: true), NSSortDescriptor(key: groupNameKey, ascending: true)]
        
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: rawCategoryKey,
                                                                  cacheName: nil)
        
        return fetchedResultsController
    }

    
    static func getFetchedResultsControllerForAllContactGroups(for contactIdentity: PersistedObvContactIdentity, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedContactGroup> {
        
        let fetchRequest: NSFetchRequest<PersistedContactGroup> = PersistedContactGroup.fetchRequest()
        
        fetchRequest.predicate = NSPredicate(format: "%@ IN %K",
                                             contactIdentity, Predicate.Key.contactIdentities.rawValue)
        
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: groupNameKey, ascending: true)]
        
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: nil,
                                                                  cacheName: nil)
        
        return fetchedResultsController
    }

    
}


// MARK: - Thread safe struct

extension PersistedContactGroup {
    
    struct Structure {
        
        let typedObjectID: TypeSafeManagedObjectID<PersistedContactGroup>
        let groupUid: UID
        let groupName: String
        let category: Category
        let displayPhotoURL: URL?
        let contactIdentities: Set<PersistedObvContactIdentity.Structure>
        
        private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "PersistedContactGroup.Structure")

    }
    
    func toStruct() throws -> Structure {
        let contactIdentities = Set(try self.contactIdentities.map { try $0.toStruct() })
        return Structure(typedObjectID: self.typedObjectID,
                         groupUid: self.groupUid,
                         groupName: self.groupName,
                         category: self.category,
                         displayPhotoURL: self.displayPhotoURL,
                         contactIdentities: contactIdentities)
    }
    
}


// MARK: - Sending notifications on change

extension PersistedContactGroup {
    
    override func willSave() {
        super.willSave()
        
        changedKeys = Set<String>(self.changedValues().keys)
    }
    
    override func didSave() {
        super.didSave()
        
        if changedKeys.contains(PersistedContactGroup.Predicate.Key.contactIdentities.rawValue) {
            
            let notification = ObvMessengerCoreDataNotification.persistedContactGroupHasUpdatedContactIdentities(persistedContactGroupObjectID: objectID,
                                                                                                                 insertedContacts: insertedContacts,
                                                                                                                 removedContacts: removedContacts)
            notification.postOnDispatchQueue()
            
        }
        
        changedKeys.removeAll()
        insertedContacts.removeAll()
        removedContacts.removeAll()
        insertedPendingMembers.removeAll()
    }
    
}
