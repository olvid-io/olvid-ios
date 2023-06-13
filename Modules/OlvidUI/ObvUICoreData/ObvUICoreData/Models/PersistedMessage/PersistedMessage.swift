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


public enum PersistedMessageKind {
    case none
    case received
    case sent
    case system
}

@objc(PersistedMessage)
public class PersistedMessage: NSManagedObject, ObvErrorMaker {

    fileprivate static let entityName = "PersistedMessage"
    public static let errorDomain = "PersistedMessageOrSubclass"
    private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "PersistedMessage")

    // MARK: Attributes

    @NSManaged private(set) var body: String?
    @NSManaged private var doesMentionOwnedIdentity: Bool // True iff this message mentions the owned identity, is a reply to a message that mentions the owned identity, or is a reply to a sent message
    @NSManaged public private(set) var forwarded: Bool
    @NSManaged public var isReplyToAnotherMessage: Bool
    @NSManaged private var onChangeFlag: Int // Transient
    @NSManaged private(set) var permanentUUID: UUID
    @NSManaged var rawStatus: Int
    @NSManaged private var rawVisibilityDuration: NSNumber?
    @NSManaged public var readOnce: Bool
    @NSManaged private(set) var sectionIdentifier: String
    @NSManaged public private(set) var senderSequenceNumber: Int
    @NSManaged public private(set) var sortIndex: Double
    @NSManaged public private(set) var timestamp: Date

    // MARK: - Relationships

    @NSManaged public private(set) var discussion: PersistedDiscussion
    @NSManaged private var illustrativeMessageForDiscussion: PersistedDiscussion?
    @NSManaged private var persistedMetadata: Set<PersistedMessageTimestampedMetadata>
    @NSManaged private(set) var rawMessageRepliedTo: PersistedMessage? // Should *only* be accessed from subentities
    @NSManaged private var rawReactions: [PersistedMessageReaction]?
    @NSManaged private var replies: Set<PersistedMessage>
    @NSManaged public private(set) var mentions: Set<PersistedUserMentionInMessage>

    // MARK: - Other variables

    public var kind: PersistedMessageKind {
        assertionFailure("Kind must be overriden in subclasses")
        return .none
    }
    
    public var messageRepliedTo: PersistedMessage? {
        self.rawMessageRepliedTo
    }
    
    public var visibilityDuration: TimeInterval? {
        get {
            guard let seconds = rawVisibilityDuration?.intValue else { return nil }
            return TimeInterval(seconds)
        }
        set {
            self.rawVisibilityDuration = (newValue == nil ? nil : NSNumber(value: newValue!) )
        }
    }
    
    public var reactions: [PersistedMessageReaction] {
        rawReactions ?? []
    }

    @objc(textBody)
    public var textBody: String? {
        if body == nil || body?.isEmpty == true { return nil }
        // Override in PersistedMessageReceived
        return self.body
    }
    
    public var textBodyToSend: String? { self.body }

    func deleteBodyAndMentions() {
        if self.body != nil {
            self.body = nil
        }
        self.deleteAllAssociatedMentions()
        self.resetDoesMentionOwnedIdentityValue()
    }

    public var initialExistenceDuration: TimeInterval? {
        if let sentMessage = self as? PersistedMessageSent {
            return sentMessage.existenceDuration
        } else {
            // Override in PersistedMessageReceived
            assert(kind == .system)
            return nil
        }
    }
    
    public var isLocallyWiped: Bool {
        self.persistedMetadata.first(where: { $0.kind == .wiped }) != nil
    }

    public var isRemoteWiped: Bool {
        deleterCryptoId != nil
    }

    public var deleterCryptoId: ObvCryptoId? {
        for meta in self.persistedMetadata {
            switch meta.kind {
            case .remoteWiped(let remoteCryptoId):
                return remoteCryptoId
            default: continue
            }
        }
        return nil
    }

    public var isWiped: Bool { isLocallyWiped || isRemoteWiped }

    /// In general, a message cannot be edited. Note that we expect `PersistedMessageSent` and `PersistedMessageReceived` to override this variable in return `true` when appropriate.
    var textBodyCanBeEdited: Bool { false }


    /// Shall only be called from methods in `PersistedMessage`, `PersistedMessageReceived`, or `PersistedMessageSent`. It shall thus not be made public.
    func replaceContentWith(newBody: String?, newMentions: Set<MessageJSON.UserMention>) throws {

        defer {
            self.resetDoesMentionOwnedIdentityValue()
        }
        
        guard self.textBodyCanBeEdited else {
            throw Self.makeError(message: "The text body of this message cannot be edited now")
        }
        
        guard let newBody else {
            if self.body != nil {
                self.body = nil
            }
            deleteAllAssociatedMentions()
            return
        }

        let (trimmedBody, mentionsInTrimmedBody) = newBody.trimmingWhitespacesAndNewlines(updating: Array(newMentions))

        if self.body != trimmedBody {
            self.body = trimmedBody
        }
        
        deleteAllAssociatedMentions()
        mentionsInTrimmedBody.forEach { mention in
            _ = try? PersistedUserMentionInMessage(mention: mention, message: self)
        }
        
    }
    

    public var repliesObjectIDs: Set<TypeSafeManagedObjectID<PersistedMessage>> {
        Set(self.replies.map({ $0.typedObjectID }))
    }
    
    public var isEdited: Bool {
        self.metadata.first(where: { $0.kind == .edited }) != nil
    }

    var isNumberOfNewMessagesMessageSystem: Bool {
        // Overriden in PersistedMessageSystem
        return false
    }
    
    /// This method is specific to system messages, when their category is `numberOfNewMessages`.
    func resetSortIndexOfNumberOfNewMessagesSystemMessage(to newSortIndex: Double) throws {
        guard isNumberOfNewMessagesMessageSystem else { throw Self.makeError(message: "Cannot reset sort index of this message type") }
        self.sortIndex = newSortIndex
        assert(fyleMessageJoinWithStatus == nil) // Otherwise we would need to update the sort index replicated within the joins
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

    public var fyleMessageJoinWithStatus: [FyleMessageJoinWithStatus]? { nil }

    var messageIdentifiersFromEngine: Set<Data> { Set() }

    public var genericRepliesTo: RepliedMessage { .none }

    
    /// Returns `true` iff all the joins of this message are wiped and the body is nil or empty.
    /// This is typically used after wiping an attachment (aka `FyleMessageJoinWithStatus`). In the case, we want to check whether the message still makes sense or if it should be deleted.
    public var shouldBeDeleted: Bool {
        let nonWipedJoins = self.fyleMessageJoinWithStatus?.filter({ !$0.isWiped }) ?? []
        guard body == nil || body?.isEmpty == true else { return false }
        guard nonWipedJoins.isEmpty else { return false }
        // If we reach this point, the message should be deleted
        return true
    }

    
    public var messagePermanentID: ObvManagedObjectPermanentID<PersistedMessage> {
        ObvManagedObjectPermanentID(entityName: PersistedMessage.entityName, uuid: self.permanentUUID)
    }

    var isIllustrativeMessage: Bool {
        illustrativeMessageForDiscussion != nil
    }
    
    public var retainWipedOutboundMessages: Bool {
        self.discussion.retainWipedOutboundMessages
    }

    /// Helper property that returns `discussion.autoRead`
    public var autoRead: Bool {
        self.discussion.autoRead
    }

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
    
    convenience init(timestamp: Date, body: String?, rawStatus: Int, senderSequenceNumber: Int, sortIndex: Double, isReplyToAnotherMessage: Bool, replyTo: PersistedMessage?, discussion: PersistedDiscussion, readOnce: Bool, visibilityDuration: TimeInterval?, forwarded: Bool, mentions: [MessageJSON.UserMention], forEntityName entityName: String) throws {
        
        guard let context = discussion.managedObjectContext else { assertionFailure(); throw PersistedMessage.makeError(message: "Could not find context") }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.body = body
        self.isReplyToAnotherMessage = isReplyToAnotherMessage
        self.permanentUUID = UUID()
        self.rawMessageRepliedTo = replyTo
        self.rawStatus = rawStatus
        self.sectionIdentifier = try PersistedMessage.computeSectionIdentifier(fromTimestamp: timestamp, sortIndex: sortIndex, discussion: discussion)
        self.senderSequenceNumber = senderSequenceNumber
        self.discussion = discussion
        self.sortIndex = sortIndex
        self.timestamp = timestamp
        self.readOnce = readOnce
        self.visibilityDuration = visibilityDuration
        self.forwarded = forwarded
        self.doesMentionOwnedIdentity = false // Set later

        mentions.forEach { mention in
            _ = try? PersistedUserMentionInMessage(mention: mention, message: self)
        }

        discussion.resetTimestampOfLastMessageIfCurrentValueIsEarlierThan(self.timestamp)
        discussion.unarchive()
        
        // Update the value of the doesMentionOwnedIdentity attribute
        
        resetDoesMentionOwnedIdentityValue()

    }

    
    /// This `update()` method shall *only* be called from the similar `update()` from the subclass `PersistedMessageReceived`.
    func update(body: String?, newMentions: Set<MessageJSON.UserMention>, senderSequenceNumber: Int, replyTo: PersistedMessage?, discussion: PersistedDiscussion) throws {
        guard self.discussion.objectID == discussion.objectID else { assertionFailure(); throw Self.makeError(message: "Invalid discussion") }
        guard self.senderSequenceNumber == senderSequenceNumber else { assertionFailure(); throw Self.makeError(message: "Invalid sender sequence number") }
        try self.replaceContentWith(newBody: body, newMentions: newMentions)
        self.rawMessageRepliedTo = replyTo
        self.resetDoesMentionOwnedIdentityValue()
    }
    
    
    /// Should *only* be called from `PersistedMessageReceived`
    func setRawMessageRepliedTo(with rawMessageRepliedTo: PersistedMessage) {
        assert(kind == .received)
        self.rawMessageRepliedTo = rawMessageRepliedTo
    }
    
    func setHasUpdate() {
        onChangeFlag += 1
    }
    
    /// Helper method that deletes and removes all associated mentions (``PersistedUserMentionInMessage``)  from ``mentions``
    private func deleteAllAssociatedMentions() {
        let oldMentions = mentions
        oldMentions
            .forEach { try? $0.deleteUserMention() }
        if !mentions.isEmpty {
            mentions = []
        }
    }

}


