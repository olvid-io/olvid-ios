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

@objc(PersistedMessage)
class PersistedMessage: NSManagedObject {
    
    private static let entityName = "PersistedMessage"
    
    static let bodyKey = "body"
    static let rawStatusKey = "rawStatus"
    static let rawVisibilityDurationKey = "rawVisibilityDuration"
    static let readOnceKey = "readOnce"
    static let sectionIdentifierKey = "sectionIdentifier"
    static let senderSequenceNumberKey = "senderSequenceNumber"
    static let sortIndexKey = "sortIndex"
    static let timestampKey = "timestamp"
    static let discussionKey = "discussion"
    private static let readOnceToBeDeletedKey = "readOnceToBeDeleted"
    static let muteNotificationsEndDateKey = [discussionKey, PersistedDiscussion.localConfigurationKey, PersistedDiscussionLocalConfiguration.muteNotificationsEndDateKey].joined(separator: ".")
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "PersistedMessage")

    private static func makeError(message: String) -> Error { NSError(domain: String(describing: Self.self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { PersistedMessage.makeError(message: message) }
    
    // MARK: - Attributes

    @NSManaged private var body: String?
    @NSManaged var readOnce: Bool
    @NSManaged private var rawReplyToJSON: Data?
    @NSManaged var rawStatus: Int
    @NSManaged private var rawVisibilityDuration: NSNumber?
    @NSManaged private(set) var sectionIdentifier: String
    @NSManaged private(set) var senderSequenceNumber: Int
    @NSManaged private(set) var sortIndex: Double
    @NSManaged private(set) var timestamp: Date

    // MARK: - Relationships

    @NSManaged private(set) var discussion: PersistedDiscussion
    @NSManaged private var persistedMetadata: Set<PersistedMessageTimestampedMetadata>
    @NSManaged private var rawReactions: [PersistedMessageReaction]?

    // MARK: - Other variables
    
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
        if let receivedMessage = self as? PersistedMessageReceived, receivedMessage.readingRequiresUserAction {
            return NSLocalizedString("EPHEMERAL_MESSAGE", comment: "")
        } else {
            return self.body
        }
    }
    
    var textBodyToSend: String? { self.body }
    
    var hasReplyTo: Bool {
        return rawReplyToJSON != nil
    }
    
    private(set) var replyToJSON: MessageReferenceJSON? {
        get {
            guard let rawReplyToJSON = self.rawReplyToJSON else { return nil }
            let decoder = JSONDecoder()
            return try? decoder.decode(MessageReferenceJSON.self, from: rawReplyToJSON)
        }
        set {
            guard let replyToJSON = newValue else {
                self.rawReplyToJSON = nil
                return
            }
            let encoder = JSONEncoder()
            self.rawReplyToJSON = try? encoder.encode(replyToJSON)
        }
    }

    var fyleMessageJoinWithStatus: [FyleMessageJoinWithStatus]? {
        if let receivedMessage = self as? PersistedMessageReceived {
            return receivedMessage.fyleMessageJoinWithStatuses
        } else if let sentMessage = self as? PersistedMessageSent {
            return sentMessage.fyleMessageJoinWithStatuses
        } else {
            return nil
        }
    }
    
    var messageIdentifiersFromEngine: Set<Data> {
        if let msg = self as? PersistedMessageSent {
            return Set(msg.unsortedRecipientsInfos.compactMap({ $0.messageIdentifierFromEngine }))
        } else if let msg = self as? PersistedMessageReceived {
            return Set([msg.messageIdentifierFromEngine])
        } else {
            return Set()
        }
    }
    
    func deleteBody() {
        self.body = nil
    }

    var autoRead: Bool {
        self.discussion.autoRead
    }

    var retainWipedOutboundMessages: Bool {
        self.discussion.retainWipedOutboundMessages
    }

    var earliestExpiration: PersistedMessageExpiration? {
        if let sentMessage = self as? PersistedMessageSent {
            return sentMessage.earliestExpiration
        } else if let receivedMessage = self as? PersistedMessageReceived {
            return receivedMessage.earliestExpiration
        } else {
            return nil
        }
    }

    var initialExistenceDuration: TimeInterval? {
        if let sentMessage = self as? PersistedMessageSent {
            return sentMessage.existenceDuration
        } else if let receivedMessage = self as? PersistedMessageReceived {
            return receivedMessage.initialExistenceDuration
        } else {
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
    var textBodyCanBeEdited: Bool {
        guard self is PersistedMessageSent || self is PersistedMessageReceived else { return false }
        guard self.discussion is PersistedOneToOneDiscussion || self.discussion is PersistedGroupDiscussion else { return false }
        guard !self.isLocallyWiped else { return false }
        guard !self.isRemoteWiped else { return false }
        return true
    }
    
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
    
    
    /// This method is specific to system messages, when their category is `numberOfNewMessages`.
    func resetSortIndexOfNumberOfNewMessagesSystemMessage(to newSortIndex: Double) throws {
        guard let systemMessage = self as? PersistedMessageSystem else { throw makeError(message: "Cannot reset sort index of this message type") }
        guard systemMessage.category == .numberOfNewMessages else { throw makeError(message: "Cannot change sort index of this category of system message") }
        self.sortIndex = newSortIndex
    }
    
}

// MARK: - Errors

extension PersistedMessage {
    
    struct ObvError: LocalizedError {
        
        let kind: Kind
        
        enum Kind {
            case managedContextIsNil
            case replyToMessageCannotBeFound
        }
        
        var errorDescription: String? {
            switch kind {
            case .replyToMessageCannotBeFound:
                return "Could not find a a reply-to message"
            case .managedContextIsNil:
                return "The managed context is nil, which is unexpected"
            }
        }
        
    }
    
}


// MARK: - Initializer

extension PersistedMessage {
    
    convenience init?(timestamp: Date, body: String?, rawStatus: Int, senderSequenceNumber: Int, sortIndex: Double, replyToJSON: MessageReferenceJSON?, discussion: PersistedDiscussion, readOnce: Bool, visibilityDuration: TimeInterval?, forEntityName entityName: String, within context: NSManagedObjectContext) {
        
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.body = body
        self.replyToJSON = replyToJSON
        self.rawStatus = rawStatus
        do {
            self.sectionIdentifier = try PersistedMessage.computeSectionIdentifier(fromTimestamp: timestamp, sortIndex: sortIndex, discussion: discussion)
        } catch {
            return nil
        }
        self.senderSequenceNumber = senderSequenceNumber
        self.discussion = discussion
        self.sortIndex = sortIndex
        self.timestamp = timestamp
        self.readOnce = readOnce
        self.visibilityDuration = visibilityDuration

        discussion.timestampOfLastMessage = max(self.timestamp, discussion.timestampOfLastMessage)
        
    }
    
    
    /// This `update()` method shall *only* be called from the similar `update()` from any of the concrete subclasses of `PersistedMessage`.
    func update(body: String?, senderSequenceNumber: Int, replyToJSON: MessageReferenceJSON?,
                discussion: PersistedDiscussion) throws {
        guard self.discussion.objectID == discussion.objectID else { throw makeError(message: "Invalid discussion") }
        guard self.senderSequenceNumber == senderSequenceNumber else { throw makeError(message: "Invalid sender sequence number") }
        self.body = body
        self.replyToJSON = replyToJSON
    }
 
    func delete() throws {
        guard let context = self.managedObjectContext else { assertionFailure(); throw makeError(message: "Could not find context") }
        context.delete(self)
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
        if let previousMessage = try PersistedMessage.getMessage(beforeSortIndex: sortIndex, in: discussion),
            previousMessage.sectionIdentifier > computedSectionIdentifier {
            appropriateSectionIdentifier = previousMessage.sectionIdentifier
        } else if let nextMessage = try PersistedMessage.getMessage(afterSortIndex: sortIndex, in: discussion),
            nextMessage.sectionIdentifier < computedSectionIdentifier {
            appropriateSectionIdentifier = nextMessage.sectionIdentifier
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


// MARK: - Getting ReplyToJSON

extension PersistedMessage {
    
    func toReplyToJSON() -> MessageReferenceJSON? {
        
        let senderIdentifier: Data
        let senderThreadIdentifier: UUID
        if let persistedMessageSent = self as? PersistedMessageSent {
            guard let ownedIdentity = persistedMessageSent.discussion.ownedIdentity else {
                os_log("Could not find owned identity. This is ok if it has just been deleted.", log: log, type: .error)
                return nil
            }
            senderIdentifier = ownedIdentity.cryptoId.getIdentity()
            senderThreadIdentifier = persistedMessageSent.discussion.senderThreadIdentifier
        } else if let persistedMessageReceived = self as? PersistedMessageReceived {
            senderIdentifier = persistedMessageReceived.senderIdentifier
            senderThreadIdentifier = persistedMessageReceived.senderThreadIdentifier
        } else {
            return nil
        }
        return MessageReferenceJSON(senderSequenceNumber: self.senderSequenceNumber,
                           senderThreadIdentifier: senderThreadIdentifier,
                           senderIdentifier: senderIdentifier)
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
        if let reaction = reactionFromOwnedIdentity() {
            try reaction.updateEmoji(with: emoji, at: reactionTimestamp)
        } else if let emoji = emoji {
            _ = try PersistedMessageReactionSent(emoji: emoji, timestamp: reactionTimestamp, message: self)
        } else {
            // The new emoji is nil (meaning we should remove a previous reaction) and no previous reaction can be found. There is nothing to do.
        }
    }

    
    func setReactionFromContact(_ contact: PersistedObvContactIdentity, withEmoji emoji: String?, reactionTimestamp: Date) throws {
        if let contactReaction = reactionFromContact(with: contact.cryptoId) {
            try contactReaction.updateEmoji(with: emoji, at: reactionTimestamp)
        } else if let emoji = emoji {
            _ = try PersistedMessageReactionReceived(emoji: emoji, timestamp: reactionTimestamp, message: self, contact: contact)
        } else {
            // The new emoji is nil (meaning we should remove a previous reaction) and no previous reaction can be found. There is nothing to do.
        }
    }
    
}


// MARK: - Convenience DB getters

extension PersistedMessage {
    
    private struct Predicate {
        static var readOnceToBeDeleted: NSPredicate {
            NSPredicate(format: "\(PersistedMessage.readOnceToBeDeletedKey) == TRUE")
        }
        static func withinDiscussion(_ discussion: PersistedDiscussion) -> NSPredicate {
            NSPredicate(format: "%K == %@", discussionKey, discussion.objectID)
        }
        static func withinDiscussion(_ discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) -> NSPredicate {
            NSPredicate(format: "%K == %@", discussionKey, discussionObjectID.objectID)
        }
        static var isOutboundMessage: NSPredicate {
            NSPredicate(format: "entity == %@", PersistedMessageSent.entity())
        }
        static var isInboundMessage: NSPredicate {
            NSPredicate(format: "entity == %@", PersistedMessageReceived.entity())
        }
        static var isNotInboundMessage: NSPredicate {
            NSPredicate(format: "entity != %@", PersistedMessageReceived.entity())
        }
        static var isSystemMessage: NSPredicate {
            NSPredicate(format: "entity == %@", PersistedMessageSystem.entity())
        }
        static var outboundMessageThatWasSent: NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                isOutboundMessage,
                PersistedMessageSent.Predicate.wasSent,
            ])
        }
        static var inboundMessageThatIsNotNewAnymore: NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                isInboundMessage,
                PersistedMessageReceived.Predicate.isNotNewAnymore,
            ])
        }
        static func objectsWithObjectId(in objectIDs: [NSManagedObjectID]) -> NSPredicate {
            NSPredicate(format: "self in %@", objectIDs)
        }
        static func withSortIndexSmallerThan(_ sortIndex: Double) -> NSPredicate {
            NSPredicate(format: "%K < %lf", sortIndexKey, sortIndex)
        }
        static func withSortIndexLargerThan(_ sortIndex: Double) -> NSPredicate {
            NSPredicate(format: "%K > %lf", sortIndexKey, sortIndex)
        }
        static func withSectionIdentifier(_ sectionIdentifier: String) -> NSPredicate {
            NSPredicate(format: "%K == %@", PersistedMessage.sectionIdentifierKey, sectionIdentifier)
        }
        static func withObjectID(_ objectID: NSManagedObjectID) -> NSPredicate {
            NSPredicate(format: "self == %@", objectID)
        }
    }

    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedMessage> {
        return NSFetchRequest<PersistedMessage>(entityName: PersistedMessage.entityName)
    }

    
    static func getMessageRightBeforeReceivedMessageInSameSection(_ message: PersistedMessageReceived) throws -> PersistedMessage? {
        guard let context = message.managedObjectContext else { throw NSError() }
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withSortIndexSmallerThan(message.sortIndex),
            Predicate.withSectionIdentifier(message.sectionIdentifier),
        ])
        request.sortDescriptors = [
            NSSortDescriptor(key: PersistedMessage.sectionIdentifierKey, ascending: true),
            NSSortDescriptor(key: sortIndexKey, ascending: false),
        ]
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    static func getLargestSortIndex(in discussion: PersistedDiscussion) -> Double? {
        guard let lastMessage = try? getLastMessage(in: discussion) else { return 0 }
        return lastMessage.sortIndex
    }
    
    
    static func getLastMessage(in discussion: PersistedDiscussion) throws -> PersistedMessage? {
        guard let context = discussion.managedObjectContext else { return nil }
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", discussionKey, discussion)
        request.sortDescriptors = [NSSortDescriptor(key: sortIndexKey, ascending: false)]
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    
    static func getMessage(afterSortIndex sortIndex: Double, in discussion: PersistedDiscussion) throws -> PersistedMessage? {
        guard let context = discussion.managedObjectContext else { return nil }
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K > %lf",
                                        discussionKey, discussion,
                                        sortIndexKey, sortIndex)
        request.sortDescriptors = [NSSortDescriptor(key: sortIndexKey, ascending: true)]
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    
    static func getMessage(beforeSortIndex sortIndex: Double, in discussion: PersistedDiscussion) throws -> PersistedMessage? {
        guard let context = discussion.managedObjectContext else { return nil }
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K < %lf",
                                        discussionKey, discussion,
                                        sortIndexKey, sortIndex)
        request.sortDescriptors = [NSSortDescriptor(key: sortIndexKey, ascending: false)]
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func getMessage(beforeSortIndex sortIndex: Double, inDiscussionWithObjectID objectID: TypeSafeManagedObjectID<PersistedDiscussion>, within context: NSManagedObjectContext) throws -> PersistedMessage? {
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K < %lf",
                                        discussionKey, objectID.objectID,
                                        sortIndexKey, sortIndex)
        request.sortDescriptors = [NSSortDescriptor(key: sortIndexKey, ascending: false)]
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func get(with objectID: TypeSafeManagedObjectID<PersistedMessage>, within context: NSManagedObjectContext) throws -> PersistedMessage? {
        return try get(with: objectID.objectID, within: context)
    }

    static func get(with objectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> PersistedMessage? {
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = Predicate.withObjectID(objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    static func getAll(with objectIDs: [NSManagedObjectID], within context: NSManagedObjectContext) throws -> [PersistedMessage] {
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = Predicate.objectsWithObjectId(in: objectIDs)
        request.fetchBatchSize = 1_000
        return try context.fetch(request)
    }
    
    static func deleteAllWithinDiscussion(persistedDiscussionObjectID: NSManagedObjectID, within context: NSManagedObjectContext) throws {
        // For now, the structure of the database prevents batch deletion
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", discussionKey, persistedDiscussionObjectID)
        request.fetchBatchSize = 1_000
        request.includesPropertyValues = false
        let messages = try context.fetch(request)
        _ = messages.map { context.delete($0) }
    }

    
    static func getNumberOfMessagesWithinDiscussion(discussionObjectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> Int {
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", discussionKey, discussionObjectID)
        return try context.count(for: request)
    }
    
    
    static func getAppropriateIllustrativeMessage(in discussion: PersistedDiscussion) throws -> PersistedMessage? {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Cannot find context in PersistedDiscussion") }
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: PersistedMessage.sortIndexKey, ascending: false)]
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.withinDiscussion(discussion),
                Predicate.isInboundMessage,
            ]),
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.withinDiscussion(discussion),
                Predicate.isOutboundMessage,
            ]),
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.withinDiscussion(discussion),
                Predicate.isSystemMessage,
                PersistedMessageSystem.Predicate.isRelevantForIllustrativeMessage,
            ]),
        ])
        return try context.fetch(request).first
    }

    
    /// If the current message is not an answer to another message, this method returns `nil`.
    /// Otherwise, this methods fetches the other message and returns it, if it exists either in the
    /// `PersistedMessageReceived` or in the `PersistedMessageSent` databases. If none is found, this method
    /// returns a `PersistedMessageSystem` indicating that the message has been deleted.
    func getReplyTo() throws -> PersistedMessage? {
        guard let replyToJSON = self.replyToJSON else { return nil }
        if let replyTo = try PersistedMessageReceived.get(senderSequenceNumber: replyToJSON.senderSequenceNumber,
                                                          senderThreadIdentifier: replyToJSON.senderThreadIdentifier,
                                                          contactIdentity: replyToJSON.senderIdentifier,
                                                          discussion: self.discussion) {
            guard replyTo.discussion.objectID == self.discussion.objectID else { throw makeError(message: "Could not determine discussion objectID") }
            return replyTo
        } else if let replyTo = try PersistedMessageSent.get(senderSequenceNumber: replyToJSON.senderSequenceNumber,
                                                             senderThreadIdentifier: replyToJSON.senderThreadIdentifier,
                                                             ownedIdentity: replyToJSON.senderIdentifier,
                                                             discussion: discussion) {
            assert(replyToJSON.senderIdentifier == discussion.ownedIdentity!.cryptoId.getIdentity())
            guard replyTo.discussion.objectID == self.discussion.objectID else { throw makeError(message: "Could not determine discussion objectID") }
            return replyTo
        } else {
            // The message may have been deleted, or is not yet arrived on this device
            throw ObvError.init(kind: .replyToMessageCannotBeFound)
        }
    }
    

}


