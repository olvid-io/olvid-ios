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
import MobileCoreServices

@objc(PersistedMessageSent)
public final class PersistedMessageSent: PersistedMessage, ObvIdentifiableManagedObject {
    
    public static let entityName = "PersistedMessageSent"
    private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "PersistedMessageSent")
    private static func makeError(message: String) -> Error { NSError(domain: String(describing: Self.self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    // MARK: Attributes

    @NSManaged private var rawExistenceDuration: NSNumber?

    // MARK: Relationships
    
    @NSManaged public private(set) var expirationForSentLimitedExistence: PersistedExpirationForSentMessageWithLimitedExistence?
    @NSManaged public private(set) var expirationForSentLimitedVisibility: PersistedExpirationForSentMessageWithLimitedVisibility?
    @NSManaged private var unsortedFyleMessageJoinWithStatuses: Set<SentFyleMessageJoinWithStatus>
    @NSManaged public private(set) var unsortedRecipientsInfos: Set<PersistedMessageSentRecipientInfos>

    // MARK: MessageStatus
    
    public enum MessageStatus: Int, Comparable, CaseIterable {
        case unprocessed = 0
        case processing = 1
        case sent = 2
        case delivered = 3
        case read = 4
        case couldNotBeSentToOneOrMoreRecipients = 5
        case hasNoRecipient = 6
        
        public static func < (lhs: PersistedMessageSent.MessageStatus, rhs: PersistedMessageSent.MessageStatus) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }

    }


    // MARK: Computed variables

    public var objectPermanentID: ObvManagedObjectPermanentID<PersistedMessageSent> {
        ObvManagedObjectPermanentID<PersistedMessageSent>(uuid: self.permanentUUID)
    }

    public override var kind: PersistedMessageKind { .sent }
    
    public var wasSentOrCouldNotBeSentToOneOrMoreRecipients: Bool {
        switch status {
        case .unprocessed, .processing:
            return false
        case .sent, .delivered, .read, .couldNotBeSentToOneOrMoreRecipients, .hasNoRecipient:
            return true
        }
    }
    
    public var status: MessageStatus {
        if let status = MessageStatus(rawValue: self.rawStatus) {
            return status
        } else {
            return .delivered
        }
    }
    
    
    private func setStatus(newValue: MessageStatus) {
        guard self.rawStatus != newValue.rawValue else { return }
        self.rawStatus = newValue.rawValue
        switch self.status {
        case .unprocessed:
            break
        case .processing:
            break
        case .sent, .couldNotBeSentToOneOrMoreRecipients, .hasNoRecipient, .delivered, .read:
            // When a sent message is marked as "sent", we check whether it has a limited visibility.
            // If this is the case, we immediately create an appropriate expiration for this message.
            if let visibilityDuration = self.visibilityDuration, self.expirationForSentLimitedVisibility == nil {
                self.expirationForSentLimitedVisibility = PersistedExpirationForSentMessageWithLimitedVisibility(
                    messageSentWithLimitedVisibility: self,
                    visibilityDuration: visibilityDuration,
                    retainWipedMessageSent: retainWipedOutboundMessages)
            }
            // When a sent message is marked as "sent", we check whether it has a limited existence.
            // If this is the case, we immediately create an appropriate expiration for this message.
            if let existenceDuration = self.existenceDuration, self.expirationForSentLimitedExistence == nil {
                self.expirationForSentLimitedExistence =  PersistedExpirationForSentMessageWithLimitedExistence(
                    messageSentWithLimitedExistence: self,
                    existenceDuration: existenceDuration)
            }

        }
    }
    
    
    var existenceDuration: TimeInterval? {
        get {
            guard let seconds = rawExistenceDuration?.intValue else { return nil }
            return TimeInterval(seconds)
        }
        set {
            self.rawExistenceDuration = (newValue == nil ? nil : NSNumber(value: newValue!) )
        }
    }

    
    /// This method is typically called each time a PersistedMessageSentRecipientInfos is updated.
    /// It loops through all infos and set the status to an appropriate status :
    /// - **unprocessed**: if no info has an identifier from the engine.
    /// - **processing**: if at least one info has an idenfier from the engine but cannot be marked as sent, delivered, nor read.
    /// - **sent**: If all infos that have an identifier from engine also are such that `messageAndAttachmentsAreSent` is `true` but cannot be marked as delivered nor read.
    /// - **delivered**: If all infos that have an identifier from engine also are such that `timestampDelivered` is not `nil` but cannot be marked as read.
    /// - **read**: If all infos that have an identifier from engine also are such that `timestampRead` is not `nil`.
    public func refreshStatus() {
        
        guard !unsortedRecipientsInfos.isEmpty else {
            // We created a sent message with no recipient. This happens when writing a message to self, i.e., at this time (2023-01-20), when sending a message in an empty groupV2.
            self.setStatus(newValue: .hasNoRecipient)
            unsortedFyleMessageJoinWithStatuses.forEach({ $0.markAsComplete() })
            return
        }
        
        let notDeletedUnsortedRecipientsInfos = unsortedRecipientsInfos.filter { !$0.isDeleted }
        
        let infosWithIdentifierFromEngine = notDeletedUnsortedRecipientsInfos
            .filter({ $0.messageIdentifierFromEngine != nil })

        guard !infosWithIdentifierFromEngine.isEmpty else {
            self.setStatus(newValue: .unprocessed)
            return
        }
        
        if infosWithIdentifierFromEngine.allSatisfy({ $0.timestampRead != nil }) {
            self.setStatus(newValue: .read)
        } else if infosWithIdentifierFromEngine.allSatisfy({ $0.timestampDelivered != nil }) {
            self.setStatus(newValue: .delivered)
        } else if infosWithIdentifierFromEngine.allSatisfy({ $0.messageAndAttachmentsAreSent }) {
            self.setStatus(newValue: .sent)
        } else if infosWithIdentifierFromEngine.first(where: { $0.couldNotBeSentToServer }) != nil {
            self.setStatus(newValue: .couldNotBeSentToOneOrMoreRecipients)
        } else {
            self.setStatus(newValue: .processing)
        }

    }
    

    public var fyleMessageJoinWithStatuses: [SentFyleMessageJoinWithStatus] {
        let nonWipedUnsortedFyleMessageJoinWithStatus = unsortedFyleMessageJoinWithStatuses.filter({ !$0.isWiped })
        switch nonWipedUnsortedFyleMessageJoinWithStatus.count {
        case 0:
            return []
        case 1:
            return [nonWipedUnsortedFyleMessageJoinWithStatus.first!]
        default:
            return nonWipedUnsortedFyleMessageJoinWithStatus.sorted(by: { $0.index < $1.index })
        }
    }

    private var changedKeys = Set<String>()

    public var isEphemeralMessage: Bool {
        readOnce || existenceDuration != nil || visibilityDuration != nil
    }

    public var isEphemeralMessageWithLimitedVisibility: Bool {
        self.readOnce || self.visibilityDuration != nil
    }

    
    /// `true` when this instance can be edited after being sent
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
    
    
    public override func replaceContentWith(newBody: String?, newMentions: Set<MessageJSON.UserMention>) throws {
        guard self.textBodyCanBeEdited else {
            throw Self.makeError(message: "The text body of this sent message cannot be edited now")
        }
        guard self.textBody != newBody else { return }
        try super.replaceContentWith(newBody: newBody, newMentions: newMentions)
        try deleteMetadataOfKind(.edited)
        try addMetadata(kind: .edited, date: Date())
    }
    

    override func toMessageReferenceJSON() -> MessageReferenceJSON? {
        return toSentMessageReferenceJSON()
    }

    public override var fyleMessageJoinWithStatus: [FyleMessageJoinWithStatus]? {
        fyleMessageJoinWithStatuses
    }

    override var messageIdentifiersFromEngine: Set<Data> {
        Set(unsortedRecipientsInfos.compactMap({ $0.messageIdentifierFromEngine }))
    }

    public override var genericRepliesTo: PersistedMessage.RepliedMessage {
        repliesTo.toRepliedMessage
    }
    
    
    public override var shouldBeDeleted: Bool {
        return super.shouldBeDeleted
    }

}


// MARK: - Reply-to

extension PersistedMessageSent {
    
    private enum RepliedMessageForMessageSent {
        case none
        case available(message: PersistedMessage)
        case deleted

        var toRepliedMessage: RepliedMessage {
            switch self {
            case .none: return .none
            case .available(let message): return .available(message: message)
            case .deleted: return .deleted
            }
        }
    }

    private var repliesTo: RepliedMessageForMessageSent {
        if let messageRepliedTo = self.rawMessageRepliedTo {
            return .available(message: messageRepliedTo)
        } else if self.isReplyToAnotherMessage {
            return .deleted
        } else {
            return .none
        }
    }
    
}


// MARK: - Initializer

extension PersistedMessageSent {

    public convenience init(body: String?, replyTo: PersistedMessage?, fyleJoins: [FyleJoin], discussion: PersistedDiscussion, readOnce: Bool, visibilityDuration: TimeInterval?, existenceDuration: TimeInterval?, forwarded: Bool, mentions: [MessageJSON.UserMention]) throws {
        guard let context = discussion.managedObjectContext else { assertionFailure(); throw PersistedMessageSent.makeError(message: "Could not find context") }

        // Sent messages can only be created when the discussion status is 'active'
        
        switch discussion.status {
        case .locked, .preDiscussion:
            throw Self.makeError(message: "Cannot create PersistedMessageSent, the discussion is not active")
        case .active:
            break
        }
        
        // To send a message in a group v2 discussion, we must be allowed to do so
        
        guard try discussion.ownedIdentityIsAllowedToSendMessagesInThisDiscussion else {
            throw Self.makeError(message: "The owned identity is not allowed to send messages in this discussion")
        }

        try? discussion.insertSystemMessagesIfDiscussionIsEmpty(markAsRead: true, messageTimestamp: Date())

        let timestamp = Date()

        let lastSortIndex = try PersistedMessage.getLargestSortIndex(in: discussion)
        let sortIndex = 1/100.0 + ceil(lastSortIndex) // We add "10 milliseconds"

        let readOnce = discussion.sharedConfiguration.readOnce || readOnce
        let visibilityDuration: TimeInterval? = TimeInterval.optionalMin(discussion.sharedConfiguration.visibilityDuration, visibilityDuration)
        let existenceDuration: TimeInterval? = TimeInterval.optionalMin(discussion.sharedConfiguration.existenceDuration, existenceDuration)
        let isReplyToAnotherMessage = replyTo != nil

        try self.init(timestamp: timestamp,
                      body: body,
                      rawStatus: MessageStatus.unprocessed.rawValue,
                      senderSequenceNumber: discussion.lastOutboundMessageSequenceNumber + 1,
                      sortIndex: sortIndex,
                      isReplyToAnotherMessage: isReplyToAnotherMessage,
                      replyTo: replyTo,
                      discussion: discussion,
                      readOnce: readOnce,
                      visibilityDuration: visibilityDuration,
                      forwarded: forwarded,
                      mentions: mentions,
                      forEntityName: PersistedMessageSent.entityName)

        self.existenceDuration = existenceDuration
        self.unsortedFyleMessageJoinWithStatuses = Set<SentFyleMessageJoinWithStatus>()
        fyleJoins.forEach {
            if let sentFyleMessageJoinWithStatuses = SentFyleMessageJoinWithStatus(fyleJoin: $0, persistedMessageSentObjectID: self.typedObjectID, within: context) {
                self.unsortedFyleMessageJoinWithStatuses.insert(sentFyleMessageJoinWithStatuses)
            } else {
                debugPrint("Could not create SentFyleMessageJoinWithStatus")
            }
        }

        // Create the recipient infos entries for the contact(s) that are part of the discussion
        
        self.unsortedRecipientsInfos = Set<PersistedMessageSentRecipientInfos>()
        
        switch try? discussion.kind {
            
        case .oneToOne(withContactIdentity: let contactIdentity):
            
            guard let contactIdentity = contactIdentity else {
                os_log("Could not find contact identity. This is ok if it has just been deleted.", log: log, type: .error)
                throw Self.makeError(message: "Could not find contact identity. This is ok if it has just been deleted.")
            }
            guard contactIdentity.isActive else {
                os_log("Trying to create PersistedMessageSentRecipientInfos for an inactive contact, which is not allowed.", log: log, type: .error)
                throw Self.makeError(message: "Trying to create PersistedMessageSentRecipientInfos for an inactive contact, which is not allowed.")
            }
            let recipientIdentity = contactIdentity.cryptoId.getIdentity()
            let infos = try PersistedMessageSentRecipientInfos(recipientIdentity: recipientIdentity,
                                                               messageSent: self)
            self.unsortedRecipientsInfos.insert(infos)
            
        case .groupV1(withContactGroup: let contactGroup):
            
            guard let contactGroup = contactGroup else {
                os_log("Could find contact group (this is ok if it was just deleted)", log: log, type: .error)
                throw Self.makeError(message: "Could find contact group (this is ok if it was just deleted)")
            }
            for recipient in contactGroup.contactIdentities {
                guard recipient.isActive else {
                    os_log("One of the group contacts is inactive. We do not create PersistedMessageSentRecipientInfos for this contact.", log: log, type: .error)
                    continue
                }
                let recipientIdentity = recipient.cryptoId.getIdentity()
                let infos = try PersistedMessageSentRecipientInfos(recipientIdentity: recipientIdentity, messageSent: self)
                self.unsortedRecipientsInfos.insert(infos)
            }
            guard !self.unsortedRecipientsInfos.isEmpty else {
                os_log("We created no recipient infos. This happens when all the contacts of a group are inactive. We do not create a PersistedMessageSent in this case", log: log, type: .error)
                throw Self.makeError(message: "We created no recipient infos. This happens when all the contacts of a group are inactive. We do not create a PersistedMessageSent in this case")
            }
            
        case .groupV2(withGroup: let group):
            
            guard let group = group else {
                os_log("Could find group v2 (this is ok if it was just deleted)", log: log, type: .error)
                throw Self.makeError(message: "Could find group v2 (this is ok if it was just deleted)")
            }
            for recipient in group.otherMembers {
                if let contact = recipient.contact {
                    guard contact.isActive else {
                        os_log("One of the group contacts is inactive. We do not create PersistedMessageSentRecipientInfos for this contact.", log: log, type: .error)
                        continue
                    }
                }
                let recipientIdentity = recipient.identity
                let infos = try PersistedMessageSentRecipientInfos(recipientIdentity: recipientIdentity, messageSent: self)
                self.unsortedRecipientsInfos.insert(infos)
            }
            
        case .none:
            throw Self.makeError(message: "Unexpected discussion type.")
        }

        discussion.lastOutboundMessageSequenceNumber = self.senderSequenceNumber

        refreshStatus()
    }


    public convenience init(draft: PersistedDraft) throws {
        try self.init(body: draft.body,
                      replyTo: draft.replyTo,
                      fyleJoins: draft.fyleJoins,
                      discussion: draft.discussion,
                      readOnce: draft.readOnce,
                      visibilityDuration: draft.visibilityDuration,
                      existenceDuration: draft.existenceDuration,
                      forwarded: false,
                      mentions: draft.mentions.compactMap({ try? $0.userMention }))
    }
    
}


// MARK: Setting delivered or read timestamps

extension PersistedMessageSent {
 
    /// When receiving a return receipt for a sent message, we expect the operation processing the receipt to call this method.
    public func messageSentWasDeliveredToRecipient(withCryptoId recipientCryptoId: ObvCryptoId, noLaterThan newTimestamp: Date, andRead: Bool) {
        let allInfos = unsortedRecipientsInfos.filter({ $0.recipientCryptoId == recipientCryptoId })
        assert(allInfos.count < 2, "Each recipient should have at most one recipient infos")
        guard let infos = allInfos.first else { assertionFailure("Each recipient should have at least one recipient infos"); return }
        infos.messageWasDeliveredNoLaterThan(newTimestamp, andRead: andRead)
        fyleMessageJoinWithStatuses.forEach { $0.markAsComplete() }
        refreshStatus()
    }

    
    /// When receiving a return receipt for a sent attachment, we expect the operation processing the receipt to call this method.
    public func attachmentSentWasDeliveredToRecipient(withCryptoId recipientCryptoId: ObvCryptoId, at newTimestamp: Date, deliveredAttachmentNumber: Int, andRead: Bool) {

        // For consistency, we also make sure the delivered timestamp of the message is set to an earlier date than the delivered timestamp of the attachment

        messageSentWasDeliveredToRecipient(withCryptoId: recipientCryptoId, noLaterThan: newTimestamp, andRead: false) // We do not assume that the message was read if the attachment was read

        // We update the recipient infos of the message as she received/read the attachment

        assert(unsortedRecipientsInfos.filter({ $0.recipientCryptoId == recipientCryptoId }).count == 1, "There should be exactly one recipient info per recipient")
        if let infos = unsortedRecipientsInfos.first(where: { $0.recipientCryptoId == recipientCryptoId }) {
            infos.messageAndAttachmentWereDeliveredNoLaterThan(newTimestamp, attachmentNumber: deliveredAttachmentNumber, andRead: andRead)
        }
                
        // We update the (global) reception status of the attachment as it might change since one of the recipients has a new reception status within the recipient infos

        assert(fyleMessageJoinWithStatuses.filter({ $0.index == deliveredAttachmentNumber }).count == 1, "There should be exactly one join for the given delivered attachment number")
        if let join = fyleMessageJoinWithStatuses.first(where: { $0.index == deliveredAttachmentNumber }) {

            // Collect all the attachment infos for all recipients of this attachment
            let allAttachmentInfos = unsortedRecipientsInfos.filter({ !$0.isDeleted }).map({ $0.attachmentInfos.first(where: { $0.index == deliveredAttachmentNumber }) })
            
            // Deduce all the attachment reception statuses for all recipients of this attachment
            let allReceptionStatuses = allAttachmentInfos.map({ $0?.status })
            
            // The (global) reception status of the attachment is set:
            // - to "read" if all the recipients did read the attachment
            // - otherwise to "delivered" if all the recipients did receive the attachment,
            // - otherwise to "none".
            let newReceptionStatus: SentFyleMessageJoinWithStatus.FyleReceptionStatus
            if allReceptionStatuses.allSatisfy({ $0 == .read }) {
                newReceptionStatus = .read
            } else if allReceptionStatuses.allSatisfy({ $0 == .read || $0 == .delivered }) {
                newReceptionStatus = .delivered
            } else {
                newReceptionStatus = .none
            }
            
            join.tryToSetReceptionStatusTo(newReceptionStatus)
            
        }
        
        refreshStatus()
    }
    
}


extension PersistedMessageSent {
    
    
    func toSentMessageReferenceJSON() -> MessageReferenceJSON? {
        guard let senderIdentifier = self.discussion.ownedIdentity?.cryptoId.getIdentity() else { return nil }
        return MessageReferenceJSON(senderSequenceNumber: self.senderSequenceNumber,
                                    senderThreadIdentifier: self.discussion.senderThreadIdentifier,
                                    senderIdentifier: senderIdentifier)
    }
    
    
    public func toJSON() -> MessageJSON? {
        
        let replyToJSON: MessageReferenceJSON?
        switch self.repliesTo {
        case .available(message: let replyTo):
            replyToJSON = replyTo.toMessageReferenceJSON()
        case .none, .deleted:
            replyToJSON = nil
        }

        switch try? discussion.kind {
            
        case .oneToOne, .none:

            return MessageJSON(senderSequenceNumber: self.senderSequenceNumber,
                               senderThreadIdentifier: self.discussion.senderThreadIdentifier,
                               body: self.textBodyToSend,
                               replyTo: replyToJSON,
                               expiration: self.expirationJSON,
                               forwarded: self.forwarded,
                               userMentions: mentions.compactMap({try? $0.userMention}))

        case .groupV1(withContactGroup: let contactGroup):
            guard let contactGroup = contactGroup else {
                os_log("Could find contact group (this is ok if it was just deleted)", log: log, type: .error)
                return nil
            }
            let groupUid = contactGroup.groupUid
            let groupOwner: ObvCryptoId
            if let groupJoined = contactGroup as? PersistedContactGroupJoined {
                guard let owner = groupJoined.owner else {
                    os_log("The owner is nil. This is ok if it was just deleted.", log: log, type: .error)
                    return nil
                }
                groupOwner = owner.cryptoId
            } else  if let groupOwned = contactGroup as? PersistedContactGroupOwned {
                guard let owner = groupOwned.owner else {
                    os_log("The owner is nil. This is ok if it was just deleted.", log: log, type: .error)
                    return nil
                }
                groupOwner = owner.cryptoId
            } else {
                return nil
            }
            let groupV1Identifier = (groupUid, groupOwner)
            
            return MessageJSON(senderSequenceNumber: self.senderSequenceNumber,
                               senderThreadIdentifier: self.discussion.senderThreadIdentifier,
                               body: self.textBodyToSend,
                               groupV1Identifier: groupV1Identifier,
                               replyTo: replyToJSON,
                               expiration: self.expirationJSON,
                               forwarded: self.forwarded,
                               userMentions: mentions.compactMap({try? $0.userMention}))

        case .groupV2(withGroup: let group):
            guard let group = group else {
                os_log("Could find group v2 (this is ok if it was just deleted)", log: log, type: .error)
                return nil
            }
            let groupV2Identifier = group.groupIdentifier
            
            let originalServerTimestamp = unsortedRecipientsInfos.compactMap({ $0.timestampMessageSent }).min()
            
            return MessageJSON(senderSequenceNumber: self.senderSequenceNumber,
                               senderThreadIdentifier: self.discussion.senderThreadIdentifier,
                               body: self.textBodyToSend,
                               groupV2Identifier: groupV2Identifier,
                               replyTo: replyToJSON,
                               expiration: self.expirationJSON,
                               forwarded: self.forwarded,
                               originalServerTimestamp: originalServerTimestamp,
                               userMentions: mentions.compactMap({try? $0.userMention}))

        }
        
    }
    
    
    /// Called when serializing a message before sending it
    private var expirationJSON: ExpirationJSON? {
        
        guard isEphemeralMessage else {
            return nil
        }

        // Special treatment for existence duration if there is one

        let existenceDurationToUseInExpirationJSON: TimeInterval?
        if let existenceDuration = existenceDuration {
            /* In case the message to be sent has a limited existence, we must consider two cases (only occurring for group v2):
             * - this is the first time we send this message
             * - the message has already been sent (e.g. to other members of the group), and we are sending it again as new group members joined.
             * In the first case, no problem, the existence duration to send is exactly the value found in self.existenceDuration. In the second case,
             * we must send the *remaining* existence duration. For example, if the original existence duration was 30 minutes but the contact took 5 minutes to accept
             * the group invitation, the existence that we must associate to the message is 25 minutes.
             * In order to determine if we are sending this message for the first time or not, we check whether expirationForSentLimitedExistence is nil or not.
             */
            if let expirationForSentLimitedExistence = self.expirationForSentLimitedExistence {
                existenceDurationToUseInExpirationJSON = max(0, expirationForSentLimitedExistence.expirationDate.timeIntervalSinceNow)
            } else {
                existenceDurationToUseInExpirationJSON = existenceDuration
            }
        } else {
            existenceDurationToUseInExpirationJSON = nil
        }
        
        return ExpirationJSON(readOnce: readOnce, visibilityDuration: visibilityDuration, existenceDuration: existenceDurationToUseInExpirationJSON)
        
    }
}


// MARK: - Determining actions availability

extension PersistedMessageSent {
    
    var copyActionCanBeMadeAvailableForSentMessage: Bool {
        return shareActionCanBeMadeAvailableForSentMessage
    }

    var shareActionCanBeMadeAvailableForSentMessage: Bool {
        return !readOnce
    }
    
    var forwardActionCanBeMadeAvailableForSentMessage: Bool {
        return shareActionCanBeMadeAvailableForSentMessage
    }

    var infoActionCanBeMadeAvailableForSentMessage: Bool {
        return !unsortedRecipientsInfos.isEmpty || !metadata.isEmpty
    }
    
    var replyToActionCanBeMadeAvailableForSentMessage: Bool {
        guard discussion.status == .active else { return false }
        if readOnce {
            return status == .read
        }
        return true
    }
    
    var editBodyActionCanBeMadeAvailableForSentMessage: Bool {
        return textBodyCanBeEdited
    }
    
    var deleteOwnReactionActionCanBeMadeAvailableForSentMessage: Bool {
        return reactions.contains { $0 is PersistedMessageReactionSent }
    }

}


// MARK: - Convenience DB getters

extension PersistedMessageSent {
        
    struct Predicate {
        enum Key: String {
            // Attributes
            case rawExistenceDuration = "rawExistenceDuration"
            // Relationships
            case expirationForSentLimitedExistence = "expirationForSentLimitedExistence"
            case expirationForSentLimitedVisibility = "expirationForSentLimitedVisibility"
            case unsortedFyleMessageJoinWithStatuses = "unsortedFyleMessageJoinWithStatuses"
            case unsortedRecipientsInfos = "unsortedRecipientsInfos"
            // Others
            static let expirationForSentLimitedVisibilityExpirationDate = [expirationForSentLimitedVisibility.rawValue, PersistedMessageExpiration.Predicate.Key.expirationDate.rawValue].joined(separator: ".")
            static let expirationForSentLimitedExistenceExpirationDate = [expirationForSentLimitedExistence.rawValue, PersistedMessageExpiration.Predicate.Key.expirationDate.rawValue].joined(separator: ".")
        }
        static var wasSent: NSPredicate {
            NSPredicate(PersistedMessage.Predicate.Key.rawStatus, largerThanOrEqualToInt: MessageStatus.sent.rawValue)
        }
        static var expiresForSentLimitedVisibility: NSPredicate {
            NSPredicate(withNonNilValueForKey: Key.expirationForSentLimitedVisibility)
        }
        static var expiresForSentLimitedExistence: NSPredicate {
            NSPredicate(withNonNilValueForKey: Key.expirationForSentLimitedExistence)
        }
        static func expiredBefore(_ date: Date) -> NSPredicate {
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    expiresForSentLimitedVisibility,
                    NSPredicate(Key.expirationForSentLimitedVisibilityExpirationDate, earlierThan: date),
                ]),
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    expiresForSentLimitedExistence,
                    NSPredicate(Key.expirationForSentLimitedExistenceExpirationDate, earlierThan: date),
                ]),
            ])
        }
        static func withinDiscussion(_ discussion: PersistedDiscussion) -> NSPredicate {
            PersistedMessage.Predicate.withinDiscussion(discussion)
        }
        static func withinDiscussionWithObjectID(_ discussionObjectID: NSManagedObjectID) -> NSPredicate {
            PersistedMessage.Predicate.withinDiscussionWithObjectID(discussionObjectID)
        }
        static func createdBefore(date: Date) -> NSPredicate {
            PersistedMessage.Predicate.createdBefore(date: date)
        }
        static func withLargerSortIndex(than message: PersistedMessage) -> NSPredicate {
            PersistedMessage.Predicate.withSortIndexLargerThan(message.sortIndex)
        }
        static func withStatus(_ status: MessageStatus) -> NSPredicate {
            NSPredicate(PersistedMessage.Predicate.Key.rawStatus, EqualToInt: status.rawValue)
        }
        static func withPermanentID(_ permanentID: ObvManagedObjectPermanentID<PersistedMessageSent>) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(withEntity: PersistedMessageSent.entity()),
                PersistedMessage.Predicate.withPermanentID(permanentID.downcast),
            ])
        }
    }

    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedMessageSent> {
        return NSFetchRequest<PersistedMessageSent>(entityName: PersistedMessageSent.entityName)
    }

    
    public static func getPersistedMessageSent(objectID: TypeSafeManagedObjectID<PersistedMessageSent>, within context: NSManagedObjectContext) throws -> PersistedMessageSent? {
        let request: NSFetchRequest<PersistedMessageSent> = PersistedMessageSent.fetchRequest()
        request.predicate = PersistedMessage.Predicate.withObjectID(objectID.objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    public static func getManagedObject(withPermanentID permanentID: ObvManagedObjectPermanentID<PersistedMessageSent>, within context: NSManagedObjectContext) throws -> PersistedMessageSent? {
        let request: NSFetchRequest<PersistedMessageSent> = PersistedMessageSent.fetchRequest()
        request.predicate = Predicate.withPermanentID(permanentID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    public static func getAllProcessingWithinDiscussion(persistedDiscussionObjectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> [PersistedMessageSent] {
        let request: NSFetchRequest<PersistedMessageSent> = PersistedMessageSent.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussionWithObjectID(persistedDiscussionObjectID),
            Predicate.withStatus(.processing),
        ])
        return try context.fetch(request)
    }
    
    
    public static func get(senderSequenceNumber: Int, senderThreadIdentifier: UUID, ownedIdentity: Data, discussion: PersistedDiscussion) throws -> PersistedMessageSent? {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Could not find context")}
        let request: NSFetchRequest<PersistedMessageSent> = PersistedMessageSent.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            PersistedMessage.Predicate.withSenderSequenceNumberEqualTo(senderSequenceNumber),
            PersistedMessage.Predicate.withSenderThreadIdentifier(senderThreadIdentifier),
            PersistedMessage.Predicate.withOwnedIdentityIdentity(ownedIdentity),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    /// Returns all `PersistedMessageSent` instances that expired before the given `date`, regardless of the owned identity or discussion.
    public static func getSentMessagesThatExpired(before date: Date, within context: NSManagedObjectContext) throws -> [PersistedMessageSent] {
        let request: NSFetchRequest<PersistedMessageSent> = PersistedMessageSent.fetchRequest()
        request.predicate = Predicate.expiredBefore(date)
        request.fetchBatchSize = 1_000
        return try context.fetch(request)
    }
    

    /// Fetches all outbound messages that are marked as `readOnce` and that have a status set to "sent".
    /// This is typically used to determine all sent messages to delete or wipe when exiting a discussion.
    public static func getReadOnceThatWasSent(restrictToDiscussionWithPermanentID discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>?, within context: NSManagedObjectContext) throws -> [PersistedMessageSent] {
        let request: NSFetchRequest<PersistedMessageSent> = PersistedMessageSent.fetchRequest()
        var predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            PersistedMessage.Predicate.readOnce,
            Predicate.wasSent,
        ])
        if let discussionPermanentID {
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                predicate,
                PersistedMessage.Predicate.withinDiscussionWithPermanentID(discussionPermanentID),
            ])
        }
        request.predicate = predicate
        request.fetchBatchSize = 1_000
        return try context.fetch(request)
    }
    
    
    /// Returns all outbound messages within the specified discussion, such that:
    /// - They are at least in the `sent` state
    /// - They were created before the specified date.
    /// This method is typically used for deleting messages that are older than the specified retention policy.
    public static func getAllSentMessagesCreatedBeforeDate(discussion: PersistedDiscussion, date: Date) throws -> [PersistedMessageSent] {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Cannot find context in PersistedDiscussion") }
        let request: NSFetchRequest<PersistedMessageSent> = PersistedMessageSent.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            Predicate.createdBefore(date: date),
            Predicate.wasSent,
        ])
        request.fetchBatchSize = 1_000
        return try context.fetch(request)
    }

    
    /// Returns `readOnce` and limited visibility messages with a timestamp less or equal to the specified date.
    /// As we expect these messages to be deleted, we only fetch a limited number of properties.
    /// This method should only be used to fetch messages that will eventually be deleted.
    public static func getAllReadOnceAndLimitedVisibilitySentMessagesToDelete(until date: Date, within context: NSManagedObjectContext) throws -> [PersistedMessageSent] {
        let request: NSFetchRequest<PersistedMessageSent> = PersistedMessageSent.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                PersistedMessage.Predicate.readOnce,
                Predicate.expiresForSentLimitedVisibility
            ]),
            PersistedMessage.Predicate.createdBeforeIncluded(date: date),
        ])
        request.relationshipKeyPathsForPrefetching = [PersistedMessage.Predicate.Key.discussion.rawValue] // The delete() method needs the discussion to return infos
        request.propertiesToFetch = [PersistedMessage.Predicate.Key.timestamp.rawValue] // The WipeAllEphemeralMessages operation needs the timestamp
        request.fetchBatchSize = 100 // Keep memory footprint low
        return try context.fetch(request)
    }

    
    public static func getDateOfLatestSentMessageWithLimitedVisibilityOrReadOnce(within context: NSManagedObjectContext) throws -> Date? {
        let request: NSFetchRequest<PersistedMessageSent> = PersistedMessageSent.fetchRequest()
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            PersistedMessage.Predicate.readOnce,
            Predicate.expiresForSentLimitedVisibility
        ])
        request.sortDescriptors = [NSSortDescriptor(key: PersistedMessage.Predicate.Key.timestamp.rawValue, ascending: false)]
        request.propertiesToFetch = [PersistedMessage.Predicate.Key.timestamp.rawValue]
        request.fetchLimit = 1
        let message = try context.fetch(request).first
        return message?.timestamp
    }

    
    /// This method returns the number of outbound messages within the specified discussion that are at least in the `sent` state.
    /// This method is typically used for later deleting messages so as to respect a count based retention policy.
    public static func countAllSentMessages(discussion: PersistedDiscussion) throws -> Int {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Cannot find context in PersistedDiscussion") }
        let request: NSFetchRequest<PersistedMessageSent> = PersistedMessageSent.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            Predicate.wasSent,
        ])
        return try context.count(for: request)
    }

}