// MARK: - Deleting a message

extension PersistedMessage {
    
    /// This is the function to call to delete this message.
    /// This method makes sure the `requester` is allowed to delete this message. If the `requester` is `nil`, deletion is performed.
    public func delete(requester: RequesterOfMessageDeletion?) throws -> InfoAboutWipedOrDeletedPersistedMessage {
        if let requester = requester {
            try throwIfRequesterIsNotAllowedToDeleteMessage(requester: requester)
        }
        guard let context = self.managedObjectContext else { assertionFailure(); throw Self.makeError(message: "Could not find context") }
        let deletedInfo = InfoAboutWipedOrDeletedPersistedMessage(kind: .deleted,
                                                                  discussionPermanentID: self.discussion.discussionPermanentID,
                                                                  messagePermanentID: self.messagePermanentID)
        context.delete(self)
        return deletedInfo
    }


    /// This methods throws an error if the requester of this message deletion is not allowed to perform such a deletion.
    func throwIfRequesterIsNotAllowedToDeleteMessage(requester: RequesterOfMessageDeletion) throws {
        
        // We fist consider the message kind
        
        switch self.kind {

        case .none:

            assertionFailure()
            return // Allow deletion

        case .system:

            guard let systemMessage = self as? PersistedMessageSystem else {
                // Unexpected, this is a bug
                assertionFailure()
                return // Allow deletion
            }

            // A system message can only (and almost always) be locally deleted by an owned identity
            
            switch requester {
            case .contact:
                throw Self.makeError(message: "A system message cannot be deleted by a contact")
            case .ownedIdentity(let ownedCryptoId, let deletionType):
                guard let discussionOwnedCryptoId = discussion.ownedIdentity?.cryptoId else {
                    return // Rare case, we allow deletion
                }
                guard (discussionOwnedCryptoId == ownedCryptoId) else {
                    assertionFailure()
                    throw Self.makeError(message: "Unexpected owned identity for deleting this message")
                }
                switch deletionType {
                case .local:
                    switch systemMessage.category {
                    case .contactJoinedGroup,
                            .contactLeftGroup,
                            .contactWasDeleted,
                            .callLogItem,
                            .updatedDiscussionSharedSettings,
                            .contactRevokedByIdentityProvider,
                            .discussionWasRemotelyWiped,
                            .notPartOfTheGroupAnymore,
                            .rejoinedGroup,
                            .contactIsOneToOneAgain,
                            .membersOfGroupV2WereUpdated,
                            .ownedIdentityIsPartOfGroupV2Admins,
                            .ownedIdentityIsNoLongerPartOfGroupV2Admins,
                            .ownedIdentityDidCaptureSensitiveMessages,
                            .contactIdentityDidCaptureSensitiveMessages:
                        return // Allow deletion
                    case .numberOfNewMessages,
                            .discussionIsEndToEndEncrypted:
                        throw Self.makeError(message: "Specific system message that cannot be deleted")
                    }
                case .global:
                    throw Self.makeError(message: "We cannot globally delete a system message")
                }
            }

        case .received, .sent:
            
            // We are considering a received or sent message. We need more information be fore deciding whether we should throw or not.
            break
            
        }
        
        assert(self.kind == .received || self.kind == .sent)
        
        // If we reach this point, we are considering a received or a sent message
        
        // Received or sent messages from locked and preDiscussion can only (and always) be locally deleted by an owned identity
        
        switch discussion.status {
        case .locked, .preDiscussion:
            switch requester {
            case .contact:
                throw Self.makeError(message: "A contact cannot delete a message from a locked or preDiscussion")
            case .ownedIdentity(let ownedCryptoId, let deletionType):
                guard let discussionOwnedCryptoId = discussion.ownedIdentity?.cryptoId else {
                    return // Rare case, we allow deletion
                }
                guard (discussionOwnedCryptoId == ownedCryptoId) else {
                    assertionFailure()
                    throw Self.makeError(message: "Unexpected owned identity for deleting this message")
                }
                switch deletionType {
                case .local:
                    return // Allow deletion
                case .global:
                    throw Self.makeError(message: "We cannot globally delete a message from a locked or preDiscussion")
                }
            }
        case .active:
            break // We need to consider more aspects about the message in order to decide whether we should throw or not
        }

        // If we reach this point, we are considering a received or a sent message in an active discussion

        // Messages that are wiped cannot be globally deleted by the owned identity and cannot be deleted by a contact
        
        guard !isRemoteWiped else {
            switch requester {
            case .contact:
                throw Self.makeError(message: "A contact cannot delete a wiped message")
            case .ownedIdentity(let ownedCryptoId, let deletionType):
                guard let discussionOwnedCryptoId = discussion.ownedIdentity?.cryptoId else {
                    return // Rare case, we allow deletion
                }
                guard (discussionOwnedCryptoId == ownedCryptoId) else {
                    assertionFailure()
                    throw Self.makeError(message: "Unexpected owned identity for deleting this message")
                }
                switch deletionType {
                case .local:
                    return // Allow deletion
                case .global:
                    throw Self.makeError(message: "We cannot globally delete a wiped message")
                }
            }
        }

        // If we reach this point, we are considering a (non-wiped) received or a sent message in an active discussion

        switch try discussion.kind {
            
        case .oneToOne, .groupV1:
            
            // It is always ok to (locally or globally) delete a non-wiped received or sent message in a oneToOne or a groupV1 discussion
            return // Allow deletion

        case .groupV2(withGroup: let group):
            
            // For a group v2 discussion, we make sure the requester has the appropriate rights
            
            guard let group = group else {
                
                // If the group cannot be found (which is unexpected), we only allow local deletion of the message from an owned identity
                
                switch requester {
                case .contact:
                    assertionFailure()
                    throw Self.makeError(message: "Since we cannot find the group, we disallow deletion by a contact")
                case .ownedIdentity(ownedCryptoId: _, deletionType: let deletionType):
                    switch deletionType {
                    case .local:
                        return // Allow deletion
                    case .global:
                        throw Self.makeError(message: "Since we cannot find the group, we disallow global deletion by owned identity")
                    }
                }
                
            }
            
            // We make sure the requester has the appropriate rights
            
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
                    if group.ownedIdentityIsAllowedToRemoteDeleteAnything {
                        return // Allow deletion
                    } else if group.ownedIdentityIsAllowedToEditOrRemoteDeleteOwnMessages && self is PersistedMessageSent {
                        return // Allow deletion
                    } else {
                        throw Self.makeError(message: "Owned identity is not allowed to perform a global (remote) delete in this case")
                    }
                }
                
            case .contact(let ownedCryptoId, let contactCryptoId, _):
                
                guard (try group.ownCryptoId == ownedCryptoId) else {
                    assertionFailure()
                    throw Self.makeError(message: "Unexpected owned identity associated to contact for deleting this discussion")
                }
                guard let member = group.otherMembers.first(where: { $0.identity == contactCryptoId.getIdentity() }) else {
                    throw Self.makeError(message: "The deletion requester is not part of the group")
                }
                if member.isAllowedToRemoteDeleteAnything {
                    return // Allow deletion
                } else if member.isAllowedToEditOrRemoteDeleteOwnMessages && (self as? PersistedMessageReceived)?.contactIdentity?.cryptoId == contactCryptoId {
                    return // Allow deletion
                } else {
                    assertionFailure()
                    throw Self.makeError(message: "The member is not allowed to delete this message")
                }
            }
            
        }
        
    }

}


