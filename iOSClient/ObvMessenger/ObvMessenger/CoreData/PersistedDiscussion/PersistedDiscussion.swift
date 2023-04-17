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


@objc(PersistedDiscussion)
class PersistedDiscussion: NSManagedObject {

    private static let entityName = "PersistedDiscussion"
    private static let errorDomain = "PersistedDiscussion"
    
    private static func makeError(message: String, code: Int = 0) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: Self.errorDomain, code: code, userInfo: userInfo)
    }

    // Attributes
    
    @NSManaged var lastOutboundMessageSequenceNumber: Int
    @NSManaged var lastSystemMessageSequenceNumber: Int
    @NSManaged private var onChangeFlag: Int // Only used internally to trigger UI updates, transient
    @NSManaged private var rawStatus: Int
    @NSManaged private(set) var senderThreadIdentifier: UUID
    @NSManaged private(set) var timestampOfLastMessage: Date
    @NSManaged private(set) var title: String

    // Relationships

    @NSManaged private(set) var sharedConfiguration: PersistedDiscussionSharedConfiguration
    @NSManaged private(set) var localConfiguration: PersistedDiscussionLocalConfiguration
    @NSManaged private(set) var draft: PersistedDraft
    @NSManaged private(set) var messages: Set<PersistedMessage>
    @NSManaged private(set) var ownedIdentity: PersistedObvOwnedIdentity? // If nil, this entity is eventually cascade-deleted
    @NSManaged private(set) var remoteDeleteAndEditRequests: Set<RemoteDeleteAndEditRequest>
    
    // Other variables
    
    private var changedKeys = Set<String>()

    private(set) var status: Status {
        get {
            guard let status = Status(rawValue: rawStatus) else { assertionFailure(); return .active }
            return status
        }
        set {
            self.rawStatus = newValue.rawValue
        }
    }

    
    enum Status: Int {
        case preDiscussion = 0
        case active = 1
        case locked = 2
    }
    
    
    enum Kind {
        case oneToOne(withContactIdentity: PersistedObvContactIdentity?)
        case groupV1(withContactGroup: PersistedContactGroup?)
        case groupV2(withGroup: PersistedGroupV2?)
    }
    
    
    var kind: Kind {
        get throws {
            if let discussionOneToOne = self as? PersistedOneToOneDiscussion {
                return .oneToOne(withContactIdentity: discussionOneToOne.contactIdentity)
            } else if let discussionGroupV1 = self as? PersistedGroupDiscussion {
                return .groupV1(withContactGroup: discussionGroupV1.contactGroup)
            } else if let discussionGroupV2 = self as? PersistedGroupV2Discussion {
                return .groupV2(withGroup: discussionGroupV2.group)
            } else {
                assertionFailure()
                throw Self.makeError(message: "Unknown discussion type")
            }
        }
    }
    
    
    // MARK: - Initializer

    convenience init(title: String, ownedIdentity: PersistedObvOwnedIdentity, forEntityName entityName: String, status: Status, shouldApplySharedConfigurationFromGlobalSettings: Bool, sharedConfigurationToKeep: PersistedDiscussionSharedConfiguration? = nil, localConfigurationToKeep: PersistedDiscussionLocalConfiguration? = nil) throws {
        
        guard let context = ownedIdentity.managedObjectContext else {
            throw Self.makeError(message: "Could not find context")
        }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        self.lastOutboundMessageSequenceNumber = 0
        self.lastSystemMessageSequenceNumber = 0
        self.onChangeFlag = 0
        self.senderThreadIdentifier = UUID()
        self.timestampOfLastMessage = Date()
        self.title = title
        self.status = status
        
        if sharedConfigurationToKeep != nil {
            self.sharedConfiguration = sharedConfigurationToKeep!
        } else {
            let sharedConfiguration = try PersistedDiscussionSharedConfiguration(discussion: self)
            if shouldApplySharedConfigurationFromGlobalSettings {
                sharedConfiguration.setValuesUsingSettings()
            }
            self.sharedConfiguration = sharedConfiguration
        }
        
        let localConfiguration = try (localConfigurationToKeep ?? PersistedDiscussionLocalConfiguration(discussion: self))
        let draft = try PersistedDraft(within: self)
        self.localConfiguration = localConfiguration
        self.sharedConfiguration = sharedConfiguration
        self.draft = draft
        self.messages = Set<PersistedMessage>()
        self.ownedIdentity = ownedIdentity
        self.remoteDeleteAndEditRequests = Set<RemoteDeleteAndEditRequest>()
        
    }
    
    
    func setHasUpdates() {
        self.onChangeFlag += 1
    }

    
    func resetTimestampOfLastMessageIfCurrentValueIsEarlierThan(_ date: Date) {
        if self.timestampOfLastMessage < date {
            self.timestampOfLastMessage = date
        }
    }
    
    // MARK: Performing deletions
        
    /// Deletes this discussion after making sure the `requester` is allowed to do so. If the `requester` is `nil`, this discussion is deleted without any check. This makes it possible to easily perform cleaning.
    func deleteDiscussion(requester: RequesterOfMessageDeletion?) throws {
        
        // Make sure the deletion is allowed
        
        if let requester = requester {
            try throwIfRequesterIsNotAllowedToDeleteDiscussion(requester: requester)
        }
                
        // The deletion is allowed, we can perform it now
        
        guard let context = self.managedObjectContext else {
            throw Self.makeError(message: "Could not find context")
        }
        context.delete(self)
        
    }
    
    
    /// This methods throws an error if the requester of the discussion deletion is not allowed to perform such a deletion.
    ///
    /// The `deletionType` parameter only makes sense when the requester is an owned identity, and the discussion is a group v2 discussion:
    /// - for a `.local` deletion, deletion is always allowed
    /// - for a `.global` deletion, we make sure the owned identity is allowed to perform a global deletion in the corresponding group
    func throwIfRequesterIsNotAllowedToDeleteDiscussion(requester: RequesterOfMessageDeletion) throws {
        
        // Locked and preDiscussion can only be locally deleted by an owned identity
        
        switch status {
        case .locked, .preDiscussion:
            switch requester {
            case .contact:
                throw Self.makeError(message: "A contact cannot delete a locked or preDiscussion")
            case .ownedIdentity(let ownedCryptoId, let deletionType):
                guard let discussionOwnedCryptoId = ownedIdentity?.cryptoId else {
                    return // Rare case, we allow deletion
                }
                guard (discussionOwnedCryptoId == ownedCryptoId) else {
                    assertionFailure()
                    throw Self.makeError(message: "Unexpected owned identity for deleting this discussion")
                }
                switch deletionType {
                case .local:
                    return // Allow deletion
                case .global:
                    throw Self.makeError(message: "We cannot globally delete a locked or preDiscussion")
                }
            }
        case .active:
            break // We need to consider the discussion kind to decide whether we should throw or not
        }
        
        // If we reach this point, we are considering an active discussion

        switch try kind {
            
        case .oneToOne, .groupV1:
            
            // It is always ok to delete a oneToOne or a groupV1 discussion
            return
            
        case .groupV2(withGroup: let group):
                        
            guard let group = group else {
                
                // If the group cannot be found (which is unexpected), we allow the deletion of the discussion only if the request comes from an owned identity.

                switch requester {
                case .ownedIdentity(ownedCryptoId: _, deletionType: let deletionType):
                    switch deletionType {
                    case .local:
                        return // Allow deletion
                    case .global:
                        throw Self.makeError(message: "Since we cannot find the group, we disallow global deletion by owned identity")
                    }
                case .contact:
                    assertionFailure()
                    throw Self.makeError(message: "Since we cannot find the group, we disallow deletion by a contact")
                }

            }
            
            // For a group v2 discussion, we make sure the requester is either the owned identity or a member with the appropriate rights.

            switch requester {
                
            case .ownedIdentity(ownedCryptoId: let ownedCryptoId, deletionType: let deletionType):
                
                guard (try group.ownCryptoId == ownedCryptoId) else {
                    assertionFailure()
                    throw Self.makeError(message: "Unexpected owned identity for deleting this discussion")
                }
                switch deletionType {
                case .local:
                    return // Allow deletion
                case .global:
                    guard group.ownedIdentityIsAllowedToRemoteDeleteAnything else {
                        throw Self.makeError(message: "Owned identity is not allowed to perform a global (remote) delete")
                    }
                    return // Allow deletion
                }
                
            case .contact(let ownedCryptoId, let contactCryptoId, _):
                
                guard (try group.ownCryptoId == ownedCryptoId) else {
                    assertionFailure()
                    throw Self.makeError(message: "Unexpected owned identity associated to contact for deleting this discussion")
                }
                guard let member = group.otherMembers.first(where: { $0.identity == contactCryptoId.getIdentity() }) else {
                    throw Self.makeError(message: "The deletion requester is not part of the group")
                }
                guard member.isAllowedToRemoteDeleteAnything else {
                    assertionFailure()
                    throw Self.makeError(message: "The member is not allowed to delete this discussion")
                }
                return // Allow deletion
            }

        }
        
    }
    
    
    func requesterIsAllowedToDeleteDiscussion(requester: RequesterOfMessageDeletion) -> Bool {
        do {
            try throwIfRequesterIsNotAllowedToDeleteDiscussion(requester: requester)
        } catch {
            return false
        }
        return true
    }
    
    
    var globalDeleteActionCanBeMadeAvailable: Bool {
        guard let ownedCryptoId = ownedIdentity?.cryptoId else { return false }
        let requester = RequesterOfMessageDeletion.ownedIdentity(ownedCryptoId: ownedCryptoId, deletionType: .global)
        return requesterIsAllowedToDeleteDiscussion(requester: requester)
    }
    
    
    // MARK: - Status management

    func setStatus(to newStatus: Status) throws {
        self.status = newStatus
    }

}


