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
import ObvEngine


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
    @NSManaged var timestampOfLastMessage: Date
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
    }
    
    
    var kind: Kind {
        get throws {
            if let discussionOneToOne = self as? PersistedOneToOneDiscussion {
                return .oneToOne(withContactIdentity: discussionOneToOne.contactIdentity)
            } else if let discussionGroupV1 = self as? PersistedGroupDiscussion {
                return .groupV1(withContactGroup: discussionGroupV1.contactGroup)
            } else {
                assertionFailure()
                throw Self.makeError(message: "Unknown discussion type")
            }
        }
    }
    
    
    // MARK: - Initializer

    convenience init(title: String, ownedIdentity: PersistedObvOwnedIdentity, forEntityName entityName: String, status: Status, sharedConfigurationToKeep: PersistedDiscussionSharedConfiguration? = nil, localConfigurationToKeep: PersistedDiscussionLocalConfiguration? = nil) throws {
        
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
            switch try self.kind {
            case .oneToOne:
                sharedConfiguration.setValuesUsingSettings()
            case .groupV1(withContactGroup: let contactGroup):
                if let contactGroup = contactGroup, contactGroup.category == .owned {
                    sharedConfiguration.setValuesUsingSettings()
                }
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

    
    func delete() throws {
        guard let context = self.managedObjectContext else {
            throw Self.makeError(message: "Could not find context")
        }
        context.delete(self)
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
        if self.sharedConfiguration.isEphemeral {
            let expirationJSON = self.sharedConfiguration.toExpirationJSON()
            try? PersistedMessageSystem.insertUpdatedDiscussionSharedSettingsSystemMessage(within: self, optionalContactIdentity: nil, expirationJSON: expirationJSON, messageUploadTimestampFromServer: nil)
        }
        if markAsRead {
            systemMessage.status = .read
        }
    }

    
    static func insertSystemMessagesIfDiscussionIsEmpty(discussionObjectID: NSManagedObjectID, markAsRead: Bool, within context: NSManagedObjectContext) throws {
        guard context.concurrencyType != .mainQueueConcurrencyType else { throw Self.makeError(message: "insertSystemMessagesIfDiscussionIsEmpty expects to be on background context") }
        guard let discussion = try PersistedDiscussion.get(objectID: discussionObjectID, within: context) else { throw Self.makeError(message: "Could not find discussion") }
        try discussion.insertSystemMessagesIfDiscussionIsEmpty(markAsRead: markAsRead)
    }
    
    
    func getAllActiveParticipants() throws -> (ownCryptoId: ObvCryptoId, contactCryptoIds: Set<ObvCryptoId>) {
        let contactCryptoIds: Set<ObvCryptoId>
        let ownCryptoId: ObvCryptoId
        if let oneToOneDiscussion = self as? PersistedOneToOneDiscussion {
            guard let contactIdentity = oneToOneDiscussion.contactIdentity else {
                throw Self.makeError(message: "Could not find contact identity")
            }
            contactCryptoIds = contactIdentity.isActive ? Set([contactIdentity.cryptoId]) : Set([])
            guard let _ownCryptoId = oneToOneDiscussion.ownedIdentity?.cryptoId else {
                throw Self.makeError(message: "Could not determine owned cryptoId (1)")
            }
            ownCryptoId = _ownCryptoId
        } else if let groupDiscussion = self as? PersistedGroupDiscussion {
            guard let contactGroup = groupDiscussion.contactGroup else {
                throw Self.makeError(message: "Could not find contact group")
            }
            guard let _ownCryptoId = groupDiscussion.ownedIdentity?.cryptoId else {
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
        } else {
            throw Self.makeError(message: "Unexpected discussion type: \(type(of: self))")
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
        } else {
            assertionFailure()
            return ""
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
    
}


// MARK: - NSFetchRequest creators

extension PersistedDiscussion {
    
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
        case groupDiscussion(structure: PersistedGroupDiscussion.Structure)
        case oneToOneDiscussion(structure: PersistedOneToOneDiscussion.Structure)
        var objectID: NSManagedObjectID {
            switch self {
            case .groupDiscussion(let structure):
                return structure.typedObjectID.objectID
            case .oneToOneDiscussion(let structure):
                return structure.typedObjectID.objectID
            }
        }
        var title: String {
            switch self {
            case .groupDiscussion(let structure):
                return structure.title
            case .oneToOneDiscussion(let structure):
                return structure.title
            }
        }
        var localConfiguration: PersistedDiscussionLocalConfiguration.Structure {
            switch self {
            case .groupDiscussion(let structure):
                return structure.localConfiguration
            case .oneToOneDiscussion(let structure):
                return structure.localConfiguration
            }
        }
    }
    
    func toStruct() throws -> StructureKind {
        if let oneToOneDiscussion = self as? PersistedOneToOneDiscussion {
            return .oneToOneDiscussion(structure: try oneToOneDiscussion.toStruct())
        } else if let groupDiscussion = self as? PersistedGroupDiscussion {
            return .groupDiscussion(structure: try groupDiscussion.toStruct())
        } else {
            throw Self.makeError(message: "Unexpected discussion type")
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
            ObvMessengerCoreDataNotification.persistedDiscussionStatusChanged(objectID: typedObjectID)
                .postOnDispatchQueue()
        }

        if isDeleted {
            ObvMessengerCoreDataNotification.persistedDiscussionWasDeleted(discussionUriRepresentation: typedObjectID.uriRepresentation()).postOnDispatchQueue()
        }       
    }
    
}
