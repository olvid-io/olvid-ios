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
import ObvTypes
import MobileCoreServices
import OlvidUtils


@objc(PersistedMessageReceived)
public final class PersistedMessageReceived: PersistedMessage, ObvIdentifiableManagedObject {
    
    public static let entityName = "PersistedMessageReceived"
    private static let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "PersistedMessageReceived")

    /// At reception, a message is marked as `new`. When it is displayed to the user, it is marked as `unread` if `readOnce` is `true` and to `read` otherwise. An unread message for which `readOnce` is `true` is marked as `read` as soon as the user reads it. In that case, the message is deleted as soon as the user exits the discussion.
    public enum MessageStatus: Int {
        case new = 0
        case unread = 2
        case read = 1
    }

    // MARK: Attributes

    @NSManaged public private(set) var messageIdentifierFromEngine: Data
    @NSManaged public private(set) var missedMessageCount: Int
    @NSManaged private(set) var senderIdentifier: Data
    @NSManaged private(set) var senderThreadIdentifier: UUID
    @NSManaged private var serializedReturnReceipt: Data?

    // MARK: Relationships
    
    @NSManaged public private(set) var contactIdentity: PersistedObvContactIdentity?
    @NSManaged public private(set) var expirationForReceivedLimitedExistence: PersistedExpirationForReceivedMessageWithLimitedExistence?
    @NSManaged public private(set) var expirationForReceivedLimitedVisibility: PersistedExpirationForReceivedMessageWithLimitedVisibility?
    @NSManaged private var messageRepliedToIdentifier: PendingRepliedTo?
    @NSManaged private var unsortedFyleMessageJoinWithStatus: Set<ReceivedFyleMessageJoinWithStatus>


    // MARK: Other variables

    private var userInfoForDeletion: [String: Any]?
    private var changedKeys = Set<String>()

    public var objectPermanentID: ObvManagedObjectPermanentID<PersistedMessageReceived> {
        ObvManagedObjectPermanentID<PersistedMessageReceived>(uuid: self.permanentUUID)
    }

    public override var kind: PersistedMessageKind { .received }

    public override var textBody: String? {
        if readingRequiresUserAction {
            return NSLocalizedString("EPHEMERAL_MESSAGE", comment: "")
        }
        return super.textBody
    }

    public override var initialExistenceDuration: TimeInterval? {
        guard let existenceExpiration = expirationForReceivedLimitedExistence else { return nil }
        return existenceExpiration.initialExpirationDuration
    }

    public override var fyleMessageJoinWithStatus: [FyleMessageJoinWithStatus]? {
        fyleMessageJoinWithStatuses
    }

    override var messageIdentifiersFromEngine: Set<Data> {
        [messageIdentifierFromEngine]
    }

    public private(set) var status: MessageStatus {
        get { return MessageStatus(rawValue: self.rawStatus)! }
        set {
            guard self.status != newValue else { return }
            self.rawStatus = newValue.rawValue
            discussion.resetNewReceivedMessageDoesMentionOwnedIdentityValue()
            switch self.status {
            case .new:
                break
            case .unread:
                break
            case .read:
                // When a received message is marked as "read", we check whether it has a limited visibility.
                // If this is the case, we immediately create an appropriate expiration for this message.
                if let visibilityDuration = self.visibilityDuration {
                    assert(self.expirationForReceivedLimitedVisibility == nil)
                    self.expirationForReceivedLimitedVisibility = PersistedExpirationForReceivedMessageWithLimitedVisibility(messageReceivedWithLimitedVisibility: self,
                                                                                                                             visibilityDuration: visibilityDuration)
                }
            }
        }
    }

    public var fyleMessageJoinWithStatuses: [ReceivedFyleMessageJoinWithStatus] {
        let nonWipedUnsortedFyleMessageJoinWithStatus = unsortedFyleMessageJoinWithStatus.filter({ !$0.isWiped })
        switch nonWipedUnsortedFyleMessageJoinWithStatus.count {
        case 0:
            return []
        case 1:
            return [nonWipedUnsortedFyleMessageJoinWithStatus.first!]
        default:
            return nonWipedUnsortedFyleMessageJoinWithStatus.sorted(by: { $0.index < $1.index })
        }
    }

    public var returnReceipt: ReturnReceiptJSON? {
        guard let serializedReturnReceipt = self.serializedReturnReceipt else { return nil }
        do {
            return try ReturnReceiptJSON.jsonDecode(serializedReturnReceipt)
        } catch let error {
            os_log("Could not decode a return receipt of a received message: %{public}@", log: PersistedMessageReceived.log, type: .fault, error.localizedDescription)
            return nil
        }
    }


    public var isEphemeralMessage: Bool {
        self.readOnce || self.visibilityDuration != nil || self.initialExistenceDuration != nil
    }
 
    public var isEphemeralMessageWithUserAction: Bool {
        self.readOnce || self.visibilityDuration != nil
    }

    /// Called when a received message was globally wiped by a contact
    public func wipeByContact(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId, messageUploadTimestampFromServer: Date) throws -> InfoAboutWipedOrDeletedPersistedMessage {
        let info = InfoAboutWipedOrDeletedPersistedMessage(kind: .wiped,
                                                           discussionPermanentID: discussion.discussionPermanentID,
                                                           messagePermanentID: self.messagePermanentID)
        let requester = RequesterOfMessageDeletion.contact(ownedCryptoId: ownedCryptoId,
                                                           contactCryptoId: contactCryptoId,
                                                           messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        try throwIfRequesterIsNotAllowedToDeleteMessage(requester: requester)
        for join in fyleMessageJoinWithStatuses {
            try join.wipe()
        }
        self.deleteBodyAndMentions()
        try? self.reactions.forEach { try $0.delete() }
        try addMetadata(kind: .remoteWiped(remoteCryptoId: contactCryptoId), date: Date())
        return info
    }

    
    public func replaceContentWith(newBody: String?, newMentions: Set<MessageJSON.UserMention>, requester: ObvCryptoId, messageUploadTimestampFromServer: Date) throws {
        guard self.contactIdentity?.cryptoId == requester else { throw Self.makeError(message: "The requester is not the contact who created the original message") }
        guard self.textBody != newBody else { return }
        try super.replaceContentWith(newBody: newBody, newMentions: newMentions)
        try deleteMetadataOfKind(.edited)
        try addMetadata(kind: .edited, date: messageUploadTimestampFromServer)
    }
    
    
    /// `true` when this instance can be edited after being received
    override var textBodyCanBeEdited: Bool {
        switch discussion.status {
        case .active:
            guard !self.isLocallyWiped else { return false }
            guard !self.isRemoteWiped else { return false }
            return true
        case .preDiscussion, .locked:
            return false
        }
    }

    
    public func updateMissedMessageCount(with missedMessageCount: Int) {
        self.missedMessageCount = missedMessageCount
    }

    override func toMessageReferenceJSON() -> MessageReferenceJSON? {
        return toReceivedMessageReferenceJSON()
    }

    public override var genericRepliesTo: PersistedMessage.RepliedMessage {
        repliesTo
    }

    public override var shouldBeDeleted: Bool {
        return super.shouldBeDeleted
    }

}