// MARK: - Other methods

extension PersistedDiscussion {
    
    func resetTitle(to newTitle: String) throws {
        guard !newTitle.isEmpty else { throw Self.makeError(message: "The new title is empty") }
        if self.title != newTitle {
            self.title = newTitle
        }
    }

    func insertSystemMessagesIfDiscussionIsEmpty(markAsRead: Bool) throws {
        guard self.messages.isEmpty else { return }
        let systemMessage = try PersistedMessageSystem(.discussionIsEndToEndEncrypted, optionalContactIdentity: nil, optionalCallLogItem: nil, discussion: self)
        if markAsRead {
            systemMessage.status = .read
        }
        insertUpdatedDiscussionSharedSettingsSystemMessageIfRequired(markAsRead: markAsRead)
    }

    /// If the discussion has some ephemeral setting set (read once, limited visibility or limited existence), the method inserts a system message allowing the user to see what kind of ephemerality is set.
    func insertUpdatedDiscussionSharedSettingsSystemMessageIfRequired(markAsRead: Bool) {
        guard self.sharedConfiguration.isEphemeral else { return }
        let expirationJSON = self.sharedConfiguration.toExpirationJSON()
        try? PersistedMessageSystem.insertUpdatedDiscussionSharedSettingsSystemMessage(within: self, optionalContactIdentity: nil, expirationJSON: expirationJSON,  messageUploadTimestampFromServer: nil, markAsRead: markAsRead)
    }

    
    static func insertSystemMessagesIfDiscussionIsEmpty(discussionObjectID: NSManagedObjectID, markAsRead: Bool, within context: NSManagedObjectContext) throws {
        guard context.concurrencyType != .mainQueueConcurrencyType else { throw Self.makeError(message: "insertSystemMessagesIfDiscussionIsEmpty expects to be on background context") }
        guard let discussion = try PersistedDiscussion.get(objectID: discussionObjectID, within: context) else { throw Self.makeError(message: "Could not find discussion") }
        try discussion.insertSystemMessagesIfDiscussionIsEmpty(markAsRead: markAsRead)
    }
    
    
    func getAllActiveParticipants() throws -> (ownCryptoId: ObvCryptoId, contactCryptoIds: Set<ObvCryptoId>) {

        let contactCryptoIds: Set<ObvCryptoId>
        let ownCryptoId: ObvCryptoId

        switch try kind {

        case .oneToOne(withContactIdentity: let contactIdentity):
            
            guard let contactIdentity = contactIdentity else {
                throw Self.makeError(message: "Could not find contact identity")
            }
            guard let oneToOneDiscussion = self as? PersistedOneToOneDiscussion else {
                assertionFailure()
                throw Self.makeError(message: "Unexpected discussion kind")
            }
            contactCryptoIds = contactIdentity.isActive ? Set([contactIdentity.cryptoId]) : Set([])
            guard let _ownCryptoId = oneToOneDiscussion.ownedIdentity?.cryptoId else {
                throw Self.makeError(message: "Could not determine owned cryptoId (1)")
            }
            ownCryptoId = _ownCryptoId
            
        case .groupV1(withContactGroup: let group):
            
            guard let contactGroup = group else {
                throw Self.makeError(message: "Could not find contact group")
            }
            guard let _ownCryptoId = ownedIdentity?.cryptoId else {
                throw Self.makeError(message: "Could not determine owned cryptoId (2)")
            }
            ownCryptoId = _ownCryptoId
            switch contactGroup.category {
            case .owned:
                contactCryptoIds = Set(contactGroup.contactIdentities.filter({ $0.isActive }).map({ $0.cryptoId }))
            case .joined:
                guard let groupOwner = try? ObvCryptoId(identity: contactGroup.ownerIdentity) else {
                    throw Self.makeError(message: "Could not determine group owner")
                }
                assert(groupOwner != ownCryptoId)
                var cryptoIds = Set(contactGroup.contactIdentities.filter({ $0.isActive }).compactMap({ $0.cryptoId == ownCryptoId ? nil : $0.cryptoId }))
                assert((contactGroup as? PersistedContactGroupJoined)?.owner != nil)
                if (contactGroup as? PersistedContactGroupJoined)?.owner?.isActive == true {
                    cryptoIds.insert(groupOwner)
                }
                contactCryptoIds = cryptoIds
            }
            
        case .groupV2(withGroup: let group):
            
            guard let group = group else {
                throw Self.makeError(message: "Could not find group v2")
            }
            
            ownCryptoId = try group.ownCryptoId
            contactCryptoIds = Set(group.contactsAmongNonPendingOtherMembers.filter({ $0.isActive }).map({ $0.cryptoId }))

        }
        
        return (ownCryptoId, contactCryptoIds)
        
    }
    