// MARK: - Reply-to

public extension PersistedMessage {

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


    public func reactionFromOwnedIdentity() -> PersistedMessageReactionSent? {
        let ownedReactions = reactions.compactMap { $0 as? PersistedMessageReactionSent }
        assert(ownedReactions.count <= 1)
        return ownedReactions.first
    }
    
    
    public func setReactionFromOwnedIdentity(withEmoji emoji: String?, reactionTimestamp: Date) throws {
        // Never set an emoji on a wiped message
        guard !self.isWiped else { return }
        // Make sure we are allowed to set a reaction
        guard try ownedIdentityIsAllowedToSetReaction else {
            throw Self.makeError(message: "Trying to set an own reaction in a group v2 discussion where we are not allowed to write")
        }
        // Set the reaction
        if let reaction = reactionFromOwnedIdentity() {
            try reaction.updateEmoji(with: emoji, at: reactionTimestamp)
        } else if let emoji = emoji {
            _ = try PersistedMessageReactionSent(emoji: emoji, timestamp: reactionTimestamp, message: self)
        } else {
            // The new emoji is nil (meaning we should remove a previous reaction) and no previous reaction can be found. There is nothing to do.
        }
    }
    
    
    public var ownedIdentityIsAllowedToSetReaction: Bool {
        get throws {
            switch try discussion.kind {
            case .oneToOne, .groupV1:
                return true
            case .groupV2(withGroup: let group):
                guard let group = group else {
                    assertionFailure()
                    throw Self.makeError(message: "Could not determine group v2 while setting own reaction to a message")
                }
                return group.ownedIdentityIsAllowedToSendMessage
            }
        }
    }

    
    public func setReactionFromContact(_ contact: PersistedObvContactIdentity, withEmoji emoji: String?, reactionTimestamp: Date) throws {
        // Never set an emoji on a wiped message
        guard !self.isWiped else { return }
        // Make sure the contact is allowed to set a reaction
        switch try discussion.kind {
        case .oneToOne(withContactIdentity: let discussionContact):
            guard discussionContact == contact else {
                assertionFailure()
                throw Self.makeError(message: "Unexpected contact reaction")
            }
        case .groupV1(withContactGroup: let group):
            guard let group = group else {
                assertionFailure()
                throw Self.makeError(message: "Could not determine group while setting reaction from contact")
            }
            guard group.contactIdentities.contains(contact) else {
                assertionFailure()
                throw Self.makeError(message: "Unexpected contact reaction is group")
            }
        case .groupV2(withGroup: let group):
            guard let group = group else {
                assertionFailure()
                throw Self.makeError(message: "Could not determine group v2 while setting reaction from contact")
            }
            guard let member = group.otherMembers.first(where: { $0.identity == contact.identity }) else {
                assertionFailure()
                throw Self.makeError(message: "Unexpected contact reaction is group v2")
            }
            guard member.isAllowedToSendMessage else {
                assertionFailure()
                throw Self.makeError(message: "Received a reaction from a contact that is now allowed to send messages")
            }
        }
        
        if let contactReaction = reactionFromContact(with: contact.cryptoId) {
            try contactReaction.updateEmoji(with: emoji, at: reactionTimestamp)
        } else {
            _ = try PersistedMessageReactionReceived(emoji: emoji, timestamp: reactionTimestamp, message: self, contact: contact)
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
        if let previousMessageValues = try PersistedMessage.getMessageValues(beforeSortIndex: sortIndex, in: discussion, propertiesToFetch: [Predicate.Key.sectionIdentifier.rawValue]),
           let sectionIdentifier = previousMessageValues[Predicate.Key.sectionIdentifier.rawValue] as? String,
           sectionIdentifier > computedSectionIdentifier {
            appropriateSectionIdentifier = sectionIdentifier
        } else if let nextMessageValues = try PersistedMessage.getMessageValues(afterSortIndex: sortIndex, in: discussion, propertiesToFetch: [Predicate.Key.sectionIdentifier.rawValue]),
                  let sectionIdentifier = nextMessageValues[Predicate.Key.sectionIdentifier.rawValue] as? String,
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


    public static func getDateComponents(fromSectionIdentifier sectionIdentifier: String) -> DateComponents? {
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


// MARK: - Managing the doesMentionOwnedIdentity Boolean

extension PersistedMessage {
    
    private func resetDoesMentionOwnedIdentityValue() {
        guard let ownedCryptoId = discussion.ownedIdentity?.cryptoId else {
            assertionFailure("Could not determine the owned crypto id which is unexpected at this point")
            if self.doesMentionOwnedIdentity {
                self.doesMentionOwnedIdentity = false
                self.discussion.resetNewReceivedMessageDoesMentionOwnedIdentityValue()
            }
            return
        }
        
        let mentionsContainOwnedIdentity = self.mentions.compactMap({ try? $0.mentionnedCryptoId }).contains(ownedCryptoId)
        let doesReplyToMessageThatMentionsOwnedIdentity = self.rawMessageRepliedTo?.mentions.compactMap({ try? $0.mentionnedCryptoId }).contains(ownedCryptoId) ?? false
        let doesReplyToSentMessage = self.rawMessageRepliedTo is PersistedMessageSent
                
        let newDoesMentionOwnedIdentity = Self.computeDoesMentionOwnedIdentityValue(
            messageMentionsContainOwnedIdentity: mentionsContainOwnedIdentity,
            messageDoesReplyToMessageThatMentionsOwnedIdentity: doesReplyToMessageThatMentionsOwnedIdentity,
            messageDoesReplyToSentMessage: doesReplyToSentMessage)
        
        if self.doesMentionOwnedIdentity != newDoesMentionOwnedIdentity {
            self.doesMentionOwnedIdentity = newDoesMentionOwnedIdentity
            self.discussion.resetNewReceivedMessageDoesMentionOwnedIdentityValue()
        }
    }
    
    public static func computeDoesMentionOwnedIdentityValue(messageMentionsContainOwnedIdentity: Bool, messageDoesReplyToMessageThatMentionsOwnedIdentity: Bool, messageDoesReplyToSentMessage: Bool) -> Bool {
        messageMentionsContainOwnedIdentity || messageDoesReplyToMessageThatMentionsOwnedIdentity || messageDoesReplyToSentMessage
    }
    
}


// MARK: - Convenience DB getters

extension PersistedMessage {

    struct Predicate {
        enum Key: String {
            // Attributes
            case body = "body"
            case doesMentionOwnedIdentity = "doesMentionOwnedIdentity"
            case forwarded = "forwarded"
            case isReplyToAnotherMessage = "isReplyToAnotherMessage"
            case permanentUUID = "permanentUUID"
            case rawStatus = "rawStatus"
            case rawVisibilityDuration = "rawVisibilityDuration"
            case readOnce = "readOnce"
            case sectionIdentifier = "sectionIdentifier"
            case senderSequenceNumber = "senderSequenceNumber"
            case sortIndex = "sortIndex"
            case timestamp = "timestamp"
            // Relationships
            case discussion = "discussion"
            case persistedMetadata = "persistedMetadata"
            case rawMessageRepliedTo = "rawMessageRepliedTo"
            case rawReactions = "rawReactions"
            // Others
            static let discussionPermanentUUID = [discussion.rawValue, PersistedDiscussion.Predicate.Key.permanentUUID.rawValue].joined(separator: ".")
            static let muteNotificationsEndDate = [discussion.rawValue, PersistedDiscussion.Predicate.Key.localConfiguration.rawValue, PersistedDiscussionLocalConfiguration.Predicate.Key.muteNotificationsEndDate.rawValue].joined(separator: ".")
            static let ownedIdentity = [discussion.rawValue, PersistedDiscussion.Predicate.Key.ownedIdentity.rawValue].joined(separator: ".")
            static let ownedIdentityIdentity = [discussion.rawValue, PersistedDiscussion.Predicate.Key.ownedIdentityIdentity].joined(separator: ".")
            static let senderThreadIdentifier = [discussion.rawValue, PersistedDiscussion.Predicate.Key.senderThreadIdentifier.rawValue].joined(separator: ".")
            static let ownedIdentityHiddenProfileHash = [ownedIdentity, PersistedObvOwnedIdentity.Predicate.Key.hiddenProfileHash.rawValue].joined(separator: ".")
            static let ownedIdentityHiddenProfileSalt = [ownedIdentity, PersistedObvOwnedIdentity.Predicate.Key.hiddenProfileSalt.rawValue].joined(separator: ".")
        }
        static var ownedIdentityIsNotHidden: NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(withNonNilValueForKey: Key.discussion),
                NSPredicate(withNonNilValueForRawKey: Key.ownedIdentity),
                NSPredicate(withNilValueForRawKey: Key.ownedIdentityHiddenProfileHash),
                NSPredicate(withNilValueForRawKey: Key.ownedIdentityHiddenProfileSalt),
            ])
        }
        static var doesMentionOwnedIdentity: NSPredicate {
            NSPredicate(Key.doesMentionOwnedIdentity, is: true)
        }
        static func withSenderThreadIdentifier(_ senderThreadIdentifier: UUID) -> NSPredicate {
            NSPredicate(Key.senderThreadIdentifier, EqualToUuid: senderThreadIdentifier)
        }
        static func withOwnedIdentity(_ ownedIdentity: PersistedObvOwnedIdentity) -> NSPredicate {
            NSPredicate(Key.ownedIdentity, equalTo: ownedIdentity)
        }
        static func withOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.ownedIdentityIdentity, EqualToData: ownedCryptoId.getIdentity())
        }
        static func withOwnedIdentityIdentity(_ ownedIdentity: Data) -> NSPredicate {
            NSPredicate(Key.ownedIdentityIdentity, EqualToData: ownedIdentity)
        }
        static func withinDiscussion(_ discussion: PersistedDiscussion) -> NSPredicate {
            NSPredicate(Key.discussion, equalTo: discussion)
        }
        static func withinDiscussion(_ discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) -> NSPredicate {
            NSPredicate(Key.discussion, equalToObjectWithObjectID: discussionObjectID.objectID)
        }
        static func withinDiscussionWithObjectID(_ discussionObjectID: NSManagedObjectID) -> NSPredicate {
            NSPredicate(Key.discussion, equalToObjectWithObjectID: discussionObjectID)
        }
        static func withinDiscussionWithPermanentID(_ discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>) -> NSPredicate {
            NSPredicate(Key.discussionPermanentUUID, EqualToUuid: discussionPermanentID.uuid)
        }
        static func objectsWithObjectId(in objectIDs: [NSManagedObjectID]) -> NSPredicate {
            NSPredicate(format: "self in %@", objectIDs)
        }
        static func withSortIndexLargerThan(_ sortIndex: Double) -> NSPredicate {
            NSPredicate(Predicate.Key.sortIndex, LargerThanDouble: sortIndex)
        }
        static func withObjectID(_ objectID: NSManagedObjectID) -> NSPredicate {
            NSPredicate(withObjectID: objectID)
        }
        static func createdBefore(date: Date) -> NSPredicate {
            NSPredicate(Key.timestamp, earlierThan: date)
        }
        static func createdBeforeIncluded(date: Date) -> NSPredicate {
            NSPredicate(format: "%K <= %@", Key.timestamp.rawValue, date as NSDate)
        }
        static func withSenderSequenceNumberEqualTo(_ senderSequenceNumber: Int) -> NSPredicate {
            NSPredicate(Key.senderSequenceNumber, EqualToInt: senderSequenceNumber)
        }
        static func withSenderSequenceNumberLargerThan(_ senderSequenceNumber: Int) -> NSPredicate {
            NSPredicate(Key.senderSequenceNumber, LargerThanInt: senderSequenceNumber)
        }
        static func withSenderSequenceNumberLessThan(_ senderSequenceNumber: Int) -> NSPredicate {
            NSPredicate(Key.senderSequenceNumber, LessThanInt: senderSequenceNumber)
        }
        static var isDiscussionUnmuted: NSPredicate {
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(withNilValueForRawKey: Key.muteNotificationsEndDate),
                NSPredicate(Key.muteNotificationsEndDate, earlierThan: Date()),
            ])
        }
        static var readOnce: NSPredicate {
            NSPredicate(Key.readOnce, is: true)
        }
        static func withSortIndexSmallerThan(_ sortIndex: Double) -> NSPredicate {
            NSPredicate(Key.sortIndex, lessThanDouble: sortIndex)
        }
        static func withPermanentID(_ permanentID: ObvManagedObjectPermanentID<PersistedMessage>) -> NSPredicate {
            NSPredicate(Key.permanentUUID, EqualToUuid: permanentID.uuid)
        }
        static func isInboundMessage(within context: NSManagedObjectContext) -> NSPredicate {
            if context.concurrencyType == .mainQueueConcurrencyType {
                let entity = NSEntityDescription.entity(forEntityName: PersistedMessageReceived.entityName, in: context)!
                return NSPredicate(withEntity: entity)
            } else {
                return NSPredicate(withEntity: PersistedMessageReceived.entity())
          }
        }
        static func isNotInboundMessage(within context: NSManagedObjectContext) -> NSPredicate {
            if context.concurrencyType == .mainQueueConcurrencyType {
                let entity = NSEntityDescription.entity(forEntityName: PersistedMessageReceived.entityName, in: context)!
                return NSPredicate(withEntityDistinctFrom: entity)
            } else {
                return NSPredicate(withEntityDistinctFrom: PersistedMessageReceived.entity())
            }
        }
        static func isOutboundMessage(within context: NSManagedObjectContext) -> NSPredicate {
            if context.concurrencyType == .mainQueueConcurrencyType {
                let entity = NSEntityDescription.entity(forEntityName: PersistedMessageSent.entityName, in: context)!
                return NSPredicate(withEntity: entity)
            } else {
                return NSPredicate(withEntity: PersistedMessageSent.entity())
            }
        }
        static func isSystemMessage(within context: NSManagedObjectContext) -> NSPredicate {
            if context.concurrencyType == .mainQueueConcurrencyType {
                let entity = NSEntityDescription.entity(forEntityName: PersistedMessageSystem.entityName, in: context)!
                return NSPredicate(withEntity: entity)
            } else {
                return NSPredicate(withEntity: PersistedMessageSystem.entity())
            }
        }
    }

    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedMessage> {
        return NSFetchRequest<PersistedMessage>(entityName: PersistedMessage.entityName)
    }

    
    @nonobjc static func dictionaryFetchRequest() -> NSFetchRequest<NSDictionary> {
        return NSFetchRequest<NSDictionary>(entityName: PersistedMessage.entityName)
    }


    public static func get(with objectID: TypeSafeManagedObjectID<PersistedMessage>, within context: NSManagedObjectContext) throws -> PersistedMessage? {
        return try get(with: objectID.objectID, within: context)
    }

    
    public static func getManagedObject(withPermanentID permanentID: ObvManagedObjectPermanentID<PersistedMessage>, within context: NSManagedObjectContext) throws -> PersistedMessage? {
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = Predicate.withPermanentID(permanentID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    public static func get(with objectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> PersistedMessage? {
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = Predicate.withObjectID(objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    

    static func getLargestSortIndex(in discussion: PersistedDiscussion) throws -> Double {
        guard let context = discussion.managedObjectContext else { throw Self.makeError(message: "Could not find context") }
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = Predicate.withinDiscussion(discussion)
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.sortIndex.rawValue, ascending: false)]
        request.propertiesToFetch = [Predicate.Key.sortIndex.rawValue]
        request.fetchLimit = 1
        return try context.fetch(request).first?.sortIndex ?? 0
    }

    
    static func getMessageValues(beforeSortIndex sortIndex: Double, in discussion: PersistedDiscussion, propertiesToFetch: [String]) throws -> NSDictionary? {
        guard let context = discussion.managedObjectContext else { return nil }
        let request: NSFetchRequest<NSDictionary> = PersistedMessage.dictionaryFetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            Predicate.withSortIndexSmallerThan(sortIndex),
        ])
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.sortIndex.rawValue, ascending: false)]
        request.resultType = .dictionaryResultType
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    static func getMessageValues(afterSortIndex sortIndex: Double, in discussion: PersistedDiscussion, propertiesToFetch: [String]) throws -> NSDictionary? {
        guard let context = discussion.managedObjectContext else { return nil }
        let request: NSFetchRequest<NSDictionary> = PersistedMessage.dictionaryFetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            Predicate.withSortIndexLargerThan(sortIndex),
        ])
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.sortIndex.rawValue, ascending: true)]
        request.resultType = .dictionaryResultType
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    public static func findMessageFrom(reference referenceJSON: MessageReferenceJSON, within discussion: PersistedDiscussion) throws -> PersistedMessage? {
        if let message = try PersistedMessageReceived.get(senderSequenceNumber: referenceJSON.senderSequenceNumber,
                                                          senderThreadIdentifier: referenceJSON.senderThreadIdentifier,
                                                          contactIdentity: referenceJSON.senderIdentifier,
                                                          discussion: discussion) {
            return message
        } else if let message = try PersistedMessageSent.get(senderSequenceNumber: referenceJSON.senderSequenceNumber,
                                                             senderThreadIdentifier: referenceJSON.senderThreadIdentifier,
                                                             ownedIdentity: referenceJSON.senderIdentifier,
                                                             discussion: discussion) {
            assert(referenceJSON.senderIdentifier == discussion.ownedIdentity?.cryptoId.getIdentity())
            return message
        } else {
            return nil
        }
    }

    
    static func getMessage(afterSortIndex sortIndex: Double, in discussion: PersistedDiscussion) throws -> PersistedMessage? {
        guard let context = discussion.managedObjectContext else { return nil }
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            Predicate.withSortIndexLargerThan(sortIndex),
        ])
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.sortIndex.rawValue, ascending: true)]
        request.fetchLimit = 1
        return try context.fetch(request).first
    }


    public static func getMessage(beforeSortIndex sortIndex: Double, in discussion: PersistedDiscussion) throws -> PersistedMessage? {
        guard let context = discussion.managedObjectContext else { return nil }
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            Predicate.withSortIndexSmallerThan(sortIndex),
        ])
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.sortIndex.rawValue, ascending: false)]
        request.fetchLimit = 1
        return try context.fetch(request).first
    }


    /// Returns the most appropriate illustrative message for the given discussion.
    ///
    /// If the criteria for being an illustrative message changes here, we should also update the `resetIllustrativeMessageWithMessageIfAppropriate` method of `PersistedDiscussion`.
    public static func getAppropriateIllustrativeMessage(in discussion: PersistedDiscussion) throws -> PersistedMessage? {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Cannot find context in PersistedDiscussion") }
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.sortIndex.rawValue, ascending: false)]
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                Predicate.isInboundMessage(within: context),
                Predicate.isOutboundMessage(within: context),
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    Predicate.isSystemMessage(within: context),
                    PersistedMessageSystem.Predicate.isRelevantForIllustrativeMessage,
                ]),
            ])
        ])
        return try context.fetch(request).first
    }

}


