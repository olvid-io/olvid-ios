/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import ObvSettings


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
    @NSManaged private var unsortedFyleMessageJoinWithStatus: Set<ReceivedFyleMessageJoinWithStatus>


    // MARK: Other variables

    private var userInfoForDeletion: [String: Any]?
    private var changedKeys = Set<String>()

    public var objectPermanentID: ObvManagedObjectPermanentID<PersistedMessageReceived> {
        ObvManagedObjectPermanentID<PersistedMessageReceived>(uuid: self.permanentUUID)
    }

    public override var kind: PersistedMessageKind { .received }

    /// 2023-07-17: This is the most appropriate identifier to use in, e.g., notifications
    public override var identifier: MessageIdentifier {
        return .received(id: self.receivedMessageIdentifier)
    }
    
    public var receivedMessageIdentifier: ReceivedMessageIdentifier {
        return .objectID(objectID: self.objectID)
    }

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
            discussion?.resetNewReceivedMessageDoesMentionOwnedIdentityValue()
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


    // MARK: - Processing wipe requests
    
    /// Called when receiving a wipe request from a contact or another owned device. Shall only be called from ``PersistedDiscussion.processWipeMessageRequestForPersistedMessageReceived(among:from:messageUploadTimestampFromServer:)``.
    override func wipeThisMessage(requesterCryptoId: ObvCryptoId) throws {
        for join in fyleMessageJoinWithStatuses {
            try join.wipe()
        }
        try super.wipeThisMessage(requesterCryptoId: requesterCryptoId)
    }

    // MARK: - Updating a message

    func processUpdateReceivedMessageRequest(newTextBody: String?, newUserMentions: [MessageJSON.UserMention], messageUploadTimestampFromServer: Date, requester: ObvCryptoId) throws {
        guard self.contactIdentity?.cryptoId == requester else { throw Self.makeError(message: "The requester is not the contact who created the original message") }
        try super.processUpdateMessageRequest(newTextBody: newTextBody, newUserMentions: newUserMentions)
        try deleteMetadataOfKind(.edited)
        try addMetadata(kind: .edited, date: messageUploadTimestampFromServer)
    }
    
    
    // MARK: - Other methods

    public func updateMissedMessageCount(with missedMessageCount: Int) {
        guard self.missedMessageCount != missedMessageCount else { return }
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
    
    private convenience init(messageUploadTimestampFromServer: Date, downloadTimestampFromServer: Date, localDownloadTimestamp: Date, messageJSON: MessageJSON, contactIdentity: PersistedObvContactIdentity, messageIdentifierFromEngine: Data, returnReceiptJSON: ReturnReceiptJSON?, missedMessageCount: Int, discussion: PersistedDiscussion, obvMessageContainsAttachments: Bool) throws {
        
        // Disallow the creation of an "empty" message
        let messageBodyIsEmpty = (messageJSON.body == nil || messageJSON.body?.isEmpty == true)
        guard !messageBodyIsEmpty || obvMessageContainsAttachments else {
            assertionFailure()
            throw Self.makeError(message: "Trying to create an empty PersistedMessageReceived")
        }
        
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

        let replyTo: ReplyToType?
        if let replyToJSON = messageJSON.replyTo {
            replyTo = .json(replyToJSON: replyToJSON)
        } else {
            replyTo = nil
        }
        
        try self.init(timestamp: adjustedTimestamp,
                      body: messageJSON.body,
                      rawStatus: MessageStatus.new.rawValue,
                      senderSequenceNumber: messageJSON.senderSequenceNumber,
                      sortIndex: sortIndex,
                      replyTo: replyTo,
                      discussion: discussion,
                      readOnce: messageJSON.expiration?.readOnce ?? false,
                      visibilityDuration: messageJSON.expiration?.visibilityDuration,
                      forwarded: messageJSON.forwarded,
                      mentions: messageJSON.userMentions,
                      forEntityName: PersistedMessageReceived.entityName)

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
            self.expirationForReceivedLimitedExistence = PersistedExpirationForReceivedMessageWithLimitedExistence(
                messageReceivedWithLimitedExistence: self,
                existenceDuration: existenceDuration,
                messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                downloadTimestampFromServer: downloadTimestampFromServer,
                localDownloadTimestamp: localDownloadTimestamp)
        }
     
        // Now that this message is created, we can look for all the messages that have a `messageRepliedToIdentifier` referencing this message.
        // For these messages, we delete this reference and, instead, reference this message using the `messageRepliedTo` relationship.
        
        try self.updateMessagesReplyingToThisMessage()

    }
    
    
    /// This method shall be called exclusively from ``PersistedObvContactIdentity.createOrOverridePersistedMessageReceived(obvMessage:messageJSON:returnReceiptJSON:overridePreviousPersistedMessage:)`` or from ``static PersistedMessageReceived.createOrUpdatePersistedMessageReceived(obvMessage:messageJSON:returnReceiptJSON:from:in:)``.
    /// Returns all the `ObvAttachment` that are fully received, i.e., such that the `ReceivedFyleMessageJoinWithStatus` status is `.complete` and if the `Fyle` has a full file on disk.
    static func createPersistedMessageReceived(obvMessage: ObvMessage, messageJSON: MessageJSON, returnReceiptJSON: ReturnReceiptJSON?, from persistedContact: PersistedObvContactIdentity, in discussion: PersistedDiscussion) throws -> (createdMessage: PersistedMessageReceived, attachmentsFullyReceivedOrCancelledByServer: [ObvAttachment]) {
        
        guard try PersistedMessageReceived.get(messageIdentifierFromEngine: obvMessage.messageIdentifierFromEngine, from: persistedContact) == nil else {
            throw ObvError.persistedMessageReceivedAlreadyExist
        }
        
        guard persistedContact.managedObjectContext == discussion.managedObjectContext else {
            throw ObvError.distinctContexts
        }
        
        let missedMessageCount = updateNextMessageMissedMessageCountAndGetCurrentMissedMessageCount(
            discussion: discussion,
            contactIdentity: persistedContact,
            senderThreadIdentifier: messageJSON.senderThreadIdentifier,
            senderSequenceNumber: messageJSON.senderSequenceNumber)
        
        let discussionKind = try discussion.kind
        
        let messageUploadTimestampFromServer = PersistedMessage.determineMessageUploadTimestampFromServer(
            messageUploadTimestampFromServerInObvMessage: obvMessage.messageUploadTimestampFromServer,
            messageJSON: messageJSON,
            discussionKind: discussionKind)

        let message = try Self.init(
            messageUploadTimestampFromServer: messageUploadTimestampFromServer,
            downloadTimestampFromServer: obvMessage.downloadTimestampFromServer,
            localDownloadTimestamp: obvMessage.localDownloadTimestamp,
            messageJSON: messageJSON,
            contactIdentity: persistedContact,
            messageIdentifierFromEngine: obvMessage.messageIdentifierFromEngine,
            returnReceiptJSON: returnReceiptJSON,
            missedMessageCount: missedMessageCount,
            discussion: discussion,
            obvMessageContainsAttachments: !obvMessage.attachments.isEmpty)
        
        // Process the attachments within the message

        let attachmentsFullyReceivedOrCancelledByServer = message.processObvAttachments(of: obvMessage)
        
        return (message, attachmentsFullyReceivedOrCancelledByServer)
        
    }
    
    
    /// Returns all the `ObvAttachment` that are fully received, i.e., such that the `ReceivedFyleMessageJoinWithStatus` status is `.complete` and if the `Fyle` has a full file on disk.
    private func processObvAttachments(of obvMessage: ObvMessage) -> [ObvAttachment] {
        var attachmentsFullyReceivedOrCancelledByServer = [ObvAttachment]()
        for obvAttachment in obvMessage.attachments {
            do {
                let attachmentFullyReceivedOrCancelledByServer = try processObvAttachment(obvAttachment)
                if attachmentFullyReceivedOrCancelledByServer {
                    attachmentsFullyReceivedOrCancelledByServer.append(obvAttachment)
                }
            } catch {
                os_log("Could not process one of the message's attachments: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                // We continue anyway
            }
        }
        return attachmentsFullyReceivedOrCancelledByServer
    }
    
    
    /// Returns `true` if the attachment is fully received, i.e., if the `ReceivedFyleMessageJoinWithStatus` status is `.complete` and if the `Fyle` has a full file on disk.
    /// Also returns `true` if the attachment was cancelled by the server.
    func processObvAttachment(_ obvAttachment: ObvAttachment) throws -> Bool {
        
        guard let context = self.managedObjectContext else {
            throw ObvError.noContext
        }
        
        let attachmentFullyReceivedOrCancelledByServer = try ReceivedFyleMessageJoinWithStatus.createOrUpdateReceivedFyleMessageJoinWithStatus(with: obvAttachment, within: context)

        return attachmentFullyReceivedOrCancelledByServer
        
    }
    
    
    /// This method shall be called exclusively from ``PersistedObvContactIdentity.createOrOverridePersistedMessageReceived(obvMessage:messageJSON:returnReceiptJSON:overridePreviousPersistedMessage:)``.
    /// Returns all the `ObvAttachment` that are fully received, i.e., such that the `ReceivedFyleMessageJoinWithStatus` status is `.complete` and if the `Fyle` has a full file on disk.
    static func createOrUpdatePersistedMessageReceived(obvMessage: ObvMessage, messageJSON: MessageJSON, returnReceiptJSON: ReturnReceiptJSON?, from persistedContact: PersistedObvContactIdentity, in discussion: PersistedDiscussion) throws -> (createdOrUpdatedMessage: PersistedMessageReceived, attachmentsFullyReceived: [ObvAttachment]) {
        
        let attachmentsFullyReceivedOrCancelledByServer: [ObvAttachment]
        let createdOrUpdatedMessage: PersistedMessageReceived
        
        if let previousMessage = try PersistedMessageReceived.get(messageIdentifierFromEngine: obvMessage.messageIdentifierFromEngine, from: persistedContact) {
            
            os_log("Updating a previous received message...", log: log, type: .info)
            
            attachmentsFullyReceivedOrCancelledByServer = try previousMessage.updatePersistedMessageReceived(
                withMessageJSON: messageJSON,
                obvMessage: obvMessage,
                returnReceiptJSON: returnReceiptJSON,
                discussion: discussion)
            
            createdOrUpdatedMessage = previousMessage
            
        } else {

            os_log("Creating a persisted message...", log: log, type: .debug)

            (createdOrUpdatedMessage, attachmentsFullyReceivedOrCancelledByServer) = try PersistedMessageReceived.createPersistedMessageReceived(
                obvMessage: obvMessage,
                messageJSON: messageJSON,
                returnReceiptJSON: returnReceiptJSON,
                from: persistedContact,
                in: discussion)
            
        }
        
        return (createdOrUpdatedMessage, attachmentsFullyReceivedOrCancelledByServer)
        
    }

    
    /// Helper method for ``static PersistedMessageReceived.create(messageIdentifierFromEngine:persistedContact:)``.
    private static func updateNextMessageMissedMessageCountAndGetCurrentMissedMessageCount(discussion: PersistedDiscussion, contactIdentity: PersistedObvContactIdentity, senderThreadIdentifier: UUID, senderSequenceNumber: Int) -> Int {

        let latestDiscussionSenderSequenceNumber: PersistedLatestDiscussionSenderSequenceNumber?
        do {
            latestDiscussionSenderSequenceNumber = try PersistedLatestDiscussionSenderSequenceNumber.get(discussion: discussion, contactIdentity: contactIdentity, senderThreadIdentifier: senderThreadIdentifier)
        } catch {
            os_log("Could not get PersistedLatestDiscussionSenderSequenceNumber: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
            return 0
        }

        if let latestDiscussionSenderSequenceNumber = latestDiscussionSenderSequenceNumber {
            if senderSequenceNumber < latestDiscussionSenderSequenceNumber.latestSequenceNumber {
                guard let nextMessage = PersistedMessageReceived.getNextMessageBySenderSequenceNumber(senderSequenceNumber, senderThreadIdentifier: senderThreadIdentifier, contactIdentity: contactIdentity, within: discussion) else {
                    return 0
                }
                if nextMessage.missedMessageCount < nextMessage.senderSequenceNumber - senderSequenceNumber {
                    // The message is older than the number of messages missed in the following message --> nothing to do
                    return 0
                }
                let remainingMissedCount = nextMessage.missedMessageCount - (nextMessage.senderSequenceNumber - senderSequenceNumber)

                nextMessage.updateMissedMessageCount(with: nextMessage.senderSequenceNumber - senderSequenceNumber - 1)

                return remainingMissedCount
            } else if senderSequenceNumber > latestDiscussionSenderSequenceNumber.latestSequenceNumber {
                let missingCount = senderSequenceNumber - latestDiscussionSenderSequenceNumber.latestSequenceNumber - 1
                latestDiscussionSenderSequenceNumber.updateLatestSequenceNumber(with: senderSequenceNumber)
                return missingCount
            } else {
                // Unexpected: senderSequenceNumber == latestSequenceNumber (this should normally not happen...)
                return 0
            }
        } else {
            _ = PersistedLatestDiscussionSenderSequenceNumber(discussion: discussion,
                                                              contactIdentity: contactIdentity,
                                                              senderThreadIdentifier: senderThreadIdentifier,
                                                              latestSequenceNumber: senderSequenceNumber)
            return 0
        }
    }

    
    
    /// Returns all the `ObvAttachment` that are fully received, i.e., such that the `ReceivedFyleMessageJoinWithStatus` status is `.complete` and if the `Fyle` has a full file on disk.
    private func updatePersistedMessageReceived(withMessageJSON json: MessageJSON, obvMessage: ObvMessage, returnReceiptJSON: ReturnReceiptJSON?, discussion: PersistedDiscussion) throws -> [ObvAttachment] {
        
        guard self.messageIdentifierFromEngine == messageIdentifierFromEngine else {
            throw Self.makeError(message: "Invalid message identifier from engine")
        }
        
        guard !isWiped else {
            os_log("Trying to update a wiped received message. We don't do that an return immediately.", log: Self.log, type: .info)
            return obvMessage.attachments
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
            os_log("Could not encode a return receipt while create a persisted message received: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
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
                let discussionKind = try discussion.kind
                let messageUploadTimestampFromServer = Self.determineMessageUploadTimestampFromServer(
                    messageUploadTimestampFromServerInObvMessage: obvMessage.messageUploadTimestampFromServer,
                    messageJSON: json,
                    discussionKind: discussionKind)
                self.expirationForReceivedLimitedExistence = PersistedExpirationForReceivedMessageWithLimitedExistence(
                    messageReceivedWithLimitedExistence: self,
                    existenceDuration: expirationJson.existenceDuration!,
                    messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                    downloadTimestampFromServer: obvMessage.downloadTimestampFromServer,
                    localDownloadTimestamp: obvMessage.localDownloadTimestamp)
            }
        }
        
        // Process the attachments within the message

        let attachmentsFullyReceivedOrCancelledByServer = processObvAttachments(of: obvMessage)
        
        return attachmentsFullyReceivedOrCancelledByServer

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

    
    func userWantsToReadThisReceivedMessageWithLimitedVisibility(dateWhenMessageWasRead: Date, requestedOnAnotherOwnedDevice: Bool) throws -> InfoAboutWipedOrDeletedPersistedMessage? {
        assert(isEphemeralMessageWithUserAction)
        guard isEphemeralMessageWithUserAction else {
            assertionFailure("There is no reason why this is called on a message that is not marked as readOnce or with a certain visibility")
            return nil
        }
        if requestedOnAnotherOwnedDevice && self.readOnce {
            let infos = try self.deleteExpiredMessage()
            return infos
        } else {
            try self.markAsRead(dateWhenMessageWasRead: dateWhenMessageWasRead)
            return nil
        }
    }
    

    /// This allows to prevent auto-read for messages received with a more restrictive ephemerality than that of the discussion.
    public var ephemeralityIsAtLeastAsPermissiveThanDiscussionSharedConfiguration: Bool {
        if self.readOnce {
            guard let discussionSharedConfigurationReadOnce = self.discussion?.sharedConfiguration.readOnce else { assertionFailure(); return false }
            guard discussionSharedConfigurationReadOnce else { return false }
        }
        if let messageVisibilityDuration = self.visibilityDuration {
            guard let discussionVisibilityDuration = self.discussion?.sharedConfiguration.visibilityDuration else { return false }
            guard messageVisibilityDuration >= discussionVisibilityDuration else { return false }
        }
        if let messageExistenceDuration = self.initialExistenceDuration {
            guard let discussionExistenceDuration = self.discussion?.sharedConfiguration.existenceDuration else { return false }
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
        guard let discussion else { return false }
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
        } else if self.messageRepliedToIdentifierIsNonNil {
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

    func markAsNotNew(dateWhenMessageTurnedNotNew: Date) throws -> Date? {
        switch self.status {
        case .new:
            if isEphemeralMessageWithUserAction {
                self.status = .unread
            } else {
                try markAsRead(dateWhenMessageWasRead: dateWhenMessageTurnedNotNew)
            }
            return self.timestamp
        case .unread, .read:
            return nil
        }
    }
    
    
    private func markAsRead(dateWhenMessageWasRead: Date) throws {
        os_log("Call to markAsRead in PersistedMessageReceived for message %{public}@", log: PersistedMessageReceived.log, type: .debug, self.objectID.debugDescription)
        
        if self.status != .read {

            self.status = .read
            
            // When a received message is marked as "read", we check whether it has a limited visibility.
            // If this is the case, we immediately create an appropriate expiration for this message.
            
            if let visibilityDuration = self.visibilityDuration {
                assert(self.expirationForReceivedLimitedVisibility == nil)
                let visibilityDurationCorrection = max(0, Date().timeIntervalSince(dateWhenMessageWasRead))
                self.expirationForReceivedLimitedVisibility = PersistedExpirationForReceivedMessageWithLimitedVisibility(
                    messageReceivedWithLimitedVisibility: self,
                    visibilityDuration: max(0, visibilityDuration - visibilityDurationCorrection))
            }

            try self.addMetadata(kind: .read, date: dateWhenMessageWasRead)
            
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

    
    func toReceivedMessageReferenceJSON() -> MessageReferenceJSON {
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
        static func createdBeforeOrAt(date: Date) -> NSPredicate {
            NSPredicate(PersistedMessage.Predicate.Key.timestamp, earlierOrAt: date)
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
        static func withMessageWriterIdentifier(_ identifier:  MessageWriterIdentifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withContactIdentityIdentity(identifier.senderIdentifier),
                PersistedMessage.Predicate.withSenderSequenceNumberEqualTo(identifier.senderSequenceNumber),
                withSenderThreadIdentifier(identifier.senderThreadIdentifier),
            ])
        }
    }
    

    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedMessageReceived> {
        return NSFetchRequest<PersistedMessageReceived>(entityName: PersistedMessageReceived.entityName)
    }

    
    static func getPersistedMessageReceived(discussion: PersistedDiscussion, messageId: ReceivedMessageIdentifier) throws -> PersistedMessageReceived? {
        guard let context = discussion.managedObjectContext else { assertionFailure(); throw ObvError.noContext }
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        switch messageId {
        case .objectID(let objectID):
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.withObjectID(objectID),
                Predicate.withinDiscussion(discussion),
            ])
        case .authorIdentifier(let writerIdentifier):
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.withinDiscussion(discussion),
                Predicate.withMessageWriterIdentifier(writerIdentifier),
            ])
        }
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    
    public static func get(with objectID: TypeSafeManagedObjectID<PersistedMessageReceived>, within context: NSManagedObjectContext) throws -> PersistedMessageReceived? {
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = Predicate.withObjectID(objectID.objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    private static func getNextMessageBySenderSequenceNumber(_ sequenceNumber: Int, senderThreadIdentifier: UUID, contactIdentity: PersistedObvContactIdentity, within discussion: PersistedDiscussion) -> PersistedMessageReceived? {
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

    
    private static func getPreviousMessageBySenderSequenceNumber(_ sequenceNumber: Int, senderThreadIdentifier: UUID, contactIdentity: PersistedObvContactIdentity, within discussion: PersistedDiscussion) -> PersistedMessageReceived? {
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
    static func markAllAsNotNew(within discussion: PersistedDiscussion, dateWhenMessageTurnedNotNew: Date) throws -> Date? {
        os_log("Call to markAllAsNotNew in PersistedMessageReceived for discussion %{public}@", log: log, type: .debug, discussion.objectID.debugDescription)
        guard let context = discussion.managedObjectContext else { assertionFailure(); return nil }
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.includesSubentities = true
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            Predicate.isNew,
        ])
        let messages = try context.fetch(request)
        guard !messages.isEmpty else { return nil }
        try messages.forEach {
            _ = try $0.markAsNotNew(dateWhenMessageTurnedNotNew: dateWhenMessageTurnedNotNew)
        }
        return messages.map({ $0.timestamp }).max()
    }

    
    static func markAllAsNotNew(within discussion: PersistedDiscussion, untilDate: Date, dateWhenMessageTurnedNotNew: Date) throws -> Date? {
        os_log("Call to markAllAsNotNew in PersistedMessageReceived for discussion %{public}@", log: log, type: .debug, discussion.objectID.debugDescription)
        guard let context = discussion.managedObjectContext else { assertionFailure(); return nil }
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.includesSubentities = true
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.createdBeforeOrAt(date: untilDate),
            Predicate.withinDiscussion(discussion),
            Predicate.isNew,
        ])
        let messages = try context.fetch(request)
        guard !messages.isEmpty else { return nil }
        try messages.forEach {
            _ = try $0.markAsNotNew(dateWhenMessageTurnedNotNew: dateWhenMessageTurnedNotNew)
        }
        return messages.map({ $0.timestamp }).max()
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
    /// For now, this is used in the notification service, when we fail to decrypt a notification. In that case, we assume the message was received by the app first (which is the reason it could not be decrypted in the notification extension) and we create the notification
    /// by fetching the message from database.
    public static func getAll(messageIdentifierFromEngine: Data, within context: NSManagedObjectContext) throws -> [PersistedMessageReceived] {
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = Predicate.withMessageIdentifierFromEngine(messageIdentifierFromEngine)
        request.fetchBatchSize = 10
        return try context.fetch(request)
    }

    
    /// This method returns "all" the received messages with the given identifier from engine. In practice, we do not expect more than on message within the array.
    public static func getAll(ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data, within context: NSManagedObjectContext) throws -> [PersistedMessageReceived] {
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.forOwnedCryptoId(ownedCryptoId),
            Predicate.withMessageIdentifierFromEngine(messageIdentifierFromEngine),
        ])
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

    
    public static func get(messageIdentifierFromEngine: Data, from contact: ObvContactIdentifier, within context: NSManagedObjectContext) throws -> PersistedMessageReceived? {
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
    

    static func getAllReceivedMessagesThatRequireUserActionForReading(discussion: PersistedDiscussion) throws -> [PersistedMessageReceived] {
        guard let context = discussion.managedObjectContext else { assertionFailure(); throw ObvError.noContext }
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
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

}


@available(iOS 14, *)
extension PersistedMessageReceived {
    
    public var fyleMessageJoinWithStatusesOfImageType: [ReceivedFyleMessageJoinWithStatus] {
        fyleMessageJoinWithStatuses.filter({ Self.supportedImageTypeIdentifiers.contains($0.uti)  })
    }

    public var fyleMessageJoinWithStatusesOfAudioType: [ReceivedFyleMessageJoinWithStatus] {
        fyleMessageJoinWithStatuses.filter({ $0.contentType.conforms(to: .audio) })
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
        if let discussionObjectID = discussion?.typedObjectID, let ownedCryptoId = contactIdentity?.ownedIdentity?.cryptoId {
            userInfoForDeletion = ["objectID": objectID,
                                   "messageIdentifierFromEngine": messageIdentifierFromEngine,
                                   "ownedCryptoId": ownedCryptoId,
                                   "sortIndex": sortIndex,
                                   "discussionObjectID": discussionObjectID]
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


extension PersistedMessageReceived {
    
    public enum ObvError: LocalizedError {
        
        case noContext
        case persistedMessageReceivedAlreadyExist
        case distinctContexts
        case discussionIsNil
        
        public var errorDescription: String? {
            switch self {
            case .persistedMessageReceivedAlreadyExist:
                return "PersistedMessageReceived already exists"
            case .noContext:
                return "No context"
            case .distinctContexts:
                return "Distinct contexts"
            case .discussionIsNil:
                return "Discussion is nil"
            }
        }
        
    }
    
}

public extension TypeSafeManagedObjectID where T == PersistedMessageReceived {
    var downcast: TypeSafeManagedObjectID<PersistedMessage> {
        TypeSafeManagedObjectID<PersistedMessage>(objectID: objectID)
    }
}