    var isCallAvailable: Bool {
        switch self.status {
        case .preDiscussion, .locked:
            return false
        case .active:
            switch try? self.kind {
            case .oneToOne:
                return true
            case .groupV1(withContactGroup: let contactGroup):
                if let contactGroup = contactGroup {
                    return !contactGroup.contactIdentities.isEmpty
                } else {
                    return false
                }
            case .groupV2(withGroup: let group):
                if let group = group {
                    return !group.otherMembers.isEmpty
                } else {
                    return false
                }
            case .none:
                assertionFailure()
                return false
            }
        }
    }
    
    var subtitle: String {
        if let oneToOne = self as? PersistedOneToOneDiscussion {
            return oneToOne.contactIdentity?.identityCoreDetails.positionAtCompany() ?? ""
        } else if let groupDiscussion = self as? PersistedGroupDiscussion {
            return groupDiscussion.contactGroup?.sortedContactIdentities.map({ $0.customOrFullDisplayName }).joined(separator: ", ") ?? ""
        } else if let groupDiscussion = self as? PersistedGroupV2Discussion {
            return groupDiscussion.group?.otherMembersSorted.compactMap({ $0.displayedCustomDisplayNameOrFirstNameOrLastName }).joined(separator: ", ") ?? ""
        } else {
            assertionFailure()
            return ""
        }
    }
    
    
    /// This variable is `true` iff the owned identity is allowed to send messages within this discussion.
    /// In oneToOne and group V1 discussions, the owned identity is always allowed to send messages.
    /// For group V2 discussions, it depends from the rights of the owned identity.
    var ownedIdentityIsAllowedToSendMessagesInThisDiscussion: Bool {
        get throws {
            switch try self.kind {
            case .oneToOne, .groupV1:
                return true // We are always allowed to send messages in oneToOne and groupV1 discussions
            case .groupV2(withGroup: let group):
                guard let group = group else { return false }
                return group.ownedIdentityIsAllowedToSendMessage
            }
        }
    }
    
}