// MARK: - Reacting to changes

extension PersistedMessage {
    
    public override func willSave() {
        super.willSave()
        
        /* When a message is inserted/deleted, the discussion changes. This is how Core Data works.
         * But when a message changes, the discussion is *not* marked has having changes (since the array of messages
         * did not change). Yet, most times, we do want the discussion to be marked as having changes when a message changes.
         * Here, we force this behaviour by marking the discussion as having updates has soon as a message changes.
         * Note that the `hasChanges` test is imporant: a call to `discussion.setHasUpdates()` marks the managed context as `dirty`
         * triggering a new call to willSave(). Without the `discussion.hasChanges` test, we would create an infinite loop.
         */
        if isUpdated && !self.changedValues().isEmpty && !self.discussion.hasChanges {
            discussion.setHasUpdates()
        }
        
        // When inserting or updating a message, we use it as a candidate for the illustrative message of the discussion.
        if (isInserted || isUpdated) && !self.changedValues().isEmpty {
            discussion.resetIllustrativeMessageWithMessageIfAppropriate(newMessage: self)
        }

        // When inserting a new message, and when the status of a message changes, the discussion must recompute the number of new messages
        if isInserted || (isUpdated && self.changedValues().keys.contains(Predicate.Key.rawStatus.rawValue)) {
            do {
                try discussion.refreshNumberOfNewMessages()
            } catch {
                assertionFailure()
                // In production, continue anyway
            }
        }
        
    }
    
