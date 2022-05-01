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
import ObvTypes
import ObvEngine
import os.log
import OlvidUtils
import UniformTypeIdentifiers

enum PersistedMessageKind {
    case none
    case received
    case sent
    case system
}

@objc(PersistedMessage)
class PersistedMessage: NSManagedObject {

    static let PersistedMessageEntityName = "PersistedMessage"

    static let bodyKey = "body"
    static let rawStatusKey = "rawStatus"
    static let rawVisibilityDurationKey = "rawVisibilityDuration"
    static let readOnceKey = "readOnce"
    static let sectionIdentifierKey = "sectionIdentifier"
    static let senderSequenceNumberKey = "senderSequenceNumber"
    static let sortIndexKey = "sortIndex"
    static let timestampKey = "timestamp"
    static let discussionKey = "discussion"
    static let readOnceToBeDeletedKey = "readOnceToBeDeleted"
    static let muteNotificationsEndDateKey = [discussionKey, PersistedDiscussion.localConfigurationKey, PersistedDiscussionLocalConfiguration.muteNotificationsEndDateKey].joined(separator: ".")
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "PersistedMessage")

    private static func makeError(message: String) -> Error { NSError(domain: String(describing: Self.self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { PersistedMessage.makeError(message: message) }
    
    // MARK: - Attributes

    @NSManaged private var body: String?
    @NSManaged var isReplyToAnotherMessage: Bool
    @NSManaged var readOnce: Bool
    @NSManaged var rawStatus: Int
    @NSManaged private var rawVisibilityDuration: NSNumber?
    @NSManaged private(set) var sectionIdentifier: String
    @NSManaged private(set) var senderSequenceNumber: Int
    @NSManaged private(set) var sortIndex: Double
    @NSManaged private(set) var timestamp: Date

    // MARK: - Relationships

    @NSManaged private(set) var discussion: PersistedDiscussion
    @NSManaged private(set) var rawMessageRepliedTo: PersistedMessage? // Should *only* be accessed from subentities
    @NSManaged private var persistedMetadata: Set<PersistedMessageTimestampedMetadata>
    @NSManaged private var rawReactions: [PersistedMessageReaction]?

    // MARK: - Other variables

    var kind: PersistedMessageKind {
        assertionFailure("Kind must be overriden in subclasses")
        return .none
    }
    
    var visibilityDuration: TimeInterval? {
        get {
            guard let seconds = rawVisibilityDuration?.intValue else { return nil }
            return TimeInterval(seconds)
        }
        set {
            self.rawVisibilityDuration = (newValue == nil ? nil : NSNumber(value: newValue!) )
        }
    }
    
    var reactions: [PersistedMessageReaction] {
        rawReactions ?? []
    }

    @objc(textBody)
    var textBody: String? {
        if body == nil || body?.isEmpty == true { return nil }
        // Override in PersistedMessageReceived
        return self.body
    }
    
    var textBodyToSend: String? { self.body }

    func deleteBody() {
        self.body = nil
    }

    var autoRead: Bool {
        self.discussion.autoRead
    }

    var retainWipedOutboundMessages: Bool {
        self.discussion.retainWipedOutboundMessages
    }

    var initialExistenceDuration: TimeInterval? {
        if let sentMessage = self as? PersistedMessageSent {
            return sentMessage.existenceDuration
        } else {
            // Override in PersistedMessageReceived
            assert(kind == .system)
            return nil
        }
    }
    
    var isLocallyWiped: Bool {
        self.persistedMetadata.first(where: { $0.kind == .wiped }) != nil
    }

    var isRemoteWiped: Bool {
        for meta in self.persistedMetadata {
            switch meta.kind {
            case .remoteWiped: return true
            default: continue
            }
        }
        return false
    }

    var isWiped: Bool { isLocallyWiped || isRemoteWiped }

    /// `true` when this instance can be edited after being sent.
    var textBodyCanBeEdited: Bool { false }

    /// Shall only be called from the overriding method in `PersistedMessageSent`
    @objc func editTextBody(newTextBody: String?) throws {
        guard self.textBodyCanBeEdited else {
            throw makeError(message: "The text body of this message cannot be edited now")
        }
        self.body = newTextBody
    }

    var isEdited: Bool {
        self.metadata.first(where: { $0.kind == .edited }) != nil
    }

    var isNumberOfNewMessagesMessageSystem: Bool {
        // Overriden in PersistedMessageSystem
        return false
    }
    
    /// This method is specific to system messages, when their category is `numberOfNewMessages`.
    func resetSortIndexOfNumberOfNewMessagesSystemMessage(to newSortIndex: Double) throws {
        guard isNumberOfNewMessagesMessageSystem else { throw makeError(message: "Cannot reset sort index of this message type") }
        self.sortIndex = newSortIndex
    }
    
    @available(iOS 14, *)
    static let supportedImageTypeIdentifiers = Set<String>(([UTType.jpeg.identifier,
                                                             UTType.png.identifier,
                                                             UTType.gif.identifier,
                                                             UTType.heic.identifier ]))

    func toMessageReferenceJSON() -> MessageReferenceJSON? {
        assertionFailure("We do not expect this function to be called on anything else than a PersistedMessageSent or a PersistedMessageReceived where this function is overriden")
        return nil
    }

    var fyleMessageJoinWithStatus: [FyleMessageJoinWithStatus]? { nil }

    var messageIdentifiersFromEngine: Set<Data> { Set() }

    var genericRepliesTo: RepliedMessage { .none }

}

// MARK: - Errors

extension PersistedMessage {
    
    struct ObvError: LocalizedError {
        
        let kind: Kind
        
        enum Kind {
            case managedContextIsNil
        }
        
        var errorDescription: String? {
            switch kind {
            case .managedContextIsNil:
                return "The managed context is nil, which is unexpected"
            }
        }
        
    }
    
}


// MARK: - Initializer

extension PersistedMessage {
    
    convenience init(timestamp: Date, body: String?, rawStatus: Int, senderSequenceNumber: Int, sortIndex: Double, isReplyToAnotherMessage: Bool, replyTo: PersistedMessage?, discussion: PersistedDiscussion, readOnce: Bool, visibilityDuration: TimeInterval?, forEntityName entityName: String) throws {
        
        guard let context = discussion.managedObjectContext else { assertionFailure(); throw PersistedMessage.makeError(message: "Could not find context") }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.body = body
        self.isReplyToAnotherMessage = isReplyToAnotherMessage
        self.rawMessageRepliedTo = replyTo
        self.rawStatus = rawStatus
        self.sectionIdentifier = try PersistedMessage.computeSectionIdentifier(fromTimestamp: timestamp, sortIndex: sortIndex, discussion: discussion)
        self.senderSequenceNumber = senderSequenceNumber
        self.discussion = discussion
        self.sortIndex = sortIndex
        self.timestamp = timestamp
        self.readOnce = readOnce
        self.visibilityDuration = visibilityDuration

        discussion.timestampOfLastMessage = max(self.timestamp, discussion.timestampOfLastMessage)
        
    }

    
    /// This `update()` method shall *only* be called from the similar `update()` from the subclasse `PersistedMessageReceived`.
    func update(body: String?, senderSequenceNumber: Int, replyTo: PersistedMessage?, discussion: PersistedDiscussion) throws {
        guard self.discussion.objectID == discussion.objectID else { assertionFailure(); throw makeError(message: "Invalid discussion") }
        guard self.senderSequenceNumber == senderSequenceNumber else { assertionFailure(); throw makeError(message: "Invalid sender sequence number") }
        self.body = body
        self.rawMessageRepliedTo = replyTo
    }
    
    
    func delete() throws {
        guard let context = self.managedObjectContext else { assertionFailure(); throw makeError(message: "Could not find context") }
        context.delete(self)
    }

    /// Should *only* be called from `PersistedMessageReceived`
    func setRawMessageRepliedTo(with rawMessageRepliedTo: PersistedMessage) {
        assert(kind == .received)
        self.rawMessageRepliedTo = rawMessageRepliedTo
    }
    
}


// MARK: - Reply-to

extension PersistedMessage {

    enum RepliedMessage {
        case none
        case notAvailableYet
        case available(message: PersistedMessage)
        case deleted
    }

}



// MARK: - Reactions Util

extension PersistedMessage {

    private func reactionFromContact(with cryptoId: ObvCryptoId) -> PersistedMessageReactionReceived? {
        let contactsReactions = reactions.compactMap { $0 as? PersistedMessageReactionReceived }
        let contactReactions = contactsReactions.filter {
            guard let reactionCryptoId = $0.contact?.cryptoId else { return false }
            return reactionCryptoId == cryptoId
        }
        assert(contactReactions.count <= 1)
        return contactReactions.first
    }


    func reactionFromOwnedIdentity() -> PersistedMessageReactionSent? {
        let ownedReactions = reactions.compactMap { $0 as? PersistedMessageReactionSent }
        assert(ownedReactions.count <= 1)
        return ownedReactions.first
    }
    
    
    func setReactionFromOwnedIdentity(withEmoji emoji: String?, reactionTimestamp: Date) throws {
        // Never set an emoji on a wiped message
        guard !self.isWiped else { return }
        if let reaction = reactionFromOwnedIdentity() {
            try reaction.updateEmoji(with: emoji, at: reactionTimestamp)
        } else if let emoji = emoji {
            _ = try PersistedMessageReactionSent(emoji: emoji, timestamp: reactionTimestamp, message: self)
        } else {
            // The new emoji is nil (meaning we should remove a previous reaction) and no previous reaction can be found. There is nothing to do.
        }
    }

    
    func setReactionFromContact(_ contact: PersistedObvContactIdentity, withEmoji emoji: String?, reactionTimestamp: Date) throws {
        // Never set an emoji on a wiped message
        guard !self.isWiped else { return }
        if let contactReaction = reactionFromContact(with: contact.cryptoId) {
            try contactReaction.updateEmoji(with: emoji, at: reactionTimestamp)
        } else if let emoji = emoji {
            _ = try PersistedMessageReactionReceived(emoji: emoji, timestamp: reactionTimestamp, message: self, contact: contact)
        } else {
            // The new emoji is nil (meaning we should remove a previous reaction) and no previous reaction can be found. There is nothing to do.
        }
    }
    
}

// MARK: - Utils for section identifiers

extension PersistedMessage {

    private static func computeSectionIdentifier(fromTimestamp timestamp: Date, sortIndex: Double, discussion: PersistedDiscussion) throws -> String {
        let calendar = Calendar.current
        let dateComponents = Set<Calendar.Component>([.year, .month, .day])
        let components = calendar.dateComponents(dateComponents, from: timestamp)
        let computedSectionIdentifier = String(format: "%ld", components.year!*10000 + components.month!*100 + components.day!)

        /* Before returning the section identifier, we make sure that the `sectionIdentifier` of this message is not
         * conflicting with the ones of the previous and next messages:
         * - If a previous message exists, we must have appropriateSectionIdentifier >= prevMsg.sectionIdentifier
         * - If a next message exists,  we must have appropriateSectionIdentifier <= nextMsg.sectionIdentifier
         * At least one constraint will be verified. If one is not, we use the "bound" as the appropriateSectionIdentifier.
         * If both constraints are ok, we use the computedSectionIdentifier as the appropriate section identifier.
         */

        let appropriateSectionIdentifier: String
        if let previousMessageValues = try PersistedMessage.getMessageValues(beforeSortIndex: sortIndex, in: discussion, propertiesToFetch: [sectionIdentifierKey]),
           let sectionIdentifier = previousMessageValues[sectionIdentifierKey] as? String,
           sectionIdentifier > computedSectionIdentifier {
            appropriateSectionIdentifier = sectionIdentifier
        } else if let nextMessageValues = try PersistedMessage.getMessageValues(afterSortIndex: sortIndex, in: discussion, propertiesToFetch: [sectionIdentifierKey]),
                  let sectionIdentifier = nextMessageValues[sectionIdentifierKey] as? String,
                  sectionIdentifier < computedSectionIdentifier {
            appropriateSectionIdentifier = sectionIdentifier
        } else {
            appropriateSectionIdentifier = computedSectionIdentifier
        }

        return appropriateSectionIdentifier
    }


    static func getSectionTitle(fromSectionIdentifier sectionIdentifier: String, usingDateFormatter df: DateFormatter) -> String? {
        guard let components = getDateComponents(fromSectionIdentifier: sectionIdentifier) else { return nil }
        guard let date = components.date else { return nil }
        return df.string(from: date)
    }


    static func getDateComponents(fromSectionIdentifier sectionIdentifier: String) -> DateComponents? {
        guard var numeric = Int(sectionIdentifier) else { return nil }
        let calendar = Calendar.current
        let year = numeric / 10000
        numeric -= year * 10000
        let month = numeric / 100
        numeric -= month * 100
        let day = numeric
        let components = DateComponents(calendar: calendar, year: year, month: month, day: day)
        return components
    }

}

// MARK: - Convenience DB getters

extension PersistedMessage {

    struct Predicate {
        static var readOnceToBeDeleted: NSPredicate {
            NSPredicate(format: "\(PersistedMessage.readOnceToBeDeletedKey) == TRUE")
        }
        static func withinDiscussion(_ discussion: PersistedDiscussion) -> NSPredicate {
            NSPredicate(format: "%K == %@", discussionKey, discussion.objectID)
        }
        static func withinDiscussion(_ discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) -> NSPredicate {
            NSPredicate(format: "%K == %@", discussionKey, discussionObjectID.objectID)
        }
        static func objectsWithObjectId(in objectIDs: [NSManagedObjectID]) -> NSPredicate {
            NSPredicate(format: "self in %@", objectIDs)
        }
        static func withSortIndexLargerThan(_ sortIndex: Double) -> NSPredicate {
            NSPredicate(format: "%K > %lf", sortIndexKey, sortIndex)
        }
        static func withObjectID(_ objectID: NSManagedObjectID) -> NSPredicate {
            NSPredicate(format: "self == %@", objectID)
        }
    }

    @nonobjc static func dictionaryFetchRequest() -> NSFetchRequest<NSDictionary> {
        return NSFetchRequest<NSDictionary>(entityName: PersistedMessage.PersistedMessageEntityName)
    }

    static func getLastMessageValues(in discussion: PersistedDiscussion, propertiesToFetch: [String]) throws -> NSDictionary? {
        guard let context = discussion.managedObjectContext else { return nil }
        let request: NSFetchRequest<NSDictionary> = PersistedMessage.dictionaryFetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", discussionKey, discussion)
        request.sortDescriptors = [NSSortDescriptor(key: sortIndexKey, ascending: false)]
        request.propertiesToFetch = propertiesToFetch
        request.resultType = .dictionaryResultType
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func getLargestSortIndex(in discussion: PersistedDiscussion) throws -> Double {
        let lastMassageValues = try getLastMessageValues(in: discussion, propertiesToFetch: [sortIndexKey])
        return lastMassageValues?[sortIndexKey] as? Double ?? 0
    }

    static func getMessageValues(beforeSortIndex sortIndex: Double, in discussion: PersistedDiscussion,  propertiesToFetch: [String]) throws -> NSDictionary? {
        guard let context = discussion.managedObjectContext else { return nil }
        let request: NSFetchRequest<NSDictionary> = PersistedMessage.dictionaryFetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K < %lf",
                                        discussionKey, discussion,
                                        sortIndexKey, sortIndex)
        request.sortDescriptors = [NSSortDescriptor(key: sortIndexKey, ascending: false)]
        request.resultType = .dictionaryResultType
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func getMessageValues(afterSortIndex sortIndex: Double, in discussion: PersistedDiscussion,  propertiesToFetch: [String]) throws -> NSDictionary? {
        guard let context = discussion.managedObjectContext else { return nil }
        let request: NSFetchRequest<NSDictionary> = PersistedMessage.dictionaryFetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K > %lf",
                                        discussionKey, discussion,
                                        sortIndexKey, sortIndex)
        request.sortDescriptors = [NSSortDescriptor(key: sortIndexKey, ascending: true)]
        request.resultType = .dictionaryResultType
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

}

// MARK: - Reacting to changes

extension PersistedMessage {
    
    override func willSave() {
        super.willSave()
        /* When a message is inserted/deleted, the discussion changes. This is how Core Data works.
         * But when a message changes, the discussion is *not* marked has having changes (since the array of messages
         * did not change). Yet, most times, we do want the discussion to be marked as having changes when a message changes.
         * Here, we force this behavious by marking the discussion as having updates has soon as a message changes.
         * Note that the `hasChanges` test is imporant: a call to `discussion.setHasUpdates()` marks the managed context as `dirty`
         * triggering a new call to willSave(). Without the `discussion.hasChanges` test, we would create an infinite loop.
         */
        if isUpdated && !self.changedValues().isEmpty && !self.discussion.hasChanges {
            discussion.setHasUpdates()
        }
    }

}


// MARK: - Metadata

extension PersistedMessage {

    enum MetadataKind: CustomStringConvertible, Hashable {
        
        case read
        case wiped
        case remoteWiped(remoteCryptoId: ObvCryptoId)
        case edited
        
        var description: String {
            switch self {
            case .read: return CommonString.Word.Read
            case .wiped: return CommonString.Word.Wiped
            case .remoteWiped: return NSLocalizedString("Remotely wiped", comment: "")
            case .edited: return CommonString.Word.Edited
            }
        }
        
        var rawValue: Int {
            switch self {
            case .read: return 1
            case .wiped: return 2
            case .remoteWiped: return 3
            case .edited: return 4
            }
        }
        
        init?(rawValue: Int, remoteCryptoId: ObvCryptoId?) {
            switch rawValue {
            case 1: self = .read
            case 2: self = .wiped
            case 3:
                guard let cryptoId = remoteCryptoId else { return nil }
                self = .remoteWiped(remoteCryptoId: cryptoId)
            case 4:
                self = .edited
            default:
                assertionFailure()
                return nil
            }
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(self.rawValue)
            switch self {
            case .read, .wiped, .edited:
                break
            case .remoteWiped(remoteCryptoId: let cryptoId):
                hasher.combine(cryptoId)
            }
        }
        
    }
    
    /// For displaying all metadata to user, you should call [sortedMetadata](x-source-tag://sortedMetadata)
    var metadata: [(kind: MetadataKind, date: Date)] {
        return persistedMetadata
            .filter({ $0.kind != nil })
            .map({ ($0.kind!, $0.date) })
    }

    /// - Tag: sortedMetadata
    var sortedMetadata: [(kind: MetadataKind, date: Date)] {
        metadata.sorted(by: { $0.date < $1.date })
    }

    /// Shall *only* be called from one of the `PersistedMessage` subclasses
    func addMetadata(kind: MetadataKind, date: Date) throws {
        os_log("Call to addMetadata for message %{public}@ of kind %{public}@", log: log, type: .error, objectID.debugDescription, kind.description)
        os_log("Creating a new PersistedMessageTimestampedMetadata for message %{public}@ with kind %{public}@", log: log, type: .info, objectID.debugDescription, kind.description)
        guard let pm = PersistedMessageTimestampedMetadata(kind: kind, date: date, message: self) else { assertionFailure(); throw makeError(message: "Could not add timestamped metadata") }
        self.persistedMetadata.insert(pm)
    }

    func deleteMetadataOfKind(_ kind: MetadataKind) throws {
        guard let context = managedObjectContext else { throw makeError(message: "No context") }
        guard let metadataToDelete = self.persistedMetadata.first(where: { $0.kind == kind }) else { return }
        context.delete(metadataToDelete)
    }
    
}


@objc(PersistedMessageTimestampedMetadata)
final class PersistedMessageTimestampedMetadata: NSManagedObject {

    // MARK: Internal constants

    private static let entityName = "PersistedMessageTimestampedMetadata"
    static let dateKey = "date"
    static let messageKey = "message"
    static let rawKindKey = "rawKind"

    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { PersistedMessageTimestampedMetadata.makeError(message: message) }

    // MARK: - Attributes

    @NSManaged private var rawKind: Int
    @NSManaged private(set) var date: Date
    @NSManaged private(set) var remoteIdentity: Data?

    // MARK: - Relationships

    @NSManaged private(set) var message: PersistedMessage?
    
    // MARK: Other variables
    
    var kind: PersistedMessage.MetadataKind? {
        let remoteCryptoId = (remoteIdentity == nil ? nil : try? ObvCryptoId(identity: remoteIdentity!))
        return PersistedMessage.MetadataKind(rawValue: rawKind, remoteCryptoId: remoteCryptoId)
    }

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "PersistedMessageTimestampedMetadata")

    convenience init?(kind: PersistedMessage.MetadataKind, date: Date, message: PersistedMessage) {
        
        guard let context = message.managedObjectContext else { assertionFailure(); return nil }
        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedMessageTimestampedMetadata.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
                
        switch kind {
        case .remoteWiped(remoteCryptoId: let remoteCryptoId):
            self.remoteIdentity = remoteCryptoId.getIdentity()
        default:
            break
        }
        
        self.rawKind = kind.rawValue
        self.date = date
        self.message = message
        
    }
    
    func delete() throws {
        guard let context = self.managedObjectContext else { throw makeError(message: "Cannot delete PersistedMessageTimestampedMetadata instance, context is nil") }
        context.delete(self)
    }
    
    override func didSave() {
        super.didSave()
        if isInserted {
            guard let message = self.message else { assertionFailure(); return }
            ObvMessengerCoreDataNotification.persistedMessageHasNewMetadata(persistedMessageObjectID: message.objectID)
                .postOnDispatchQueue()
        }
    }

    struct Predicate {
        static func forMessage(_ message: PersistedMessage) -> NSPredicate {
            NSPredicate(format: "%K == %@", messageKey, message.objectID)
        }
        static func forMessage(withObjectID messageObjectID: NSManagedObjectID) -> NSPredicate {
            NSPredicate(format: "%K == %@", messageKey, messageObjectID)
        }
        static var excludeKindRead: NSPredicate {
            NSPredicate(format: "%K != %d", rawKindKey, PersistedMessage.MetadataKind.read.rawValue)
        }
        static func withKind(_ kind: PersistedMessage.MetadataKind) -> NSPredicate {
            NSPredicate(format: "%K == %d", rawKindKey, kind.rawValue)
        }
        static var withoutMessage: NSPredicate {
            NSPredicate(format: "%K == NIL", messageKey)
        }
    }

    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedMessageTimestampedMetadata> {
        return NSFetchRequest<PersistedMessageTimestampedMetadata>(entityName: PersistedMessageTimestampedMetadata.entityName)
    }

    static func getFetchRequest(messageObjectID: NSManagedObjectID, excludeKindRead: Bool) -> NSFetchRequest<PersistedMessageTimestampedMetadata> {
        let request: NSFetchRequest<PersistedMessageTimestampedMetadata> = PersistedMessageTimestampedMetadata.fetchRequest()
        if excludeKindRead {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.forMessage(withObjectID: messageObjectID),
                Predicate.excludeKindRead,
            ])
        } else {
            request.predicate = Predicate.forMessage(withObjectID: messageObjectID)
        }
        request.sortDescriptors = [NSSortDescriptor(key: dateKey, ascending: true)]
        return request
    }

    static func getOrphanedPersistedMessageTimestampedMetadata(within obvContext: ObvContext) throws -> [PersistedMessageTimestampedMetadata] {
        let request = PersistedMessageTimestampedMetadata.fetchRequest()
        request.predicate = Predicate.withoutMessage
        request.fetchLimit = 10_000
        return try obvContext.context.fetch(request)
    }
    
}