// MARK: Initializer

extension PersistedMessageReceived {
    
    public convenience init(messageUploadTimestampFromServer: Date, downloadTimestampFromServer: Date, localDownloadTimestamp: Date, messageJSON: MessageJSON, contactIdentity: PersistedObvContactIdentity, messageIdentifierFromEngine: Data, returnReceiptJSON: ReturnReceiptJSON?, missedMessageCount: Int, discussion: PersistedDiscussion, obvMessageContainsAttachments: Bool) throws {
        
        // Disallow the creation of an "empty" message
        let messageBodyIsEmpty = (messageJSON.body == nil || messageJSON.body?.isEmpty == true)
        guard !messageBodyIsEmpty || obvMessageContainsAttachments else {
            assertionFailure()
            throw Self.makeError(message: "Trying to create an empty PersistedMessageReceived")
        }
        
        guard let context = discussion.managedObjectContext else { throw PersistedMessageReceived.makeError(message: "Could not find context") }
        
        // Received messages can only be created when the discussion status is 'active'
        
        switch discussion.status {
        case .locked, .preDiscussion:
            throw Self.makeError(message: "Cannot create PersistedMessageReceived, the discussion is not active")
        case .active:
            break
        }
        
        switch try discussion.kind {
        case .oneToOne(withContactIdentity: let contactIdentityOfDiscussion):
            guard contactIdentityOfDiscussion == contactIdentity else {
                assertionFailure()
                throw PersistedMessageReceived.makeError(message: "The referenced one2one discussion corresponds to a different contact than the one that sent the message.")
            }
        case .groupV1(withContactGroup: let contactGroup):
            // We check that the received message comes from a member (likely) or a pending member (unlikely, but still)
            guard let contactGroup = contactGroup else {
                os_log("Could find contact group (this is ok if it was just deleted)", log: PersistedMessageReceived.log, type: .error)
                assertionFailure()
                throw PersistedMessageReceived.makeError(message: "Could find contact group (this is ok if it was just deleted)")
            }
            let pendingMembersCryptoIds = contactGroup.pendingMembers.map { $0.cryptoId }
            guard contactGroup.contactIdentities.contains(contactIdentity) || pendingMembersCryptoIds.contains(contactIdentity.cryptoId) else {
                os_log("The PersistedGroupDiscussion list of contacts does not contain the contact that sent a message within this discussion", log: PersistedMessageReceived.log, type: .error)
                assertionFailure()
                throw PersistedMessageReceived.makeError(message: "The PersistedGroupDiscussion list of contacts does not contain the contact that sent a message within this discussion")
            }
        case .groupV2(withGroup: let group):
            guard let group = group else {
                os_log("Could find group v2 (this is ok if it was just deleted)", log: PersistedMessageReceived.log, type: .error)
                assertionFailure()
                throw PersistedMessageReceived.makeError(message: "Could find group v2 (this is ok if it was just deleted)")
            }
            guard let member = group.otherMembers.first(where: { $0.identity == contactIdentity.identity }) else {
                os_log("The list of other members of the group does not contain the contact that sent a message within this discussion", log: PersistedMessageReceived.log, type: .error)
                assertionFailure()
                throw PersistedMessageReceived.makeError(message: "The list of other members of the group does not contain the contact that sent a message within this discussion")
            }
            guard member.isAllowedToSendMessage else {
                os_log("We received a group v2 message from a member who is not allowed to send messages. We discard the message.", log: PersistedMessageReceived.log, type: .error)
                assertionFailure()
                throw PersistedMessageReceived.makeError(message: "We received a group v2 message from a member who is not allowed to send messages. We discard the message.")
            }
        }
        
        let (sortIndex, adjustedTimestamp) = try PersistedMessageReceived.determineAppropriateSortIndex(
            forSenderSequenceNumber: messageJSON.senderSequenceNumber,
            senderThreadIdentifier: messageJSON.senderThreadIdentifier,
            contactIdentity: contactIdentity,
            timestamp: messageUploadTimestampFromServer,
            within: discussion)

        let isReplyToAnotherMessage: Bool
        let replyTo: PersistedMessage?
        let messageRepliedToIdentifier: PendingRepliedTo?
        if let replyToJSON = messageJSON.replyTo {
            isReplyToAnotherMessage = true
            replyTo = try PersistedMessage.findMessageFrom(reference: replyToJSON, within: discussion)
            if replyTo == nil {
                messageRepliedToIdentifier = PendingRepliedTo(replyToJSON: replyToJSON, within: context)
            } else {
                messageRepliedToIdentifier = nil
            }
        } else {
            isReplyToAnotherMessage = false
            replyTo = nil
            messageRepliedToIdentifier = nil
        }

        try self.init(timestamp: adjustedTimestamp,
                      body: messageJSON.body,
                      rawStatus: MessageStatus.new.rawValue,
                      senderSequenceNumber: messageJSON.senderSequenceNumber,
                      sortIndex: sortIndex,
                      isReplyToAnotherMessage: isReplyToAnotherMessage,
                      replyTo: replyTo,
                      discussion: discussion,
                      readOnce: messageJSON.expiration?.readOnce ?? false,
                      visibilityDuration: messageJSON.expiration?.visibilityDuration,
                      forwarded: messageJSON.forwarded,
                      mentions: messageJSON.userMentions,
                      forEntityName: PersistedMessageReceived.entityName)

        self.messageRepliedToIdentifier = messageRepliedToIdentifier
        self.contactIdentity = contactIdentity
        self.senderIdentifier = contactIdentity.cryptoId.getIdentity()
        self.senderThreadIdentifier = messageJSON.senderThreadIdentifier
        self.serializedReturnReceipt = try returnReceiptJSON?.jsonEncode()
        self.messageIdentifierFromEngine = messageIdentifierFromEngine
        self.unsortedFyleMessageJoinWithStatus = Set<ReceivedFyleMessageJoinWithStatus>()
        self.missedMessageCount = missedMessageCount

        // As soon as we receive a message, we check whether it has a limited existence.
        // If this is the case, we immediately create an appropriate expiration for this message.
        if let existenceDuration = messageJSON.expiration?.existenceDuration {
            assert(self.expirationForReceivedLimitedExistence == nil)
            self.expirationForReceivedLimitedExistence = PersistedExpirationForReceivedMessageWithLimitedExistence(messageReceivedWithLimitedExistence: self,
                                                                                                                   existenceDuration: existenceDuration,
                                                                                                                   messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                                                                                                                   downloadTimestampFromServer: downloadTimestampFromServer,
                                                                                                                   localDownloadTimestamp: localDownloadTimestamp)
        }
        
        // Now that this message is created, we can look for all the messages that have a `messageRepliedToIdentifier` referencing this message.
        // For these messages, we delete this reference and, instead, reference this message using the `messageRepliedTo` relationship.
        
        try self.updateMessagesReplyingToThisMessage()

    }
    
    
    /// When creating a new `PersistedMessageReceived`, we need to search for previous `PersistedMessageReceived` that are a reply to this message.
    /// These messages have a non-nil `messageRepliedToIdentifier` relationship that references this message. This method searches for these
    /// messages, delete the `messageRepliedToIdentifier` and replaces it by a non-nil `messageRepliedTo` relationship.
    private func updateMessagesReplyingToThisMessage() throws {

        guard let context = self.managedObjectContext else { throw Self.makeError(message: "Could not find context") }

        let pendingRepliedTos = try PendingRepliedTo.getAll(senderIdentifier: self.senderIdentifier,
                                                            senderSequenceNumber: self.senderSequenceNumber,
                                                            senderThreadIdentifier: self.senderThreadIdentifier,
                                                            discussion: self.discussion,
                                                            within: context)
        pendingRepliedTos.forEach { pendingRepliedTo in
            guard let reply = pendingRepliedTo.message else {
                assertionFailure()
                try? pendingRepliedTo.delete()
                return
            }
            assert(reply.isReplyToAnotherMessage)
            reply.setRawMessageRepliedTo(with: self)
            reply.messageRepliedToIdentifier = nil
            try? pendingRepliedTo.delete()
        }

    }

    
    public func update(withMessageJSON json: MessageJSON, messageIdentifierFromEngine: Data, returnReceiptJSON: ReturnReceiptJSON?, messageUploadTimestampFromServer: Date, downloadTimestampFromServer: Date, localDownloadTimestamp: Date, discussion: PersistedDiscussion) throws {
        guard self.messageIdentifierFromEngine == messageIdentifierFromEngine else {
            throw Self.makeError(message: "Invalid message identifier from engine")
        }
        
        guard !isWiped else {
            return
        }
        
        let replyTo: PersistedMessage?
        if let replyToJSON = json.replyTo {
            replyTo = try PersistedMessage.findMessageFrom(reference: replyToJSON, within: discussion)
        } else {
            replyTo = nil
        }

        try self.update(body: json.body,
                        newMentions: Set(json.userMentions),
                        senderSequenceNumber: json.senderSequenceNumber,
                        replyTo: replyTo,
                        discussion: discussion)
                
        do {
            self.serializedReturnReceipt = try returnReceiptJSON?.jsonEncode()
        } catch let error {
            os_log("Could not encode a return receipt while create a persisted message received: %{public}@", log: PersistedMessageReceived.log, type: .fault, error.localizedDescription)
            assertionFailure()
        }

        if let expirationJson = json.expiration {
            if expirationJson.readOnce {
                self.readOnce = true
            }
            if self.visibilityDuration == nil && expirationJson.visibilityDuration != nil {
                self.visibilityDuration = expirationJson.visibilityDuration
            }
            if self.expirationForReceivedLimitedExistence == nil && expirationJson.existenceDuration != nil {
                self.expirationForReceivedLimitedExistence = PersistedExpirationForReceivedMessageWithLimitedExistence(messageReceivedWithLimitedExistence: self,
                                                                                                                       existenceDuration: expirationJson.existenceDuration!,
                                                                                                                       messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                                                                                                                       downloadTimestampFromServer: downloadTimestampFromServer,
                                                                                                                       localDownloadTimestamp: localDownloadTimestamp)
            }
        }
    }