    public override func prepareForDeletion() {
        super.prepareForDeletion()
        
        assert(isDeleted)

        guard let managedObjectContext else { assertionFailure(); return }
        guard managedObjectContext.concurrencyType != .mainQueueConcurrencyType else { return }
        
        // The following two lines are important as they allow to make sure the managedObjectContext keeps a strong pointer to the discussion.
        // Without these two lines, the app crashes while trying to access the discussion.
        guard let discussion = self.value(forKey: Predicate.Key.discussion.rawValue) as? PersistedDiscussion else { return }
        discussion.setHasUpdates()
        
        // When deleting an illustrative message, we must reset the illustrative message of the discussion.
        if self.isIllustrativeMessage {
            do {
                try discussion.resetIllustrativeMessage()
            } catch {
                assertionFailure()
                // In production, continue anyway
            }
        }

        // When deleting a message, the discussion must recompute the number of new messages
        do {
            try discussion.refreshNumberOfNewMessages()
        } catch {
            assertionFailure()
            // In production, continue anyway
        }

    }
        
}


// MARK: - Metadata

extension PersistedMessage {

    public enum MetadataKind: CustomStringConvertible, Hashable {
        
        case read
        case wiped
        case remoteWiped(remoteCryptoId: ObvCryptoId)
        case edited
        