// MARK: - Retention related methods

extension PersistedDiscussion {
    
    /// If `nil`, no message should be deleted because of time retention. Otherwise, the return
    /// date is the limit date for retention.
    ///
    /// If the non `nil`:
    /// - Outbound messages that were sent before this date should be deleted
    /// - Non-new inbound messages that were received before this date should be deleted
    var effectiveTimeBasedRetentionDate: Date? {
        guard let timeInterval = self.effectiveTimeIntervalRetention else { return nil }
        return Date(timeIntervalSinceNow: -timeInterval)
    }
    
    var effectiveTimeIntervalRetention: TimeInterval? {
        switch localConfiguration.timeBasedRetention {
        case .useAppDefault:
            guard let timeInterval = ObvMessengerSettings.Discussions.timeBasedRetentionPolicy.timeInterval else { return nil }
            return timeInterval
        default:
            return localConfiguration.timeBasedRetention.timeInterval
        }
    }
    
    var effectiveCountBasedRetention: Int? {
        switch localConfiguration.countBasedRetentionIsActive {
        case .none:
            // Use the app default configuration to know whether we should return a value
            guard ObvMessengerSettings.Discussions.countBasedRetentionPolicyIsActive else { return nil }
            // If we reach this point, there is a count-based retention policy that applies.
            // If it exists, the local count based superseeds the app default count based retention.
            return localConfiguration.countBasedRetention ?? ObvMessengerSettings.Discussions.countBasedRetentionPolicy
        case .some(true):
            return localConfiguration.countBasedRetention ?? ObvMessengerSettings.Discussions.countBasedRetentionPolicy
        case .some(false):
            return nil
        }
    }
    
}