    static private func determineAppropriateSortIndex(forSenderSequenceNumber senderSequenceNumber: Int, senderThreadIdentifier: UUID, contactIdentity: PersistedObvContactIdentity, timestamp: Date, within discussion: PersistedDiscussion) throws -> (sortIndex: Double, adjustedTimestamp: Date) {
        
        let nextMsg = getNextMessageBySenderSequenceNumber(senderSequenceNumber,
                                                           senderThreadIdentifier: senderThreadIdentifier,
                                                           contactIdentity: contactIdentity,
                                                           within: discussion)
        
        if nextMsg == nil || nextMsg!.timestamp > timestamp {
            let prevMsg = getPreviousMessageBySenderSequenceNumber(senderSequenceNumber,
                                                                   senderThreadIdentifier: senderThreadIdentifier,
                                                                   contactIdentity: contactIdentity,
                                                                   within: discussion)
            if prevMsg == nil || prevMsg!.timestamp < timestamp {
                return (timestamp.timeIntervalSince1970, timestamp)
            } else {
                // The previous message's timestamp is larger than the received message timestamp. Rare case. We adjust the timestamp of the received message in order to avoid weird timelines
                let msgRightAfterPrevMsg = try getMessage(afterSortIndex: prevMsg!.sortIndex, in: discussion)
                let sortIndexRightAfterPrevMsgSortIndex = msgRightAfterPrevMsg?.sortIndex ?? (prevMsg!.sortIndex + 1/100.0)
                let adjustedTimestamp = prevMsg!.timestamp
                let sortIndex = (sortIndexRightAfterPrevMsgSortIndex + prevMsg!.sortIndex) / 2.0
                return (sortIndex, adjustedTimestamp)
            }
        } else {
            // There is a next message by the same sender, and its timestamp is smaller than the received message. Rare case. We adjust the timestamp of the received message in order to avoid weird timelines
            let msgRightBeforeNextMsg = try getMessage(beforeSortIndex: nextMsg!.sortIndex, in: discussion)
            let sortIndexRightBeforeNextMsgSortIndex = msgRightBeforeNextMsg?.sortIndex ?? (nextMsg!.sortIndex - 1/100.0)
            let adjustedTimestamp = nextMsg!.timestamp
            let sortIndex = (sortIndexRightBeforeNextMsgSortIndex + nextMsg!.sortIndex) / 2.0
            return (sortIndex, adjustedTimestamp)
        }
        
    }

    
    public func allowReading(now: Date) throws {
        assert(isEphemeralMessageWithUserAction)
        guard isEphemeralMessageWithUserAction else {
            assertionFailure("There is no reason why this is called on a message that is not marked as readOnce or with a certain visibility")
            return
        }
        try self.markAsRead(now: now)
    }