        public var description: String {
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

        public func hash(into hasher: inout Hasher) {
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
    public var sortedMetadata: [(kind: MetadataKind, date: Date)] {
        metadata.sorted(by: { $0.date < $1.date })
    }

    /// Shall *only* be called from one of the `PersistedMessage` subclasses
    func addMetadata(kind: MetadataKind, date: Date) throws {
        os_log("Call to addMetadata for message %{public}@ of kind %{public}@", log: log, type: .error, objectID.debugDescription, kind.description)
        os_log("Creating a new PersistedMessageTimestampedMetadata for message %{public}@ with kind %{public}@", log: log, type: .info, objectID.debugDescription, kind.description)
        guard let pm = PersistedMessageTimestampedMetadata(kind: kind, date: date, message: self) else { assertionFailure(); throw Self.makeError(message: "Could not add timestamped metadata") }
        self.persistedMetadata.insert(pm)
    }

    func deleteMetadataOfKind(_ kind: MetadataKind) throws {
        guard let context = managedObjectContext else { throw Self.makeError(message: "No context") }
        guard let metadataToDelete = self.persistedMetadata.first(where: { $0.kind == kind }) else { return }
        context.delete(metadataToDelete)
    }
    
}


// MARK: - PersistedMessageTimestampedMetadata

@objc(PersistedMessageTimestampedMetadata)
public final class PersistedMessageTimestampedMetadata: NSManagedObject, ObvErrorMaker {

    // MARK: Internal constants

    private static let entityName = "PersistedMessageTimestampedMetadata"
    public static let errorDomain = "PersistedMessageTimestampedMetadata"
    private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "PersistedMessageTimestampedMetadata")

    // MARK: Attributes

    @NSManaged private var rawKind: Int
    @NSManaged public private(set) var date: Date
    @NSManaged private(set) var remoteIdentity: Data?

    // MARK: Relationships

    @NSManaged private(set) var message: PersistedMessage?
    
    // MARK: Other variables
    
    public var kind: PersistedMessage.MetadataKind? {
        let remoteCryptoId = (remoteIdentity == nil ? nil : try? ObvCryptoId(identity: remoteIdentity!))
        return PersistedMessage.MetadataKind(rawValue: rawKind, remoteCryptoId: remoteCryptoId)
    }

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
        guard let context = self.managedObjectContext else { throw Self.makeError(message: "Cannot delete PersistedMessageTimestampedMetadata instance, context is nil") }
        context.delete(self)
    }
    