// MARK: - Configuration related methods

extension PersistedDiscussion {

    var autoRead: Bool {
        localConfiguration.autoRead ?? ObvMessengerSettings.Discussions.autoRead
    }

    var retainWipedOutboundMessages: Bool {
        localConfiguration.retainWipedOutboundMessages ?? ObvMessengerSettings.Discussions.retainWipedOutboundMessages
    }

    var shouldMuteNotifications: Bool {
        return localConfiguration.shouldMuteNotifications
    }

}

// MARK: - Convenience DB getters

extension PersistedDiscussion {

    struct Predicate {
        enum Key: String {
            case lastOutboundMessageSequenceNumber = "lastOutboundMessageSequenceNumber"
            case lastSystemMessageSequenceNumber = "lastSystemMessageSequenceNumber"
            case onChangeFlag = "onChangeFlag"
            case rawStatus = "rawStatus"
            case senderThreadIdentifier = "senderThreadIdentifier"
            case timestampOfLastMessage = "timestampOfLastMessage"
            case title = "title"
            case sharedConfiguration = "sharedConfiguration"
            case localConfiguration = "localConfiguration"
            case draft = "draft"
            case messages = "messages"
            case ownedIdentity = "ownedIdentity"
            case remoteDeleteAndEditRequests = "remoteDeleteAndEditRequests"
            static var ownedIdentityIdentity: String {
                [Key.ownedIdentity.rawValue, PersistedObvOwnedIdentity.identityKey].joined(separator: ".")
            }
        }
        static func withOwnCryptoId(_ ownCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.ownedIdentityIdentity, EqualToData: ownCryptoId.getIdentity())
        }
        static func persistedDiscussion(withObjectID objectID: NSManagedObjectID) -> NSPredicate {
            NSPredicate(format: "SELF == %@", objectID)
        }
        static func withStatus(_ status: Status) -> NSPredicate {
            NSPredicate(Key.rawStatus, EqualToInt: status.rawValue)
        }
        static var withNoMessage: NSPredicate {
            NSPredicate(format: "%K.@count == 0", PersistedDiscussion.Predicate.Key.messages.rawValue)
        }
        static var withMessages: NSPredicate {
            NSPredicate(format: "%K.@count > 0", PersistedDiscussion.Predicate.Key.messages.rawValue)
        }
        static fileprivate var isPersistedGroupDiscussion: NSPredicate {
            NSPredicate(withEntity: PersistedGroupDiscussion.entity())
        }
        static fileprivate var isPersistedGroupV2Discussion: NSPredicate {
            NSPredicate(withEntity: PersistedGroupV2Discussion.entity())
        }
        static fileprivate var isGroupDiscussion: NSPredicate {
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                isPersistedGroupDiscussion,
                isPersistedGroupV2Discussion,
            ])
        }
    }
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedDiscussion> {
        return NSFetchRequest<PersistedDiscussion>(entityName: PersistedDiscussion.entityName)
    }
    
    
    static func get(objectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> PersistedDiscussion? {
        let request: NSFetchRequest<PersistedDiscussion> = PersistedDiscussion.fetchRequest()
        request.predicate = Predicate.persistedDiscussion(withObjectID: objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func get(objectID: TypeSafeManagedObjectID<PersistedDiscussion>, within context: NSManagedObjectContext) throws -> PersistedDiscussion? {
        return try get(objectID: objectID.objectID, within: context)
    }

    static func getAllSortedByTimestampOfLastMessage(within context: NSManagedObjectContext) throws -> [PersistedDiscussion] {
        let request: NSFetchRequest<PersistedDiscussion> = PersistedDiscussion.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.timestampOfLastMessage.rawValue, ascending: false)]
        return try context.fetch(request)
    }
    
    
    static func getTotalCount(within context: NSManagedObjectContext) throws -> Int {
        let request: NSFetchRequest<PersistedDiscussion> = PersistedDiscussion.fetchRequest()
        return try context.count(for: request)
    }
    
    static func getAllActiveDiscussionsForAllOwnedIdentities(within context: NSManagedObjectContext) throws -> [PersistedDiscussion] {
        let request: NSFetchRequest<PersistedDiscussion> = PersistedDiscussion.fetchRequest()
        request.predicate = Predicate.withStatus(.active)
        request.fetchBatchSize = 500
        return try context.fetch(request)
    }

}