    /// This allows to prevent auto-read for messages received with a more restrictive ephemerality than that of the discussion.
    public var ephemeralityIsAtLeastAsPermissiveThanDiscussionSharedConfiguration: Bool {
        if self.readOnce {
            guard discussion.sharedConfiguration.readOnce else { return false }
        }
        if let messageVisibilityDuration = self.visibilityDuration {
            guard let discussionVisibilityDuration = self.discussion.sharedConfiguration.visibilityDuration else { return false }
            guard messageVisibilityDuration >= discussionVisibilityDuration else { return false }
        }
        if let messageExistenceDuration = self.initialExistenceDuration {
            guard let discussionExistenceDuration = self.discussion.sharedConfiguration.existenceDuration else { return false }
            guard messageExistenceDuration >= discussionExistenceDuration else { return false }
        }
        return true
    }
    
}


// MARK: Determining actions availability

extension PersistedMessageReceived {
    
    var copyActionCanBeMadeAvailableForReceivedMessage: Bool {
        return shareActionCanBeMadeAvailableForReceivedMessage
    }

    var shareActionCanBeMadeAvailableForReceivedMessage: Bool {
        guard !readingRequiresUserAction else { return false }
        return !isEphemeralMessageWithUserAction
    }
    
    var forwardActionCanBeMadeAvailableForReceivedMessage: Bool {
        return shareActionCanBeMadeAvailableForReceivedMessage
    }
    
    var infoActionCanBeMadeAvailableForReceivedMessage: Bool {
        return !metadata.isEmpty
    }

    var replyToActionCanBeMadeAvailableForReceivedMessage: Bool {
        guard discussion.status == .active else { return false }
        if readOnce {
            return status == .read
        }
        return true
    }
    
    var deleteOwnReactionActionCanBeMadeAvailableForReceivedMessage: Bool {
        return reactions.contains { $0 is PersistedMessageReactionSent }
    }
    
}


// MARK: Reply-to

extension PersistedMessageReceived {

    var repliesTo: RepliedMessage {
        if let messageRepliedTo = self.rawMessageRepliedTo {
            return .available(message: messageRepliedTo)
        } else if self.messageRepliedToIdentifier != nil {
            return .notAvailableYet
        } else if self.isReplyToAnotherMessage {
            return .deleted
        } else {
            return .none
        }
    }
    
}


// MARK: Other methods

extension PersistedMessageReceived {

    public func markAsNotNew(now: Date) throws {
        switch self.status {
        case .new:
            if isEphemeralMessageWithUserAction {
                self.status = .unread
            } else {
                try markAsRead(now: now)
            }
        case .unread, .read:
            break
        }
    }
    
    private func markAsRead(now: Date) throws {
        os_log("Call to markAsRead in PersistedMessageReceived for message %{public}@", log: PersistedMessageReceived.log, type: .debug, self.objectID.debugDescription)
        if self.status != .read {
            self.status = .read
            try self.addMetadata(kind: .read, date: now)
        }
    }
        
    
    public var readingRequiresUserAction: Bool {
        guard isEphemeralMessageWithUserAction else { return false }
        switch self.status {
        case .new, .unread:
            return true
        case .read:
            return false
        }
    }

    
    func toReceivedMessageReferenceJSON() -> MessageReferenceJSON? {
        return MessageReferenceJSON(senderSequenceNumber: self.senderSequenceNumber,
                                    senderThreadIdentifier: self.senderThreadIdentifier,
                                    senderIdentifier: self.senderIdentifier)
    }
}


// MARK: Convenience DB getters

extension PersistedMessageReceived {
    