// MARK: - Convenience NSFetchedResultsController creators

extension PersistedMessage {

    static func getFetchedResultsControllerForAllMessagesWithinDiscussion(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedMessage> {
        let fetchRequest: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "%K == %@", discussionKey, discussionObjectID.objectID)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: PersistedMessage.sortIndexKey, ascending: true)]
        fetchRequest.fetchBatchSize = 500
        fetchRequest.propertiesToFetch = [
            bodyKey,
            rawStatusKey,
            rawVisibilityDurationKey,
            readOnceKey,
            sectionIdentifierKey,
            senderSequenceNumberKey,
            sortIndexKey,
            timestampKey,
        ]
        fetchRequest.returnsObjectsAsFaults = false
        fetchRequest.shouldRefreshRefetchedObjects = true
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: sectionIdentifierKey,
                                                                  cacheName: nil)
        
        return fetchedResultsController
    }
    
    
    static func getFetchedResultsControllerForLastMessagesWithinDiscussion(discussionObjectID: NSManagedObjectID, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedMessage> {
        
        let numberOfMessagesToFetch = 20
        
        let numberOfMessages: Int
        do {
            numberOfMessages = try getNumberOfMessagesWithinDiscussion(discussionObjectID: discussionObjectID, within: context)
        } catch {
            numberOfMessages = 0
        }
        
        let fetchRequest: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "%K == %@", discussionKey, discussionObjectID)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: PersistedMessage.sortIndexKey, ascending: true)]
        fetchRequest.fetchLimit = min(numberOfMessagesToFetch, numberOfMessages)
        fetchRequest.fetchOffset = max(0, numberOfMessages - numberOfMessagesToFetch)
        
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: sectionIdentifierKey,
                                                                  cacheName: nil)
        
        return fetchedResultsController
    }

    
    /// This method deletes the first outbound/inbound messages of the discussion, up to the `count` parameter.
    /// Oubound messages only concerns sent messages. Outbound messages only concerns non-new messages.
    static func deleteFirstMessages(discussion: PersistedDiscussion, count: Int) throws {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Cannot find context in PersistedDiscussion") }
        guard count > 0 else { return }
        let fetchRequest: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: PersistedMessage.sortIndexKey, ascending: true)]
        fetchRequest.fetchLimit = count
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                Predicate.outboundMessageThatWasSent,
                Predicate.inboundMessageThatIsNotNewAnymore,
            ]),
        ])
        let messages = try context.fetch(fetchRequest)
        messages.forEach { context.delete($0) }
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
            ObvMessengerInternalNotification.persistedMessageHasNewMetadata(persistedMessageObjectID: message.objectID)
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