// MARK: - NSFetchRequest creators

extension PersistedDiscussion {
    
    /// Returns a `NSFetchRequest` for all the group discussions (both V1 and V2) of the owned identity, sorted by the discussion title.
    static func getFetchRequestForAllGroupDiscussionsSortedByTitleForOwnedIdentity(with ownedCryptoId: ObvCryptoId) -> NSFetchRequest<PersistedDiscussion> {
        let fetchRequest: NSFetchRequest<PersistedDiscussion> = PersistedDiscussion.fetchRequest()
        
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnCryptoId(ownedCryptoId),
            Predicate.isGroupDiscussion,
        ])
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.title.rawValue, ascending: true)]
        return fetchRequest
    }

    /// Returns a `NSFetchRequest` for the non-empty discussions of the owned identity, sorted by the timestamp of the last message of each discussion.
    static func getFetchRequestForNonEmptyRecentDiscussionsForOwnedIdentity(with ownedCryptoId: ObvCryptoId) -> NSFetchRequest<PersistedDiscussion> {
        
        let fetchRequest: NSFetchRequest<PersistedDiscussion> = PersistedDiscussion.fetchRequest()
        
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "%K == %@", Predicate.Key.ownedIdentityIdentity, ownedCryptoId.getIdentity() as NSData),
            Predicate.withMessages,
        ])
        
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.timestampOfLastMessage.rawValue, ascending: false)]

        return fetchRequest
    }

    /// Returns a `NSFetchRequest` for the non-empty and active discussions of the owned identity, sorted by the timestamp of the last message of each discussion.
    static func getFetchRequestForAllActiveRecentDiscussionsForOwnedIdentity(with ownedCryptoId: ObvCryptoId) -> NSFetchRequest<PersistedDiscussion> {

        let fetchRequest: NSFetchRequest<PersistedDiscussion> = PersistedDiscussion.fetchRequest()

        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "%K == %@", Predicate.Key.ownedIdentityIdentity, ownedCryptoId.getIdentity() as NSData),
            Predicate.withStatus(.active)
        ])

        fetchRequest.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.timestampOfLastMessage.rawValue, ascending: false)]

        return fetchRequest
    }
    
    static func getFetchedResultsController(fetchRequest: NSFetchRequest<PersistedDiscussion>, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedDiscussion> {
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: nil,
                                                                  cacheName: nil)
        return fetchedResultsController
    }
        
    
    static func getAllLockedWithNoMessage(within context: NSManagedObjectContext) throws -> [PersistedDiscussion] {
        let request: NSFetchRequest<PersistedDiscussion> = PersistedDiscussion.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withStatus(.locked),
            Predicate.withNoMessage,
        ])
        return try context.fetch(request)
    }


}