    struct Predicate {
        enum Key: String {
            // Attributes
            case messageIdentifierFromEngine = "messageIdentifierFromEngine"
            case missedMessageCount = "missedMessageCount"
            case senderIdentifier = "senderIdentifier"
            case senderThreadIdentifier = "senderThreadIdentifier"
            case serializedReturnReceipt = "serializedReturnReceipt"
            // Relationships
            case contactIdentity = "contactIdentity"
            case expirationForReceivedLimitedExistence = "expirationForReceivedLimitedExistence"
            case expirationForReceivedLimitedVisibility = "expirationForReceivedLimitedVisibility"
            case messageRepliedToIdentifier = "messageRepliedToIdentifier"
            case unsortedFyleMessageJoinWithStatus = "unsortedFyleMessageJoinWithStatus"
            // Others
            static let contactIdentityIdentity = [contactIdentity.rawValue, PersistedObvContactIdentity.Predicate.Key.identity.rawValue].joined(separator: ".")
            static let expirationForReceivedLimitedExistenceExpirationDate = [expirationForReceivedLimitedExistence.rawValue, PersistedMessageExpiration.Predicate.Key.expirationDate.rawValue].joined(separator: ".")
            static let expirationForReceivedLimitedVisibilityExpirationDate = [expirationForReceivedLimitedVisibility.rawValue, PersistedMessageExpiration.Predicate.Key.expirationDate.rawValue].joined(separator: ".")
        }
        static var ownedIdentityIsNotHidden: NSPredicate {
            PersistedMessage.Predicate.ownedIdentityIsNotHidden
        }
        static func withStatus(_ status: MessageStatus) -> NSPredicate {
            NSPredicate(PersistedMessage.Predicate.Key.rawStatus, EqualToInt: status.rawValue)
        }
        static var isNew: NSPredicate { withStatus(.new) }
        static var isUnread: NSPredicate { withStatus(.unread) }
        static var isRead: NSPredicate { withStatus(.read) }
        static var isNotNewAnymore: NSPredicate {
            NSPredicate(PersistedMessage.Predicate.Key.rawStatus, LargerThanInt: MessageStatus.new.rawValue)
        }
        static func withinDiscussion(_ discussion: PersistedDiscussion) -> NSPredicate {
            PersistedMessage.Predicate.withinDiscussion(discussion)
        }
        static func withinDiscussion(_ discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) -> NSPredicate {
            PersistedMessage.Predicate.withinDiscussion(discussionObjectID)
        }
        static func withinDiscussion(_ discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>) -> NSPredicate {
            PersistedMessage.Predicate.withinDiscussionWithPermanentID(discussionPermanentID)
        }
        static func withContactIdentity(_ contactIdentity: PersistedObvContactIdentity) -> NSPredicate {
            NSPredicate(Key.contactIdentity, equalTo: contactIdentity)
        }
        static func withContactIdentityIdentity(_ contactIdentity: Data) -> NSPredicate {
            NSPredicate(Key.contactIdentityIdentity, EqualToData: contactIdentity)
        }
        static func withSenderThreadIdentifier(_ senderThreadIdentifier: UUID) -> NSPredicate {
            NSPredicate(Key.senderThreadIdentifier, EqualToUuid: senderThreadIdentifier)
        }
        static var readOnce: NSPredicate {
            NSPredicate(PersistedMessage.Predicate.Key.readOnce, is: true)
        }
        static func forOwnedIdentity(_ ownedIdentity: PersistedObvOwnedIdentity) -> NSPredicate {
            PersistedMessage.Predicate.withOwnedIdentity(ownedIdentity)
        }
        static func forOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> NSPredicate {
            PersistedMessage.Predicate.withOwnedCryptoId(ownedCryptoId)
        }
        static var expiresForReceivedLimitedVisibility: NSPredicate {
            NSPredicate(withNonNilValueForKey: Key.expirationForReceivedLimitedVisibility)
        }
        static var expiresForReceivedLimitedExistence: NSPredicate {
            NSPredicate(withNonNilValueForKey: Key.expirationForReceivedLimitedExistence)
        }
        static var hasVisibilityDuration: NSPredicate {
            NSPredicate(withNonNilValueForKey: PersistedMessage.Predicate.Key.rawVisibilityDuration)
        }
        static var expiredBeforeNow: NSPredicate {
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    expiresForReceivedLimitedVisibility,
                    NSPredicate(Key.expirationForReceivedLimitedVisibilityExpirationDate, earlierThan: Date()),
                ]),
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    expiresForReceivedLimitedExistence,
                    NSPredicate(Key.expirationForReceivedLimitedExistenceExpirationDate, earlierThan: Date()),
                ]),
            ])
        }
        static func createdBefore(date: Date) -> NSPredicate {
            NSPredicate(PersistedMessage.Predicate.Key.timestamp, earlierThan: date)
        }
        static func withLargerSortIndex(than message: PersistedMessage) -> NSPredicate {
            NSPredicate(PersistedMessage.Predicate.Key.sortIndex, LargerThanDouble: message.sortIndex)
        }
        static func withObjectID(_ objectID: NSManagedObjectID) -> NSPredicate {
            NSPredicate(withObjectID: objectID)
        }
        static func withMessageIdentifierFromEngine(_ messageIdentifierFromEngine: Data) -> NSPredicate {
            NSPredicate(Key.messageIdentifierFromEngine, EqualToData: messageIdentifierFromEngine)
        }
        static var isDiscussionUnmuted: NSPredicate {
            PersistedMessage.Predicate.isDiscussionUnmuted
        }
    }
    

    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedMessageReceived> {
        return NSFetchRequest<PersistedMessageReceived>(entityName: PersistedMessageReceived.entityName)
    }

    
    public static func get(with objectID: TypeSafeManagedObjectID<PersistedMessageReceived>, within context: NSManagedObjectContext) throws -> PersistedMessageReceived? {
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = Predicate.withObjectID(objectID.objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    public static func getNextMessageBySenderSequenceNumber(_ sequenceNumber: Int, senderThreadIdentifier: UUID, contactIdentity: PersistedObvContactIdentity, within discussion: PersistedDiscussion) -> PersistedMessageReceived? {
        guard let context = discussion.managedObjectContext else { return nil }
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            Predicate.withContactIdentity(contactIdentity),
            Predicate.withSenderThreadIdentifier(senderThreadIdentifier),
            PersistedMessage.Predicate.withSenderSequenceNumberLargerThan(sequenceNumber),
        ])
        request.sortDescriptors = [NSSortDescriptor(key: PersistedMessage.Predicate.Key.senderSequenceNumber.rawValue, ascending: true)]
        request.fetchLimit = 1
        do { return try context.fetch(request).first } catch { return nil }
    }

    
    static func getPreviousMessageBySenderSequenceNumber(_ sequenceNumber: Int, senderThreadIdentifier: UUID, contactIdentity: PersistedObvContactIdentity, within discussion: PersistedDiscussion) -> PersistedMessageReceived? {
        guard let context = discussion.managedObjectContext else { return nil }
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            Predicate.withContactIdentity(contactIdentity),
            Predicate.withSenderThreadIdentifier(senderThreadIdentifier),
            PersistedMessage.Predicate.withSenderSequenceNumberLessThan(sequenceNumber),
        ])
        request.sortDescriptors = [NSSortDescriptor(key: PersistedMessage.Predicate.Key.senderSequenceNumber.rawValue, ascending: false)]
        request.fetchLimit = 1
        do { return try context.fetch(request).first } catch { return nil }
    }

    
    /// Each message of the discussion that is in the status `new` changes status as follows:
    /// - If the message is such that `hasWipeAfterRead` is `true`, the new status is `unread`
    /// - Otherwise, the new status is `read`.
    public static func markAllAsNotNew(within discussion: PersistedDiscussion) throws {
        os_log("Call to markAllAsNotNew in PersistedMessageReceived for discussion %{public}@", log: log, type: .debug, discussion.objectID.debugDescription)
        guard let context = discussion.managedObjectContext else { return }
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.includesSubentities = true
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            Predicate.isNew,
        ])
        let messages = try context.fetch(request)
        guard !messages.isEmpty else { return }
        let now = Date()
        try messages.forEach {
            try $0.markAsNotNew(now: now)
        }
    }


    /// Return readOnce and limited visibility messages with a timestamp less or equal to the specified date.
    /// As we expect these messages to be deleted, we only fetch a limited number of properties.
    /// This method should only be used to fetch messages that will eventually be deleted.
    public static func getAllReadOnceAndLimitedVisibilityReceivedMessagesToDelete(until date: Date, within context: NSManagedObjectContext) throws -> [PersistedMessageReceived] {
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                Predicate.hasVisibilityDuration,
                Predicate.readOnce,
            ]),
            PersistedMessage.Predicate.createdBeforeIncluded(date: date)
        ])
        request.relationshipKeyPathsForPrefetching = [PersistedMessage.Predicate.Key.discussion.rawValue] // The delete() method needs the discussion to return infos
        request.propertiesToFetch = [PersistedMessage.Predicate.Key.timestamp.rawValue] // The WipeAllEphemeralMessages operation needs the timestamp
        request.fetchBatchSize = 100 // Keep memory footprint low
        return try context.fetch(request)
    }

    
    public static func getDateOfLatestReceivedMessageWithLimitedVisibilityOrReadOnce(within context: NSManagedObjectContext) throws -> Date? {
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            Predicate.hasVisibilityDuration,
            Predicate.readOnce,
        ])
        request.sortDescriptors = [NSSortDescriptor(key: PersistedMessage.Predicate.Key.timestamp.rawValue, ascending: false)]
        request.propertiesToFetch = [PersistedMessage.Predicate.Key.timestamp.rawValue]
        request.fetchLimit = 1
        let message = try context.fetch(request).first
        return message?.timestamp
    }


    public static func countNew(within discussion: PersistedDiscussion) throws -> Int {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Could not find context") }
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.isNew,
            Predicate.withinDiscussion(discussion)])
        return try context.count(for: request)
    }

    static func countNewAndMentionningOwnedIdentity(within discussion: PersistedDiscussion) throws -> Int {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Could not find context") }
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.isNew,
            Predicate.withinDiscussion(discussion),
            PersistedMessage.Predicate.doesMentionOwnedIdentity,
        ])
        return try context.count(for: request)
    }


    /// This method returns "all" the received messages with the given identifier from engine. In practice, we do not expect more than on message within the array.
    public static func getAll(messageIdentifierFromEngine: Data, within context: NSManagedObjectContext) throws -> [PersistedMessageReceived] {
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = Predicate.withMessageIdentifierFromEngine(messageIdentifierFromEngine)
        request.fetchBatchSize = 10
        return try context.fetch(request)
    }

    
    public static func get(messageIdentifierFromEngine: Data, ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> PersistedMessageReceived? {
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.forOwnedCryptoId(ownedCryptoId),
            Predicate.withMessageIdentifierFromEngine(messageIdentifierFromEngine),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    public static func get(messageIdentifierFromEngine: Data, from contact: ObvContactIdentity, within context: NSManagedObjectContext) throws -> PersistedMessageReceived? {
        guard let persistedContact = try? PersistedObvContactIdentity.get(persisted: contact, whereOneToOneStatusIs: .any, within: context) else { return nil }
        return try get(messageIdentifierFromEngine: messageIdentifierFromEngine, from: persistedContact)
    }

    
    public static func get(messageIdentifierFromEngine: Data, from persistedContact: PersistedObvContactIdentity) throws -> PersistedMessageReceived? {
        guard let context = persistedContact.managedObjectContext else { throw Self.makeError(message: "PersistedObvContactIdentity's context is nil") }
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withMessageIdentifierFromEngine(messageIdentifierFromEngine),
            Predicate.withContactIdentity(persistedContact),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }


    public static func get(senderSequenceNumber: Int, senderThreadIdentifier: UUID, contactIdentity: Data, discussion: PersistedDiscussion) throws -> PersistedMessageReceived? {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Could not find context") }
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            PersistedMessage.Predicate.withSenderSequenceNumberEqualTo(senderSequenceNumber),
            Predicate.withSenderThreadIdentifier(senderThreadIdentifier),
            Predicate.withContactIdentityIdentity(contactIdentity),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    
    public static func getAllNew(with context: NSManagedObjectContext) throws -> [PersistedMessageReceived] {
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = Predicate.isNew
        return try context.fetch(request)
    }
    
    
    public static func getAllNew(in discussion: PersistedDiscussion) throws -> [PersistedMessageReceived] {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Could not find context in discussion object") }
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            Predicate.isNew,
        ])
        return try context.fetch(request)
    }
    
    
    public static func getFirstNew(in discussion: PersistedDiscussion) throws -> PersistedMessageReceived? {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Could not find context in discussion")}
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: PersistedMessage.Predicate.Key.sortIndex.rawValue, ascending: true)]
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            Predicate.isNew,
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    public static func getReceivedMessagesThatExpired(within context: NSManagedObjectContext) throws -> [PersistedMessageReceived] {
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = Predicate.expiredBeforeNow
        request.fetchBatchSize = 1_000
        return try context.fetch(request)
    }

    
    /// Fetches all inbound messages that are marked as readOnce and that have a status set to "read".
    /// This is typically used to return all the received messages to delete when exiting a discussion.
    public static func getReadOnceMarkedAsRead(restrictToDiscussionWithPermanentID discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>?, within context: NSManagedObjectContext) throws -> [PersistedMessageReceived] {
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        var predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.readOnce,
            Predicate.isRead,
        ])
        if let discussionPermanentID {
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                predicate,
                Predicate.withinDiscussion(discussionPermanentID),
            ])
        }
        request.predicate = predicate
        request.fetchBatchSize = 1_000
        return try context.fetch(request)
    }

    
    /// Returns all outbound messages within the specified discussion, such that :
    /// - The message was created before the specified date
    /// - The message is not new anymore (thus, either unread or read)
    /// This method is typically used for deleting messages that are older than the specified retention policy.
    public static func getAllNonNewReceivedMessagesCreatedBeforeDate(discussion: PersistedDiscussion, date: Date) throws -> [PersistedMessageReceived] {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Cannot find context in PersistedDiscussion") }
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            Predicate.createdBefore(date: date),
            Predicate.isNotNewAnymore,
        ])
        request.fetchBatchSize = 1_000
        return try context.fetch(request)
    }
    
    
    /// This method returns the number of inbound messages of the discussion that are not new (thus either unread or read).
    /// This method is typically used for later deleting messages so as to respect a count based retention policy.
    public static func countAllNonNewMessages(discussion: PersistedDiscussion) throws -> Int {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Cannot find context in PersistedDiscussion") }
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            Predicate.isNotNewAnymore,
        ])
        return try context.count(for: request)
    }
    
    
    /// This method returns the number of inbound messages of the discussion that are not new (thus either unread or read) and
    /// that occur after the message passed as a parameter.
    /// This method is typically used for displaying count based retention information for a specific message.
    public static func countAllSentMessages(after messageObjectID: NSManagedObjectID, discussion: PersistedDiscussion) throws -> Int {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Cannot find context in PersistedDiscussion") }
        guard let message = try PersistedMessage.get(with: messageObjectID, within: context) else {
            throw makeError(message: "Cannot find message to compare to")
        }
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            Predicate.isNotNewAnymore,
            Predicate.withLargerSortIndex(than: message),
        ])
        return try context.count(for: request)
    }
    

    public static func getAllReceivedMessagesThatRequireUserActionForReading(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, within context: NSManagedObjectContext) throws -> [PersistedMessageReceived] {
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussionPermanentID),
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                Predicate.isNew,
                Predicate.isUnread,
            ]),
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                Predicate.readOnce,
                Predicate.hasVisibilityDuration,
            ]),
        ])
        request.fetchBatchSize = 1_000
        return try context.fetch(request)
    }
    

    public static func batchDeletePendingRepliedToEntriesOlderThan(_ date: Date, within context: NSManagedObjectContext) throws {
        try PendingRepliedTo.batchDeleteEntriesOlderThan(date, within: context)
    }

    
}