@available(iOS 14, *)
extension PersistedMessageSent {

    public var fyleMessageJoinWithStatusesOfImageType: [SentFyleMessageJoinWithStatus] {
        fyleMessageJoinWithStatuses.filter({ Self.supportedImageTypeIdentifiers.contains($0.uti)  })
    }

    public var fyleMessageJoinWithStatusesOfAudioType: [SentFyleMessageJoinWithStatus] {
        fyleMessageJoinWithStatuses.filter({ ObvUTIUtils.uti($0.uti, conformsTo: kUTTypeAudio) })
    }

    public var fyleMessageJoinWithStatusesOfOtherTypes: [SentFyleMessageJoinWithStatus] {
        var result = fyleMessageJoinWithStatuses
        result.removeAll(where: { fyleMessageJoinWithStatusesOfImageType.contains($0)})
        result.removeAll(where: { fyleMessageJoinWithStatusesOfAudioType.contains($0)})
        return result
    }

}


// MARK: - Notifying on save


extension PersistedMessageSent {
    
    public override func willSave() {
        super.willSave()
        if isUpdated {
            changedKeys = Set<String>(self.changedValues().keys)
        }
    }

    
    public override func didSave() {
        super.didSave()
        defer { changedKeys.removeAll() }
        
        // When a readOnce message is sent, we notify. This is catched by the coordinator that checks whether the user is in the message's discussion or not. If this is the case, nothing happens. Otherwise the coordiantor deletes this readOnce message.
        if changedKeys.contains(PersistedMessage.Predicate.Key.rawStatus.rawValue) && self.status == .sent && self.readOnce {
            ObvMessengerCoreDataNotification.aReadOncePersistedMessageSentWasSent(persistedMessageSentPermanentID: self.objectPermanentID,
                                                                                  persistedDiscussionPermanentID: self.discussion.discussionPermanentID)
                .postOnDispatchQueue()
        }

    }
    
}

public extension TypeSafeManagedObjectID where T == PersistedMessageSent {
    var downcast: TypeSafeManagedObjectID<PersistedMessage> {
        TypeSafeManagedObjectID<PersistedMessage>(objectID: objectID)
    }
}