// MARK: - Thread safe struct

extension PersistedDiscussion {
    
    struct AbstractStructure {
        let title: String
        let localConfiguration: PersistedDiscussionLocalConfiguration.Structure
    }
    
    func toAbstractStruct() throws -> AbstractStructure {
        return AbstractStructure(title: self.title,
                                 localConfiguration: try self.localConfiguration.toStructure())
    }
    
    enum StructureKind {
        case oneToOneDiscussion(structure: PersistedOneToOneDiscussion.Structure)
        case groupDiscussion(structure: PersistedGroupDiscussion.Structure)
        case groupV2Discussion(structure: PersistedGroupV2Discussion.Structure)

        var typedObjectID: TypeSafeManagedObjectID<PersistedDiscussion> {
            switch self {
            case .groupDiscussion(let structure):
                return structure.typedObjectID.downcast
            case .oneToOneDiscussion(let structure):
                return structure.typedObjectID.downcast
            case .groupV2Discussion(let structure):
                return structure.typedObjectID.downcast
            }
        }
        var title: String {
            switch self {
            case .groupDiscussion(let structure):
                return structure.title
            case .oneToOneDiscussion(let structure):
                return structure.title
            case .groupV2Discussion(let structure):
                return structure.title
            }
        }
        var localConfiguration: PersistedDiscussionLocalConfiguration.Structure {
            switch self {
            case .groupDiscussion(let structure):
                return structure.localConfiguration
            case .oneToOneDiscussion(let structure):
                return structure.localConfiguration
            case .groupV2Discussion(let structure):
                return structure.localConfiguration
            }
        }
    }
    
    func toStruct() throws -> StructureKind {
        switch try kind {
        case .oneToOne:
            guard let oneToOneDiscussion = self as? PersistedOneToOneDiscussion else {
                throw Self.makeError(message: "Internal error")
            }
            return .oneToOneDiscussion(structure: try oneToOneDiscussion.toStruct())
        case .groupV1:
            guard let groupDiscussion = self as? PersistedGroupDiscussion else {
                throw Self.makeError(message: "Internal error")
            }
            return .groupDiscussion(structure: try groupDiscussion.toStruct())
        case .groupV2:
            guard let groupV2Discussion = self as? PersistedGroupV2Discussion else {
                throw Self.makeError(message: "Internal error")
            }
            return .groupV2Discussion(structure: try groupV2Discussion.toStruct())
        }
    }
    
}


// MARK: - Sending notifications on changes

extension PersistedDiscussion {
    
    override func willSave() {
        super.willSave()
        
        if isUpdated {
            changedKeys = Set<String>(self.changedValues().keys)
        }
        
    }


    override func didSave() {
        super.didSave()
        
        if changedKeys.contains(Predicate.Key.title.rawValue) {
            ObvMessengerCoreDataNotification.persistedDiscussionHasNewTitle(objectID: typedObjectID, title: title)
                .postOnDispatchQueue()
        }
        
        if changedKeys.contains(Predicate.Key.rawStatus.rawValue), !isDeleted {
            ObvMessengerCoreDataNotification.persistedDiscussionStatusChanged(objectID: typedObjectID, newStatus: status)
                .postOnDispatchQueue()
        }

        if isDeleted {
            ObvMessengerCoreDataNotification.persistedDiscussionWasDeleted(discussionUriRepresentation: typedObjectID.uriRepresentation()).postOnDispatchQueue()
        }       
    }
    
}