@available(iOS 14, *)
extension PersistedMessageReceived {
    
    public var fyleMessageJoinWithStatusesOfImageType: [ReceivedFyleMessageJoinWithStatus] {
        fyleMessageJoinWithStatuses.filter({ Self.supportedImageTypeIdentifiers.contains($0.uti)  })
    }

    public var fyleMessageJoinWithStatusesOfAudioType: [ReceivedFyleMessageJoinWithStatus] {
        fyleMessageJoinWithStatuses.filter({ ObvUTIUtils.uti($0.uti, conformsTo: kUTTypeAudio) })
    }

    public var fyleMessageJoinWithStatusesOfOtherTypes: [ReceivedFyleMessageJoinWithStatus] {
        var result = fyleMessageJoinWithStatuses
        result.removeAll(where: { fyleMessageJoinWithStatusesOfImageType.contains($0)})
        result.removeAll(where: { fyleMessageJoinWithStatusesOfAudioType.contains($0)})
        return result
    }

}


// MARK: Sending notifications on change

extension PersistedMessageReceived {

    public override func prepareForDeletion() {
        
        defer {
            // Note that we only call super here, after setting the userInfoForDeletion, because we don't want this call to interfere.
            super.prepareForDeletion()
        }
        
        guard let managedObjectContext else { assertionFailure(); return }
        guard managedObjectContext.concurrencyType != .mainQueueConcurrencyType else { return }
        
        // Note that the following line may return nil if we are currently deleting a message that is part of a locked discussion.
        // In that case, we do not notify that the message is being deleted, but this is not an issue at this time
        if let ownedCryptoId = contactIdentity?.ownedIdentity?.cryptoId {
            userInfoForDeletion = ["objectID": objectID,
                                   "messageIdentifierFromEngine": messageIdentifierFromEngine,
                                   "ownedCryptoId": ownedCryptoId,
                                   "sortIndex": sortIndex,
                                   "discussionObjectID": discussion.typedObjectID]
        }
        
        
    }
    
    
    public override func willSave() {
        super.willSave()
        if !isInserted, !isDeleted, isUpdated {
            changedKeys = Set<String>(self.changedValues().keys)
        }
    }
    