    public override func didSave() {
        super.didSave()
        if isInserted {
            guard let message = self.message else { assertionFailure(); return }
            ObvMessengerCoreDataNotification.persistedMessageHasNewMetadata(persistedMessageObjectID: message.objectID)
                .postOnDispatchQueue()
        }
    }

    struct Predicate {
        enum Key: String {
            // Attributes
            case rawKind = "rawKind"
            case date = "date"
            case remoteIdentity = "remoteIdentity"
            // Relationships
            case message = "message"
        }
        static func forMessage(_ message: PersistedMessage) -> NSPredicate {
            NSPredicate(Key.message, equalTo: message)
        }
        static func forMessage(withObjectID messageObjectID: NSManagedObjectID) -> NSPredicate {
            NSPredicate(Key.message, equalToObjectWithObjectID: messageObjectID)
        }
        static var excludeKindRead: NSPredicate {
            NSPredicate(Key.rawKind, DistinctFromInt: PersistedMessage.MetadataKind.read.rawValue)
        }
        static func withKind(_ kind: PersistedMessage.MetadataKind) -> NSPredicate {
            NSPredicate(Key.rawKind, EqualToInt: kind.rawValue)
        }
        static var withoutMessage: NSPredicate {
            NSPredicate(withNilValueForKey: Key.message)
        }
    }

    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedMessageTimestampedMetadata> {
        return NSFetchRequest<PersistedMessageTimestampedMetadata>(entityName: PersistedMessageTimestampedMetadata.entityName)
    }

    
    public static func getFetchRequest(messageObjectID: NSManagedObjectID, excludeKindRead: Bool) -> NSFetchRequest<PersistedMessageTimestampedMetadata> {
        let request: NSFetchRequest<PersistedMessageTimestampedMetadata> = PersistedMessageTimestampedMetadata.fetchRequest()
        if excludeKindRead {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.forMessage(withObjectID: messageObjectID),
                Predicate.excludeKindRead,
            ])
        } else {
            request.predicate = Predicate.forMessage(withObjectID: messageObjectID)
        }
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.date.rawValue, ascending: true)]
        return request
    }

    
    public static func deleteOrphanedPersistedMessageTimestampedMetadata(within obvContext: ObvContext) throws {
        let request = PersistedMessageTimestampedMetadata.fetchRequest()
        request.predicate = Predicate.withoutMessage
        request.fetchLimit = 10_000
        let orphanedObjects = try obvContext.context.fetch(request)
        for object in orphanedObjects {
            do {
                try object.delete()
            } catch {
                assertionFailure()
            }
        }
    }
}


// MARK: - Downcasting ObvManagedObjectPermanentID of subclasses of PersistedMessage

extension ObvManagedObjectPermanentID where T: PersistedMessage {

    public var downcast: ObvManagedObjectPermanentID<PersistedMessage> {
        ObvManagedObjectPermanentID<PersistedMessage>(entityName: PersistedMessage.entityName, uuid: self.uuid)
    }
     
    public init?(_ description: String) {
        self.init(description, expectedEntityName: PersistedMessage.entityName)
    }

}