    public override func didSave() {
        super.didSave()
        
        defer {
            self.userInfoForDeletion = nil
            self.changedKeys.removeAll()
        }
        
        if isDeleted, let userInfoForDeletion = self.userInfoForDeletion {
            guard let objectID = userInfoForDeletion["objectID"] as? NSManagedObjectID,
                  let messageIdentifierFromEngine = userInfoForDeletion["messageIdentifierFromEngine"] as? Data,
                  let ownedCryptoId = userInfoForDeletion["ownedCryptoId"] as? ObvCryptoId,
                  let sortIndex = userInfoForDeletion["sortIndex"] as? Double,
                  let discussionObjectID = userInfoForDeletion["discussionObjectID"] as? TypeSafeManagedObjectID<PersistedDiscussion> else {
                assertionFailure()
                return
            }
            ObvMessengerCoreDataNotification.persistedMessageReceivedWasDeleted(objectID: objectID, messageIdentifierFromEngine: messageIdentifierFromEngine, ownedCryptoId: ownedCryptoId, sortIndex: sortIndex, discussionObjectID: discussionObjectID)
                .postOnDispatchQueue()
            
        } else if (self.changedKeys.contains(PersistedMessage.Predicate.Key.rawStatus.rawValue) || isInserted) {
            if self.status == .read {
                ObvMessengerCoreDataNotification.persistedMessageReceivedWasRead(persistedMessageReceivedObjectID: self.typedObjectID)
                    .postOnDispatchQueue()
            }
            if isInserted, let returnReceipt = self.returnReceipt, let contactCryptoId = contactIdentity?.cryptoId, let ownedCryptoId = contactIdentity?.ownedIdentity?.cryptoId {
                ObvMessengerCoreDataNotification.aDeliveredReturnReceiptShouldBeSentForPersistedMessageReceived(
                    returnReceipt: returnReceipt,
                    contactCryptoId: contactCryptoId,
                    ownedCryptoId: ownedCryptoId,
                    messageIdentifierFromEngine: messageIdentifierFromEngine)
                .postOnDispatchQueue()
            }
        }
        
        if self.changedKeys.contains(PersistedMessage.Predicate.Key.body.rawValue) {
            ObvMessengerCoreDataNotification.theBodyOfPersistedMessageReceivedDidChange(persistedMessageReceivedObjectID: self.objectID)
                .postOnDispatchQueue()
        }
    }
}

public extension TypeSafeManagedObjectID where T == PersistedMessageReceived {
    var downcast: TypeSafeManagedObjectID<PersistedMessage> {
        TypeSafeManagedObjectID<PersistedMessage>(objectID: objectID)
    }
}


// MARK: - PendingRepliedTo

/// When receiving a message that replies to another message, it might happen that this replied-to message is not available
/// because it did not arrive yet. This entity makes it possible to save the elements (`senderIdentifier`, etc.) referencing
/// this replied-to message for later. Each time a new message arrive, we check the `PendingRepliedTo` entities and look
/// for all those that reference this arriving message. This allows to associate message with its replied-to message a posteriori.
@objc(PendingRepliedTo)
fileprivate final class PendingRepliedTo: NSManagedObject, ObvErrorMaker {

    private static let entityName = "PendingRepliedTo"
    static let errorDomain = "PendingRepliedTo"

    @NSManaged private var creationDate: Date
    @NSManaged private var senderIdentifier: Data
    @NSManaged private var senderSequenceNumber: Int
    @NSManaged private var senderThreadIdentifier: UUID
        
    @NSManaged private(set) var message: PersistedMessageReceived?

    convenience init?(replyToJSON: MessageReferenceJSON, within context: NSManagedObjectContext) {
        
        let entityDescription = NSEntityDescription.entity(forEntityName: PendingRepliedTo.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.creationDate = Date()
        self.senderSequenceNumber = replyToJSON.senderSequenceNumber
        self.senderThreadIdentifier = replyToJSON.senderThreadIdentifier
        self.senderIdentifier = replyToJSON.senderIdentifier

    }

    
    fileprivate func delete() throws {
        guard let context = self.managedObjectContext else { throw Self.makeError(message: "Could not find context") }
        context.delete(self)
    }
    
    
    private struct Predicate {
        enum Key: String {
            case creationDate = "creationDate"
            case senderIdentifier = "senderIdentifier"
            case senderSequenceNumber = "senderSequenceNumber"
            case senderThreadIdentifier = "senderThreadIdentifier"
            case message = "message"
        }
        static func with(senderIdentifier: Data, senderSequenceNumber: Int, senderThreadIdentifier: UUID, discussion: PersistedDiscussion) -> NSPredicate {
            let discussionKey = [Key.message.rawValue, PersistedMessage.Predicate.Key.discussion.rawValue].joined(separator: ".")
            return NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(Key.senderIdentifier, EqualToData: senderIdentifier),
                NSPredicate(Key.senderSequenceNumber, EqualToInt: senderSequenceNumber),
                NSPredicate(Key.senderThreadIdentifier, EqualToUuid: senderThreadIdentifier),
                NSPredicate(format: "%K == %@", discussionKey, discussion.objectID),
            ])
        }
        static func createBefore(_ date: Date) -> NSPredicate {
            NSPredicate(Key.creationDate, earlierThan: date)
        }
    }

    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PendingRepliedTo> {
        return NSFetchRequest<PendingRepliedTo>(entityName: PendingRepliedTo.entityName)
    }

    
    fileprivate static func getAll(senderIdentifier: Data, senderSequenceNumber: Int, senderThreadIdentifier: UUID, discussion: PersistedDiscussion, within context: NSManagedObjectContext) throws -> [PendingRepliedTo] {
        let request = PendingRepliedTo.fetchRequest()
        request.predicate = Predicate.with(senderIdentifier: senderIdentifier,
                                           senderSequenceNumber: senderSequenceNumber,
                                           senderThreadIdentifier: senderThreadIdentifier,
                                           discussion: discussion)
        request.fetchBatchSize = 1_000
        return try context.fetch(request)
    }
    
    
    static func batchDeleteEntriesOlderThan(_ date: Date, within context: NSManagedObjectContext) throws {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: PendingRepliedTo.entityName)
        fetchRequest.predicate = Predicate.createBefore(date)
        let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        batchDeleteRequest.resultType = .resultTypeStatusOnly
        _ = try context.execute(batchDeleteRequest)
    }
    
}