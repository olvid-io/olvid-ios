/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import OSLog
import ObvEngine
import ObvTypes
import MobileCoreServices
import ObvSettings
import ObvUICoreDataStructs
import ObvAppTypes


/// A message sent by an owned identity.
///
/// *About the `senderThreadIdentifier`*
///
/// In general, the `senderThreadIdentifier` is identical to the one found in the `PersistedDiscussion` and is the thread identifier of the owned identity in that discussion.
/// It differs when the `PersistedMessageSent` was actually sent from another device, in which case, the `senderThreadIdentifier` found here corresponds to the `senderThreadIdentifier` found in the `PersistedDiscussion` of the other owned device.
/// This is the case since, for a given discussion, the same owned identity has distinct `senderThreadIdentifier` on each of her owned devices.
@objc(PersistedMessageSent)
public final class PersistedMessageSent: PersistedMessage, ObvIdentifiableManagedObject {
    
    public static let entityName = "PersistedMessageSent"
    private static let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "PersistedMessageSent")
    private static let logger = Logger(subsystem: ObvUICoreDataConstants.logSubsystem, category: "PersistedMessageSent")

    // MARK: Attributes

    @NSManaged private(set) var messageIdentifierFromEngine: Data? // Only set for message sent from another device, always nil for messages sent from this device
    @NSManaged private var rawExistenceDuration: NSNumber?
    @NSManaged private(set) var senderThreadIdentifier: UUID

    // MARK: Relationships
    
    @NSManaged public private(set) var expirationForSentLimitedExistence: PersistedExpirationForSentMessageWithLimitedExistence?
    @NSManaged public private(set) var expirationForSentLimitedVisibility: PersistedExpirationForSentMessageWithLimitedVisibility?
    @NSManaged public private(set) var locationContinuousSent: PersistedLocationContinuousSent?
    @NSManaged public private(set) var locationOneShotSent: PersistedLocationOneShotSent?
    @NSManaged private var unsortedFyleMessageJoinWithStatuses: Set<SentFyleMessageJoinWithStatus>
    @NSManaged public private(set) var unsortedRecipientsInfos: Set<PersistedMessageSentRecipientInfos>

    // MARK: Computed variables

    /// Expected to be non-nil, unless this `NSManagedObject` is deleted.
    public var objectPermanentID: MessageSentPermanentID {
        get throws {
            guard self.managedObjectContext != nil else {
                // This happens if the object was created then deleted, which happens, e.g., when receiving a
                // message sent from another owned device for which we have a remote deleted request
                throw ObvUICoreDataError.noContext
            }
            return MessageSentPermanentID(uuid: self.permanentUUID)
        }
    }

    public override var kind: PersistedMessageKind { .sent }
    
    public var wasSentOrCouldNotBeSentToOneOrMoreRecipients: Bool {
        switch status {
        case .unprocessed, .processing:
            return false
        case .sentFromAnotherOwnedDevice,
                .hasNoRecipient,
                .couldNotBeSentToOneOrMoreRecipients,
                .fullyDeliveredAndFullyRead,
                .fullyDeliveredAndPartiallyRead,
                .fullyDeliveredAndNotRead,
                .partiallyDeliveredAndPartiallyRead,
                .partiallyDeliveredNotRead,
                .sent:
            return true
        }
    }
    
    public var status: MessageStatus {
        if let status = MessageStatus(rawValue: self.rawStatus) {
            return status
        } else {
            assertionFailure()
            return .fullyDeliveredAndNotRead
        }
    }
    
    
    func setStatusOnApplyingHintOnPersistedMessageSentRecipientInfos(newStatus: MessageStatus) {
        self.setStatus(newValue: newStatus)
    }
    
    
    private func setStatus(newValue: MessageStatus) {
        
        guard self.rawStatus != newValue.rawValue else { return }
        
        // If the message was sent from another device, we never update it
        guard self.status != .sentFromAnotherOwnedDevice else {
            assertionFailure("We should not be trying to update the status of a message sent from another owned device")
            return
        }
        
        self.rawStatus = newValue.rawValue
        switch self.status {
        case .unprocessed, .processing:
            break
        case .sentFromAnotherOwnedDevice,
                .hasNoRecipient,
                .couldNotBeSentToOneOrMoreRecipients,
                .fullyDeliveredAndFullyRead,
                .fullyDeliveredAndPartiallyRead,
                .fullyDeliveredAndNotRead,
                .partiallyDeliveredAndPartiallyRead,
                .partiallyDeliveredNotRead,
                .sent:
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

    /// Called when the owned identity requests a location edition from the current device
//    override func replaceContentWith(newLocation: ObvLocation?) throws {
//        guard !self.isLocallyWiped && !self.isRemoteWiped else {
//            throw ObvUICoreDataError.theTextBodyOfThisPersistedMessageSentCannotBeEditedNow
//        }
//        try super.replaceContentWith(newLocation: newLocation)
//        try deleteMetadataOfKind(.edited)
//        try addMetadata(kind: .edited, date: Date())
//    }
    
    /// Called when the owned identity requests a message edition from the current device
    override func replaceContentWith(newBody: String?, newMentions: Set<MessageJSON.UserMention>) throws {
        guard !self.isLocallyWiped && !self.isRemoteWiped else {
            throw ObvUICoreDataError.theTextBodyOfThisPersistedMessageSentCannotBeEditedNow
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
        repliesTo
    }
    
    
    public override var shouldBeDeleted: Bool {
        return super.shouldBeDeleted
    }

    public var hasMoreThanOneRecipient: Bool {
        unsortedRecipientsInfos.filter({ !$0.isDeleted }).count > 1
    }

    // MARK: - MessageStatus
    
    /// Enumerates the possible values of the status of a sent message.
    ///
    /// We use the following notations:
    /// - `N` is the number of "Recipient infos"
    /// - `n` is the number of "Recipient infos" with a non-nil message identifier from engine.
    /// - `f` is the number of "Recipient infos" for which we failed to send the message
    /// - `Ts` is number of those infos for which messageAndAttachmentsAreSent is True (i.e., non-nil sent timestamps for the message and all its attachments)
    /// - `Td` is number of those infos that have a non-nil "delivered" timestamp
    /// - `Tr` is number of those infos that have a non-nil "read" timestamp
    ///
    /// We ensure that `0 <= Tr <= Td <= Ts <= N <= n`: when setting a timestamp, we also set the "lower" timestamps if they are nil. As a consequence, we also "reset" a timestamp when receiving a new lower value.
    public enum MessageStatus: Int, CaseIterable {
        case sentFromAnotherOwnedDevice = 7             // Always set at creation of the message, never refreshed.
        case hasNoRecipient = 6                         // If N == 0
        case couldNotBeSentToOneOrMoreRecipients = 5    // If N > 0 and f > 0
        case fullyDeliveredAndFullyRead = 4             // If N > 0 and f = 0 and n == N and Ts == n and Td == N    and Tr == N
        case fullyDeliveredAndPartiallyRead = 8         // If N > 0 and f = 0 and n == N and Ts == n and Td == N    and 0 < Tr < N (does not make sense in a o2o discussion)
        case fullyDeliveredAndNotRead = 3               // If N > 0 and f = 0 and n == N and Ts == n and Td == N    and Tr == 0
        case partiallyDeliveredAndPartiallyRead = 9     // If N > 0 and f = 0 and n > 0  and Ts == n and 0 < Td < N and 0 < Tr < N (does not make sense in a o2o discussion)
        case partiallyDeliveredNotRead = 10             // If N > 0 and f = 0 and n > 0  and Ts == n and 0 < Td < N and Tr == 0    (does not make sense in a o2o discussion)
        case sent = 2                                   // If N > 0 and f = 0 and n > 0  and Ts == n and Td == 0    and Tr == 0
        case processing = 1                             // If N > 0 and f = 0 and n > 0  and none of the above case applies
        case unprocessed = 0                            // If N > 0 and f = 0 and n == 0 and none of the above case applies
        
        var debugDescription: String {
            switch self {
            case .sentFromAnotherOwnedDevice: return "sentFromAnotherOwnedDevice"
            case .hasNoRecipient: return "hasNoRecipient"
            case .couldNotBeSentToOneOrMoreRecipients: return "couldNotBeSentToOneOrMoreRecipients"
            case .fullyDeliveredAndFullyRead: return "fullyDeliveredAndFullyRead"
            case .fullyDeliveredAndPartiallyRead: return "fullyDeliveredAndPartiallyRead"
            case .fullyDeliveredAndNotRead: return "fullyDeliveredAndNotRead"
            case .partiallyDeliveredAndPartiallyRead: return "partiallyDeliveredAndPartiallyRead"
            case .partiallyDeliveredNotRead: return "partiallyDeliveredNotRead"
            case .sent: return "sent"
            case .processing: return "processing"
            case .unprocessed: return "unprocessed"
            }
        }
        
    }

    
    func markAllFyleMessageJoinWithStatusesAsComplete() -> Set<SentFyleMessageJoinWithStatus> {
        unsortedFyleMessageJoinWithStatuses.forEach({ $0.markAsComplete() })
        return self.unsortedFyleMessageJoinWithStatuses
    }
    

    /// This method is typically called each time a PersistedMessageSentRecipientInfos is updated, in order to update this message status accordingly.
    ///
    /// It loops through all infos and set the status to an appropriate status of the message, which is fully determined by the values of `n`, `N`, `f`, `Ts`, `Td`, and `Tr` as defined in ``enum MessageStatus``.
    public func refreshStatus() {
        
        // We first rule out three of the statuses: sentFromAnotherOwnedDevice, hasNoRecipient, and couldNotBeSentToOneOrMoreRecipients
        
        guard self.status != .sentFromAnotherOwnedDevice else {
            assertionFailure("We should not be trying to refresh the status of a message sent from another device")
            return
        }
        
        let infos = unsortedRecipientsInfos.filter { !$0.isDeleted }

        guard !infos.isEmpty else {
            // We created a sent message with no recipient. This happens when writing a message to self, i.e., at this time (2023-01-20), when sending a message in an empty groupV2.
            self.setStatus(newValue: .hasNoRecipient)
            _ = markAllFyleMessageJoinWithStatusesAsComplete()
            return
        }
        
        guard !infos.contains(where: { $0.couldNotBeSentToServer }) else {
            self.setStatus(newValue: .couldNotBeSentToOneOrMoreRecipients)
            return
        }
        
        // Now that we ruled out the first three statuses, we compute a few things that will allow to determine the correct status
                
        let N = infos.count
        let n = infos.filter({ $0.messageIdentifierFromEngine != nil }).count
        let ts = infos.filter({ $0.messageAndAttachmentsAreSent }).count
        let td = infos.filter({ $0.timestampDelivered != nil }).count
        let tr = infos.filter({ $0.timestampRead != nil }).count
        
        assert(tr <= td, "When setting a read timestamp, we should be setting the delivered timestamp if nil. So this should not happen")
        assert(td <= ts, "When setting a delivered timestamp, we should be setting the sent timestamp if nil. So this should not happen")
        assert(ts <= n, "This should not happen as all sent messages should have an identifier from engine")
        
        if n == 0 {
            self.setStatus(newValue: .unprocessed)
        } else if ts < n {
            self.setStatus(newValue: .processing)
        } else if n == N && td == N && tr == N {
            self.setStatus(newValue: .fullyDeliveredAndFullyRead)
        } else if n == N && td == N && tr > 0 {
            self.setStatus(newValue: .fullyDeliveredAndPartiallyRead)
        } else if n == N && td == N && tr == 0 {
            self.setStatus(newValue: .fullyDeliveredAndNotRead)
        } else if td > 0 && td < N && tr > 0 && tr < N {
            self.setStatus(newValue: .partiallyDeliveredAndPartiallyRead)
        } else if td > 0 && td < N && tr == 0 {
            self.setStatus(newValue: .partiallyDeliveredNotRead)
        } else {
            self.setStatus(newValue: .sent)
        }

        Self.logger.debug("🐇 N = \(N), n = \(n), ts = \(ts), td = \(td), tr = \(tr) | status = \(self.status.debugDescription)")

    }
    

    // MARK: - Processing wipe requests

    /// Called when receiving a wipe request from a contact or another owned device. Shall only be called from ``PersistedDiscussion.processWipeMessageRequestForPersistedMessageSent(among:from:messageUploadTimestampFromServer:)``.
    override func wipeThisMessage(requesterCryptoId: ObvCryptoId) throws -> InfoAboutWipedOrDeletedPersistedMessage {
        for join in fyleMessageJoinWithStatuses {
            try join.wipe()
        }
        let info = try super.wipeThisMessage(requesterCryptoId: requesterCryptoId)
        return info
    }

    
    // MARK: - Updating a message

    /// Called when receiving a remote request from another owned device
    func processUpdateSentMessageRequest(newTextBody: String?, newUserMentions: [MessageJSON.UserMention], newLocation: LocationJSON?, messageUploadTimestampFromServer: Date, requester: ObvCryptoId) throws {
        guard let discussion else { throw ObvUICoreDataError.discussionIsNil }
        guard discussion.ownedIdentity?.cryptoId == requester else { assertionFailure(); throw ObvUICoreDataError.theRequesterIsNotTheOwnedIdentityWhoCreatedThePersistedMessageSent }
        guard !self.isLocallyWiped && !self.isRemoteWiped else {
            throw ObvUICoreDataError.theTextBodyOfThisPersistedMessageSentCannotBeEditedNow
        }
        
        if let newLocation, self.isLocationMessage {
            switch newLocation.type {
            case .SEND:
                if let locationOneShotSent = self.locationOneShotSent {
                    try locationOneShotSent.updateContentForOneShotLocation(with: newLocation.locationData)
                }
            case .SHARING:
                if let locationContinuousSent = self.locationContinuousSent {
                    try locationContinuousSent.updateContentForContinuousLocation(with: newLocation.locationData, count: newLocation.count ?? 0)
                }
            case .END_SHARING:
                if let locationContinuousSent = self.locationContinuousSent {
                    try locationContinuousSent.sentLocationNoLongerNeeded(by: self)
                }
            }
        }
        
        try super.processUpdateMessageRequest(newTextBody: newTextBody, newUserMentions: newUserMentions)
        try deleteMetadataOfKind(.edited)
        try addMetadata(kind: .edited, date: messageUploadTimestampFromServer)
    }


    // MARK: - Observers
    
    private static var observersHolder = PersistedMessageSentObserversHolder()
    
    public static func addObserver(_ newObserver: PersistedMessageSentObserver) async {
        await observersHolder.addObserver(newObserver)
    }

}

// MARK: - Sending an update

extension PersistedMessageSent {
    
    public func toUpdateMessageJSONToSend() throws -> UpdateMessageJSONToSend {
        
        // Find all the contacts to which this item should be sent.
        
        guard let discussion = self.discussion else {
            assertionFailure()
            throw ObvUICoreDataError.couldNotFindDiscussion
        }
        
        let (ownedCryptoId, contactCryptoIds) = try discussion.getAllActiveParticipants()
        
        // Determine if the owned identity has other owned devices
        
        let hasAnotherDeviceWhichIsReachable: Bool
        do {
            guard let ownedIdentity = discussion.ownedIdentity else {
                assertionFailure()
                throw ObvUICoreDataError.ownedIdentityIsNil
            }
            hasAnotherDeviceWhichIsReachable = ownedIdentity.hasAnotherDeviceWhichIsReachable
        }

        // Create the UpdateMessageJSON
        
        let updateMessageJSON = try self.toUpdateMessageJSON()

        let updateMessageJSONToSend = UpdateMessageJSONToSend(ownedCryptoId: ownedCryptoId,
                                                              contactCryptoIds: contactCryptoIds,
                                                              updateMessageJSON: updateMessageJSON,
                                                              hasAnotherDeviceWhichIsReachable: hasAnotherDeviceWhichIsReachable)
        
        return updateMessageJSONToSend
        
    }
    
    
    private func toUpdateMessageJSON() throws -> UpdateMessageJSON {
        
        let newTextBody: String?
        let userMentions: [MessageJSON.UserMention]
        if let textBodyToSend = self.textBodyToSend {
            newTextBody = textBodyToSend.isEmpty ? nil : textBodyToSend
            userMentions = self
                .mentions
                .compactMap({ try? $0.userMention })
        } else {
            newTextBody = nil
            userMentions = []
        }
        
        let locationJSON = try self.toLocationJSON()
        
        return try UpdateMessageJSON(persistedMessageSentToEdit: self,
                                     newTextBody: newTextBody,
                                     userMentions: userMentions,
                                     locationJSON: locationJSON)
    }
    
    
    private func toLocationJSON() throws -> LocationJSON? {
        if let locationOneShotSent, locationOneShotSent.isDeleted {
            return try locationOneShotSent.toLocationJSON()
        } else if let locationContinuousSent, !locationContinuousSent.isDeleted {
            return try locationContinuousSent.toLocationJSON()
        } else if isLocation {
            return LocationJSON(type: .END_SHARING,
                                timestamp: Date.now,
                                count: nil,
                                quality: nil,
                                sharingExpiration: nil,
                                latitude: 0,
                                longitude: 0,
                                altitude: nil,
                                precision: nil,
                                address: nil)
        } else {
            return nil
        }
    }
    
}


// MARK: - Reply-to

extension PersistedMessageSent {
    
    private var repliesTo: RepliedMessage {
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


// MARK: - Initializer

extension PersistedMessageSent {
    

    /// Allows to check whether a `PersistedMessageSent` is allowed to be created within the specified discussion. This method throws if this is not the case.
    ///
    /// This method is called early in the initializer of `PersistedMessageSent`. Is is also used to determine if the replyTo action can be made available on a specific message (a check that happens
    /// on the main thread, reason why this method must be efficient).
    public static func isCreationAllowed(inDiscussion discussion: PersistedDiscussion) throws {
        
        // Sent messages can only be created when the discussion status is 'active'
        
        switch discussion.status {
        case .locked, .preDiscussion:
            throw ObvUICoreDataError.cannotCreatePersistedMessageSentAsDiscussionIsNotActive
        case .active:
            break
        }
        
        // To send a message in a group v2 discussion, we must be allowed to do so
        
        guard try discussion.ownedIdentityIsAllowedToSendMessagesInThisDiscussion else {
            throw ObvUICoreDataError.ownedIdentityIsAllowedToSendMessagesInThisDiscussion
        }

    }
    
    private convenience init(body: String?, replyTo: ReplyToType?, fyleJoins: [FyleJoin], discussion: PersistedDiscussion, readOnce: Bool, visibilityDuration: TimeInterval?, existenceDuration: TimeInterval?, forwarded: Bool, mentions: [MessageJSON.UserMention], location: SentLocation?, timestamp: Date, messageIdentifierFromEngine: Data?, infosFromOtherOwnedDevice: (senderThreadIdentifier: UUID, messageSequenceNumber: Int)?) throws {

        guard let context = discussion.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }

        // Make sure that we are allowed to create a PersistedMessageSent in the given discussion
        try Self.isCreationAllowed(inDiscussion: discussion)

        try? discussion.insertSystemMessagesIfDiscussionIsEmpty(markAsRead: true, messageTimestamp: timestamp.addingTimeInterval(-1/100.0)) // We remove 10 milliseconds

        let sortIndex: Double
        let adjustedTimestamp: Date
        if let (senderThreadIdentifier, messageSequenceNumber) = infosFromOtherOwnedDevice {
            (sortIndex, adjustedTimestamp) = try Self.determineAppropriateSortIndexForMessageReceivedFromOtherOwnedDevice(forSenderSequenceNumber: messageSequenceNumber, senderThreadIdentifier: senderThreadIdentifier, timestamp: timestamp, within: discussion)
            
        } else {
            let lastSortIndex = try PersistedMessage.getLargestSortIndex(in: discussion)
            sortIndex = 1/100.0 + ceil(lastSortIndex) // We add "10 milliseconds"
            adjustedTimestamp = timestamp
        }

        let readOnce = discussion.sharedConfiguration.readOnce || readOnce
        let visibilityDuration: TimeInterval? = TimeInterval.optionalMin(discussion.sharedConfiguration.visibilityDuration, visibilityDuration)
        let existenceDuration: TimeInterval? = TimeInterval.optionalMin(discussion.sharedConfiguration.existenceDuration, existenceDuration)

        // `infosFromOtherOwnedDevice` is `nil` iff the message was sent from the current device. Otherwise, it contains informations about the senderThreadIdentifier and the messageSequenceNumber on the other remote device.
        // Thus, if set, we use the values found in these infos in order to set the values of the `senderThreadIdentifier` and the `senderSequenceNumber` for this message.
        // If not, we use the values found in the discussion.
        
        let senderSequenceNumberForThisMessage: Int
        let senderThreadIdentifierForThisMessage: UUID
        if let infosFromOtherOwnedDevice {
            senderSequenceNumberForThisMessage = infosFromOtherOwnedDevice.messageSequenceNumber
            senderThreadIdentifierForThisMessage = infosFromOtherOwnedDevice.senderThreadIdentifier
        } else {            
            senderSequenceNumberForThisMessage = discussion.incrementLastOutboundMessageSequenceNumber()
            senderThreadIdentifierForThisMessage = discussion.senderThreadIdentifier
        }
        
        let locationContinuousSent: PersistedLocationContinuousSent?
        let locationOneShotSent: PersistedLocationOneShotSent?
        let locationBody: String?
        var locationToRemoveMessage: PersistedLocationContinuousSent?
        if let sentLocation = location {
            switch sentLocation {
            case .continuous(location: let objectID, toStop: let endSharingDestination):
                let persistedLocationContinuousSent = try PersistedLocationContinuousSent.getPersistedLocationContinuousSent(objectID: objectID, within: context)
                
                if let discussionIdentifier = try? discussion.discussionIdentifier, endSharingDestination == .all || discussionIdentifier == endSharingDestination?.discussionIdentifier {
                    locationContinuousSent = nil
                    locationOneShotSent = nil
                    locationToRemoveMessage = persistedLocationContinuousSent
                    locationBody = persistedLocationContinuousSent?.legacyLocationMessageBody
                } else {
                    locationContinuousSent = persistedLocationContinuousSent
                    locationOneShotSent = nil
                    locationBody = locationContinuousSent?.legacyLocationMessageBody
                }
            case .oneShot(location: let objectID):
                locationOneShotSent = try PersistedLocationOneShotSent.getPersistedLocationOneShotSent(objectID: objectID, within: context)
                locationContinuousSent = nil
                locationBody = locationOneShotSent?.legacyLocationMessageBody
            }
        } else {
            locationBody = nil
            locationContinuousSent = nil
            locationOneShotSent = nil
        }
                
        try self.init(timestamp: adjustedTimestamp,
                      body: body ?? locationBody,
                      rawStatus: MessageStatus.unprocessed.rawValue,
                      senderSequenceNumber: senderSequenceNumberForThisMessage,
                      sortIndex: sortIndex,
                      replyTo: replyTo,
                      discussion: discussion,
                      readOnce: readOnce,
                      visibilityDuration: visibilityDuration,
                      forwarded: forwarded,
                      mentions: mentions,
                      isLocation: location != nil,
                      forEntityName: PersistedMessageSent.entityName)

        self.locationContinuousSent = locationContinuousSent
        self.locationOneShotSent = locationOneShotSent
        if let location = locationToRemoveMessage {
            try location.sentLocationNoLongerNeeded(by: self)
        }
        
        self.senderThreadIdentifier = senderThreadIdentifierForThisMessage
        self.existenceDuration = existenceDuration
        self.unsortedFyleMessageJoinWithStatuses = Set<SentFyleMessageJoinWithStatus>()
        self.messageIdentifierFromEngine = messageIdentifierFromEngine // Non-nil iff the message was sent from another owned device
        fyleJoins.forEach {
            if let sentFyleMessageJoinWithStatuses = try? SentFyleMessageJoinWithStatus(fyleJoin: $0, persistedMessageSentObjectID: self.typedObjectID, within: context) {
                self.unsortedFyleMessageJoinWithStatuses.insert(sentFyleMessageJoinWithStatuses)
            } else {
                debugPrint("Could not create SentFyleMessageJoinWithStatus")
            }
        }

        // If the message was sent from this device, create the recipient infos entries for the contact(s) that are part of the discussion
        
        if infosFromOtherOwnedDevice == nil {
            
            self.unsortedRecipientsInfos = Set<PersistedMessageSentRecipientInfos>()
            
            switch try? discussion.kind {
                
            case .oneToOne(withContactIdentity: let contactIdentity):
                
                guard let contactIdentity else {
                    os_log("Could not find contact identity. This is ok if it has just been deleted.", log: Self.log, type: .error)
                    throw ObvUICoreDataError.contactIdentityIsNil
                }
                guard contactIdentity.isActive else {
                    os_log("Trying to create PersistedMessageSentRecipientInfos for an inactive contact, which is not allowed.", log: Self.log, type: .error)
                    throw ObvUICoreDataError.contactIdentityIsNotActive
                }
                let recipientIdentity = contactIdentity.cryptoId.getIdentity()
                let infos = try PersistedMessageSentRecipientInfos(recipientIdentity: recipientIdentity,
                                                                   messageSent: self)
                self.unsortedRecipientsInfos.insert(infos)
                
            case .groupV1(withContactGroup: let contactGroup):
                
                guard let contactGroup else {
                    os_log("Could find contact group (this is ok if it was just deleted)", log: Self.log, type: .error)
                    throw ObvUICoreDataError.groupV1IsNil
                }
                for recipient in contactGroup.contactIdentities {
                    guard recipient.isActive else {
                        os_log("One of the group contacts is inactive. We do not create PersistedMessageSentRecipientInfos for this contact.", log: Self.log, type: .error)
                        continue
                    }
                    let recipientIdentity = recipient.cryptoId.getIdentity()
                    let infos = try PersistedMessageSentRecipientInfos(recipientIdentity: recipientIdentity, messageSent: self)
                    self.unsortedRecipientsInfos.insert(infos)
                }
                guard !self.unsortedRecipientsInfos.isEmpty else {
                    os_log("We created no recipient infos. This happens when all the contacts of a group are inactive. We do not create a PersistedMessageSent in this case", log: Self.log, type: .error)
                    throw ObvUICoreDataError.recipientInfosIsEmpty
                }
                
            case .groupV2(withGroup: let group):
                
                guard let group else {
                    os_log("Could find group v2 (this is ok if it was just deleted)", log: Self.log, type: .error)
                    throw ObvUICoreDataError.groupV2IsNil
                }
                for recipient in group.otherMembers {
                    if let contact = recipient.contact {
                        guard contact.isActive else {
                            os_log("One of the group contacts is inactive. We do not create PersistedMessageSentRecipientInfos for this contact.", log: Self.log, type: .error)
                            continue
                        }
                    }
                    let recipientIdentity = recipient.identity
                    let infos = try PersistedMessageSentRecipientInfos(recipientIdentity: recipientIdentity, messageSent: self)
                    self.unsortedRecipientsInfos.insert(infos)
                }
                
            case .none:

                throw ObvUICoreDataError.unexpectedDiscussionKind
                
            }
            
        }

        // Now that this message is created, we can look for all the messages that have a `messageRepliedToIdentifier` referencing this message.
        // For these messages, we delete this reference and, instead, reference this message using the `messageRepliedTo` relationship.
        
        try self.updateMessagesReplyingToThisMessage()

        // Refresh the status
        
        refreshStatus()
    }
    
    ///Called when the owned identity has refreshed its location
    func setBodyWithLocation() throws {
        let messageBody: String = (self.locationContinuousSent ?? self.locationOneShotSent)?.legacyLocationMessageBody ?? ""
        
        try self.replaceContentWith(newBody: messageBody, newMentions: [])
    }
    
    static private func determineAppropriateSortIndexForMessageReceivedFromOtherOwnedDevice(forSenderSequenceNumber senderSequenceNumber: Int, senderThreadIdentifier: UUID, timestamp: Date, within discussion: PersistedDiscussion) throws -> (sortIndex: Double, adjustedTimestamp: Date) {
        
        let nextMsg = Self.getNextMessageBySenderSequenceNumber(
            senderSequenceNumber,
            senderThreadIdentifier: senderThreadIdentifier,
            within: discussion)
        
        if nextMsg == nil || nextMsg!.timestamp > timestamp {
            let prevMsg = Self.getPreviousMessageBySenderSequenceNumber(
                senderSequenceNumber,
                senderThreadIdentifier: senderThreadIdentifier,
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



    public static func createPersistedMessageSentFromDraft(_ draft: PersistedDraft) throws -> PersistedMessageSent {
        let replyTo: ReplyToType?
        if let messageRepliedTo = draft.replyTo {
            replyTo = .message(messageRepliedTo: messageRepliedTo)
        } else {
            replyTo = nil
        }
        let persistedMessageSent = try self.init(
            body: draft.body,
            replyTo: replyTo,
            fyleJoins: draft.fyleJoins,
            discussion: draft.discussion,
            readOnce: draft.readOnce,
            visibilityDuration: draft.visibilityDuration,
            existenceDuration: draft.existenceDuration,
            forwarded: false,
            mentions: draft.mentions.compactMap({ try? $0.userMention }),
            location: nil,
            timestamp: Date(),
            messageIdentifierFromEngine: nil, // since this message is sent from the current device
            infosFromOtherOwnedDevice: nil)
        return persistedMessageSent
    }
    
    
    public static func createPersistedMessageSentFromShareExtension(body: String, fyleJoins: [FyleJoin], discussion: PersistedDiscussion) throws -> PersistedMessageSent {
        let persistedMessageSent = try PersistedMessageSent(
            body: body,
            replyTo: nil,
            fyleJoins: fyleJoins,
            discussion: discussion,
            readOnce: false,
            visibilityDuration: nil,
            existenceDuration: nil,
            forwarded: false,
            mentions: [],
            location: nil,
            timestamp: Date(),
            messageIdentifierFromEngine: nil, // since this message is sent from the current device
            infosFromOtherOwnedDevice: nil)
        return persistedMessageSent
    }
    
    
    /// In addition to replying from a notification, this is also used to test (on a view context) whether it is possible to reply to a message.
    public static func createPersistedMessageSentWhenReplyingFromTheNotificationExtensionNotification(body: String, discussion: PersistedDiscussion, effectiveReplyTo: PersistedMessageReceived?) throws -> PersistedMessageSent {
        let replyTo: ReplyToType?
        if let effectiveReplyTo {
            replyTo = .message(messageRepliedTo: effectiveReplyTo)
        } else {
            replyTo = nil
        }
        let persistedMessageSent = try PersistedMessageSent(
            body: body,
            replyTo: replyTo,
            fyleJoins: [],
            discussion: discussion,
            readOnce: false,
            visibilityDuration: nil,
            existenceDuration: nil,
            forwarded: false,
            mentions: [],
            location: nil,
            timestamp: Date(),
            messageIdentifierFromEngine: nil, // since this message is sent from the current device
            infosFromOtherOwnedDevice: nil)
        return persistedMessageSent
    }


    
    public static func createPersistedMessageSentWhenForwardingAMessage(messageToForward: PersistedMessage, discussion: PersistedDiscussion, forwarded: Bool) throws -> PersistedMessageSent {
        let persistedMessageSent = try PersistedMessageSent(
            body: messageToForward.textBody,
            replyTo: nil,
            fyleJoins: messageToForward.fyleMessageJoinWithStatus ?? [],
            discussion: discussion,
            readOnce: false,
            visibilityDuration: nil,
            existenceDuration: nil,
            forwarded: forwarded,
            mentions: messageToForward.mentions.compactMap({ try? $0.userMention }),
            location: nil,
            timestamp: Date(),
            messageIdentifierFromEngine: nil, // Since this message is sent from the current device
            infosFromOtherOwnedDevice: nil)
        return persistedMessageSent
    }
    
    
    public static func createPersistedMessageSentForSharingLocation(discussion: PersistedDiscussion, location: SentLocation) throws -> PersistedMessageSent {
        let persistedMessageSent = try PersistedMessageSent(
            body: nil,
            replyTo: nil,
            fyleJoins: [],
            discussion: discussion,
            readOnce: false,
            visibilityDuration: nil,
            existenceDuration: nil,
            forwarded: false,
            mentions: [],
            location: location,
            timestamp: Date(),
            messageIdentifierFromEngine: nil, // Since this message is sent from the current device
            infosFromOtherOwnedDevice: nil)
        return persistedMessageSent
    }
    
}


// MARK: Processing message sent from other owned devices

extension PersistedMessageSent {
    
    /// This method shall be called exclusively from ``PersistedObvOwnedIdentity.createPersistedMessageSentFromOtherOwnedDevice(obvOwnedMessage:messageJSON:returnReceiptJSON:)``.
    static func createPersistedMessageSentFromOtherOwnedDevice(obvOwnedMessage: ObvOwnedMessage, messageJSON: MessageJSON, returnReceiptJSON: ReturnReceiptJSON?, sentLocation: SentLocation?, in discussion: PersistedDiscussion) throws -> PersistedMessageSent {
        
        guard try PersistedMessageSent.getPersistedMessageSentFromOtherOwnedDevice(messageIdentifierFromEngine: obvOwnedMessage.messageIdentifierFromEngine, in: discussion) == nil else {
            throw ObvUICoreDataError.persistedMessageSentAlreadyExists
        }
        
        let discussionKind = try discussion.kind

        let messageUploadTimestampFromServer = PersistedMessage.determineMessageUploadTimestampFromServer(
            messageUploadTimestampFromServerInObvMessage: obvOwnedMessage.messageUploadTimestampFromServer,
            messageJSON: messageJSON,
            discussionKind: discussionKind)

        let replyTo: ReplyToType?
        if let replyToJson = messageJSON.replyTo {
            replyTo = .json(replyToJSON: replyToJson)
        } else {
            replyTo = nil
        }
                
        let fyleJoins = [SentFyleMessageJoinWithStatus]() // Set later, when receiving the attachments
        
        let readOnce: Bool
        let visibilityDuration: TimeInterval?
        let existenceDuration: TimeInterval?
        if let expiration = messageJSON.expiration {
            readOnce = expiration.readOnce
            visibilityDuration = expiration.visibilityDuration
            existenceDuration = expiration.existenceDuration
        } else {
            readOnce = false
            visibilityDuration = nil
            existenceDuration = nil
        }
        
        let infosFromOtherOwnedDevice = (messageJSON.senderThreadIdentifier, messageJSON.senderSequenceNumber)
        
        let message = try self.init(
            body: messageJSON.body,
            replyTo: replyTo,
            fyleJoins: fyleJoins,
            discussion: discussion,
            readOnce: readOnce,
            visibilityDuration: visibilityDuration,
            existenceDuration: existenceDuration,
            forwarded: messageJSON.forwarded,
            mentions: messageJSON.userMentions,
            location: sentLocation,
            timestamp: messageUploadTimestampFromServer,
            messageIdentifierFromEngine: obvOwnedMessage.messageIdentifierFromEngine,
            infosFromOtherOwnedDevice: infosFromOtherOwnedDevice)
        
        message.setStatus(newValue: .sentFromAnotherOwnedDevice)

        // Process the attachments within the message

        message.processObvOwnedAttachmentsFromOtherOwnedDevice(of: obvOwnedMessage)

        return message

    }

    
    func processObvOwnedAttachmentsFromOtherOwnedDevice(of obvOwnedMessage: ObvOwnedMessage) {
        for obvOwnedAttachment in obvOwnedMessage.attachments {
            do {
                try processObvOwnedAttachmentFromOtherOwnedDevice(obvOwnedAttachment)
            } catch {
                os_log("Could not process one of the message's attachments: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                // We continue anyway
            }
        }
    }

    
    func processObvOwnedAttachmentFromOtherOwnedDevice(_ obvOwnedAttachment: ObvOwnedAttachment) throws {
        
        try SentFyleMessageJoinWithStatus.createOrUpdateSentFyleMessageJoinWithStatusFromOtherOwnedDevice(with: obvOwnedAttachment, messageSent: self)

    }

    
    func markAttachmentFromOwnedDeviceAsResumed(attachmentNumber: Int) throws {
        
        guard attachmentNumber < fyleMessageJoinWithStatuses.count else {
            throw ObvUICoreDataError.unexpectedAttachmentNumber
        }
        
        let join = fyleMessageJoinWithStatuses[attachmentNumber]
        
        join.tryToSetStatusTo(.downloading)
        
    }

    
    func markAttachmentFromOwnedDeviceAsPaused(attachmentNumber: Int) throws {
        
        guard attachmentNumber < fyleMessageJoinWithStatuses.count else {
            throw ObvUICoreDataError.unexpectedAttachmentNumber
        }
        
        let join = fyleMessageJoinWithStatuses[attachmentNumber]
        
        join.tryToSetStatusTo(.downloadable)

    }

}


// MARK: Setting delivered or read timestamps

extension PersistedMessageSent {
 
    func refreshStatusOfSentFyleMessageJoinWithStatus(atIndex index: Int) -> SentFyleMessageJoinWithStatus? {
        
        guard let join = fyleMessageJoinWithStatuses.first(where: { $0.index == index }) else { return nil }
        
        // Collect all the attachment infos for all recipients of this attachment
        let allAttachmentInfos: [PersistedAttachmentSentRecipientInfos?] = unsortedRecipientsInfos.filter({ !$0.isDeleted }).map({ $0.attachmentInfos.first(where: { $0.index == index }) })
        
        // Deduce all the attachment reception statuses for all recipients of this attachment
        let allReceptionStatuses = allAttachmentInfos.map({ $0?.status })
        
        // The (global) reception status of the attachment is set:
        // - to "read" if all the recipients did read the attachment
        // - otherwise to "delivered" if all the recipients did receive the attachment,
        // - otherwise to "none".
        let newReceptionStatus: SentFyleMessageJoinWithStatus.FyleReceptionStatus
        if allReceptionStatuses.allSatisfy({ $0 == .read }) {
            newReceptionStatus = .fullyDeliveredAndFullyRead
        } else if allReceptionStatuses.contains(where: { $0 == .read }) && allReceptionStatuses.allSatisfy({ $0 == .delivered || $0 == .read }) {
            newReceptionStatus = .fullyDeliveredAndPartiallyRead
        } else if allReceptionStatuses.allSatisfy({ $0 == .delivered }) {
            newReceptionStatus = .fullyDeliveredAndNotRead
        } else if allReceptionStatuses.contains(where: { $0 == .read }) && allReceptionStatuses.contains(where: { $0 == .delivered || $0 == .read }) {
            newReceptionStatus = .partiallyDeliveredAndPartiallyRead
        } else if allReceptionStatuses.contains(where: { $0 == .delivered }) {
            newReceptionStatus = .partiallyDeliveredNotRead
        } else {
            newReceptionStatus = .none
        }
        
        join.tryToSetReceptionStatusTo(newReceptionStatus)
        
        return join
        
    }
    
}


extension PersistedMessageSent {
    
    /// Called by the operation executed to send a new message from the current device.
    public func toMessageJSONToSend() throws -> MessageJSONToSend {
        
        guard let context = self.managedObjectContext else {
            assertionFailure()
            throw ObvUICoreDataError.noContext
        }
        
        // Make sure the message is not wiped
        
        guard !self.isWiped else {
            assertionFailure()
            throw ObvUICoreDataError.cannotSendWipedMessage
        }
        
        // If the message is a read once message, we won't send it to our other owned devices
        
        let isReadOnce = self.readOnce
        
        // Determine the crypto ids of the potential recipients of the message, i.e., those to whom the message shall still be sent.
        // We will filter those identities later in this operation to only keep those to whom the message can indeed be sent.
        
        let cryptoIdsWithoutMessageIdentifierFromEngine = Set(self.unsortedRecipientsInfos
            .filter({ $0.messageIdentifierFromEngine == nil })
            .map({ $0.recipientCryptoId }))
        
        guard let ownedCryptoId = self.discussion?.ownedIdentity?.cryptoId else {
            assertionFailure()
            throw ObvUICoreDataError.couldNotDetermineOwnedCryptoId
        }
        
        // Determine the discussion kind
        
        guard let discussion = self.discussion else {
            assertionFailure()
            throw ObvUICoreDataError.discussionIsNil
        }
        
        let discussionKind = try discussion.kind
        
        /* Create a set of all the cryptoId's to which the message needs to be sent by the engine,
         * i.e., that has no identifier from the engine (for group v1 and one2one discussions), or that
         * have no identifer from the engine and such that the recipient accepted
         * the group invitation (for group v2)
         */
        
        var contactCryptoIds = Set<ObvCryptoId>()
        
        switch discussionKind {
            
        case .oneToOne:
            
            for contactCryptoId in cryptoIdsWithoutMessageIdentifierFromEngine {
                
                // We can send the message to the recipient if
                // - she is a oneToOne contact
                // - with at least one device
                
                // Determine the contact identity
                
                guard let contact = try PersistedObvContactIdentity.get(
                    contactCryptoId: contactCryptoId,
                    ownedIdentityCryptoId: ownedCryptoId,
                    whereOneToOneStatusIs: .oneToOne,
                    within: context) else {
                    assertionFailure()
                    continue
                }
                
                guard !contact.devices.isEmpty else {
                    // This may happen, when sending a message before a channel is created
                    continue
                }
                
                // If we reach this point, we can send the message to the recipient indicated in the infos.
                
                contactCryptoIds.insert(contactCryptoId)
                
            }
            
        case .groupV1(withContactGroup: let group):
            
            guard let group = group else {
                assertionFailure()
                throw ObvUICoreDataError.groupV1IsNil
            }
            
            for contactCryptoId in cryptoIdsWithoutMessageIdentifierFromEngine {
                
                // We can send the message to the recipient if
                // - she is part of the group
                // - with at least one device
                
                // Determine the contact identity
                
                guard let contact = try PersistedObvContactIdentity.get(
                    contactCryptoId: contactCryptoId,
                    ownedIdentityCryptoId: ownedCryptoId,
                    whereOneToOneStatusIs: .any,
                    within: context) else {
                    assertionFailure()
                    continue
                }
                
                guard !contact.devices.isEmpty else {
                    // This may happen, when sending a message before a channel is created
                    continue
                }
                
                guard group.contactIdentities.contains(contact) else {
                    assertionFailure()
                    continue
                }
                
                // If we reach this point, we can send the message to the recipient indicated in the infos.
                
                contactCryptoIds.insert(contactCryptoId)
                
            }
            
        case .groupV2(withGroup: let group):
            
            guard let group = group else {
                assertionFailure()
                throw ObvUICoreDataError.groupV2IsNil
            }
            
            for contactCryptoId in cryptoIdsWithoutMessageIdentifierFromEngine {
                
                // We can send the message to the recipient if
                // - she is part of the group
                // - she is not pending
                // - with at least one device
                
                // Determine the contact identity
                
                guard let contact = try PersistedObvContactIdentity.get(
                    contactCryptoId: contactCryptoId,
                    ownedIdentityCryptoId: ownedCryptoId,
                    whereOneToOneStatusIs: .any,
                    within: context) else {
                    // Can happen when a recipient is a pending member who is not a contact yet
                    continue
                }
                
                guard !contact.devices.isEmpty else {
                    // This may happen, when sending a message before a channel is created
                    continue
                }
                
                // Make sure the contact is a non-pending member of the group
                
                guard let member = group.otherMembers.first(where: { $0.identity == contactCryptoId.getIdentity() }) else {
                    assertionFailure()
                    continue
                }
                
                guard !member.isPending else {
                    continue
                }
                
                // If we reach this point, we can send the message to the recipient indicated in the infos.
                
                contactCryptoIds.insert(contactCryptoId)
                
            }
            
        }
        
        // Construct the return receipts, payload, etc.
        
        let attachmentsToSend: [ObvAttachmentToSend]
        let messageJSON: MessageJSON
        do {
            
            guard let _messageJSON = self.toMessageJSON() else {
                assertionFailure()
                throw ObvUICoreDataError.couldNotTurnPersistedMessageSentIntoAMessageJSON
            }
            messageJSON = _messageJSON
            
            // For each the of fyles of the SendMessageToProcess, we create a ObvAttachmentToSend
            
            attachmentsToSend = try self.fyleMessageJoinWithStatuses.compactMap {
                guard let metadata = try $0.getFyleMetadata()?.jsonEncode() else { return nil }
                guard let fyle = $0.fyle else { return nil }
                guard let totalUnitCount = fyle.getFileSize() else { return nil }
                return ObvAttachmentToSend(fileURL: fyle.url,
                                           deleteAfterSend: false,
                                           totalUnitCount: Int(totalUnitCount),
                                           metadata: metadata)
            }
            
        }
        
        // Determine if the owned identity has other owned devices
        
        let hasAnotherDeviceWhichIsReachable: Bool
        do {
            guard let ownedIdentity = discussion.ownedIdentity else {
                assertionFailure()
                throw ObvUICoreDataError.ownedIdentityIsNil
            }
            hasAnotherDeviceWhichIsReachable = ownedIdentity.hasAnotherDeviceWhichIsReachable
        }

        // Return
        
        let messageJSONToSend = MessageJSONToSend(ownedCryptoId: ownedCryptoId,
                                                  contactCryptoIds: contactCryptoIds,
                                                  messageJSON: messageJSON,
                                                  attachmentsToSend: attachmentsToSend,
                                                  hasAnotherDeviceWhichIsReachable: hasAnotherDeviceWhichIsReachable,
                                                  isReadOnce: isReadOnce)
        
        return messageJSONToSend
        
    }
    
    
    func toSentMessageReferenceJSON() -> MessageReferenceJSON? {
        guard let senderIdentifier = self.discussion?.ownedIdentity?.cryptoId.getIdentity() else { return nil }
        return MessageReferenceJSON(senderSequenceNumber: self.senderSequenceNumber,
                                    senderThreadIdentifier: self.senderThreadIdentifier,
                                    senderIdentifier: senderIdentifier)
    }
    
    
    private func toMessageJSON() -> MessageJSON? {
        
        let replyToJSON: MessageReferenceJSON?
        switch self.repliesTo {
        case .available(message: let replyTo):
            replyToJSON = replyTo.toMessageReferenceJSON()
        case .none, .deleted, .notAvailableYet:
            replyToJSON = nil
        }

        guard let discussionKind = try? discussion?.kind else {
            assertionFailure()
            return nil
        }
        
        switch discussionKind {
            
        case .oneToOne(withContactIdentity: let contactIdentity):
            
            guard let oneToOneDiscussion = contactIdentity?.oneToOneDiscussion else {
                os_log("Could find contact identity (this is ok if it was just deleted)", log: Self.log, type: .error)
                return nil
            }
            
            guard let oneToOneIdentifier = try? oneToOneDiscussion.oneToOneIdentifier else {
                os_log("Could not determine one2one discussion identifier", log: Self.log, type: .error)
                return nil
            }

            return MessageJSON(senderSequenceNumber: self.senderSequenceNumber,
                               senderThreadIdentifier: self.senderThreadIdentifier,
                               body: self.textBodyToSend,
                               oneToOneIdentifier: oneToOneIdentifier,
                               replyTo: replyToJSON,
                               expiration: self.expirationJSON,
                               location: self.locationJSON,
                               forwarded: self.forwarded,
                               userMentions: mentions.compactMap({try? $0.userMention}))

        case .groupV1(withContactGroup: let contactGroup):
            guard let contactGroup = contactGroup else {
                os_log("Could find contact group (this is ok if it was just deleted)", log: Self.log, type: .error)
                return nil
            }
            let groupUid = contactGroup.groupUid
            let groupOwner: ObvCryptoId
            if let groupJoined = contactGroup as? PersistedContactGroupJoined {
                guard let owner = groupJoined.owner else {
                    os_log("The owner is nil. This is ok if it was just deleted.", log: Self.log, type: .error)
                    return nil
                }
                groupOwner = owner.cryptoId
            } else  if let groupOwned = contactGroup as? PersistedContactGroupOwned {
                guard let owner = groupOwned.owner else {
                    os_log("The owner is nil. This is ok if it was just deleted.", log: Self.log, type: .error)
                    return nil
                }
                groupOwner = owner.cryptoId
            } else {
                return nil
            }
            let groupV1Identifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
            
            return MessageJSON(senderSequenceNumber: self.senderSequenceNumber,
                               senderThreadIdentifier: self.senderThreadIdentifier,
                               body: self.textBodyToSend,
                               groupV1Identifier: groupV1Identifier,
                               replyTo: replyToJSON,
                               expiration: self.expirationJSON,
                               location: self.locationJSON,
                               forwarded: self.forwarded,
                               userMentions: mentions.compactMap({try? $0.userMention}))

        case .groupV2(withGroup: let group):
            guard let group = group else {
                os_log("Could find group v2 (this is ok if it was just deleted)", log: Self.log, type: .error)
                return nil
            }
            let groupV2Identifier = group.groupIdentifier
            
            let originalServerTimestamp = unsortedRecipientsInfos.compactMap({ $0.timestampMessageSent }).min()
            
            return MessageJSON(senderSequenceNumber: self.senderSequenceNumber,
                               senderThreadIdentifier: self.senderThreadIdentifier,
                               body: self.textBodyToSend,
                               groupV2Identifier: groupV2Identifier,
                               replyTo: replyToJSON,
                               expiration: self.expirationJSON,
                               location: self.locationJSON,
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
    
    // Called when serializing a message before sending it
    private var locationJSON: LocationJSON? {
        guard isLocationMessage else { return nil }
        
        if let location = locationContinuousSent ?? locationOneShotSent { // `SHARING` or `SEND` location
            return try? location.toLocationJSON()
        } else { // no location means it is a `END_SHARING`
            return LocationJSON.defaultLocation(with: .END_SHARING)
        }
    }
}


// MARK: - Determining actions availability

extension PersistedMessageSent {
    
    var copyActionCanBeMadeAvailableForSentMessage: Bool {
        return shareActionCanBeMadeAvailableForSentMessage
    }

    var shareActionCanBeMadeAvailableForSentMessage: Bool {
        return !isWiped && !isEphemeralMessageWithLimitedVisibility && !isLocationMessage
    }
    
    var forwardActionCanBeMadeAvailableForSentMessage: Bool {
        return shareActionCanBeMadeAvailableForSentMessage
    }

    var infoActionCanBeMadeAvailableForSentMessage: Bool {
        return !unsortedRecipientsInfos.isEmpty || !metadata.isEmpty
    }
    
    var editBodyActionCanBeMadeAvailableForSentMessage: Bool {
        assert(Thread.isMainThread)
        
        guard let context = self.managedObjectContext else {
            assertionFailure()
            return false
        }
        guard context.concurrencyType == .mainQueueConcurrencyType else {
            assertionFailure()
            return false
        }
        
        let childViewContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        childViewContext.parent = context
        guard let sentMessageInChildViewContext = try? PersistedMessageSent.getPersistedMessageSent(objectID: self.typedObjectID, within: childViewContext) else {
            assertionFailure()
            return false
        }
        guard let ownedIdentity = sentMessageInChildViewContext.discussion?.ownedIdentity else {
            assertionFailure()
            return false
        }
        // We return true iff the update would succeed
        do {
            _ = try ownedIdentity.processLocalUpdateMessageRequestFromThisOwnedIdentity(persistedSentMessageObjectID: self.typedObjectID, newTextBody: nil)
            return true
        } catch {
            return false
        }
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
            case messageIdentifierFromEngine = "messageIdentifierFromEngine"
            case rawExistenceDuration = "rawExistenceDuration"
            case senderThreadIdentifier = "senderThreadIdentifier"
            // Relationships
            case expirationForSentLimitedExistence = "expirationForSentLimitedExistence"
            case expirationForSentLimitedVisibility = "expirationForSentLimitedVisibility"
            case unsortedFyleMessageJoinWithStatuses = "unsortedFyleMessageJoinWithStatuses"
            case unsortedRecipientsInfos = "unsortedRecipientsInfos"
            // Others
            static let expirationForSentLimitedVisibilityExpirationDate = [expirationForSentLimitedVisibility.rawValue, PersistedMessageExpiration.Predicate.Key.expirationDate.rawValue].joined(separator: ".")
            static let expirationForSentLimitedExistenceExpirationDate = [expirationForSentLimitedExistence.rawValue, PersistedMessageExpiration.Predicate.Key.expirationDate.rawValue].joined(separator: ".")
            static let ownedIdentityIdentity = [PersistedMessage.Predicate.Key.discussion.rawValue, PersistedDiscussion.Predicate.Key.ownedIdentityIdentity].joined(separator: ".")
        }
        static var wasSent: NSPredicate {
            NSPredicate(PersistedMessage.Predicate.Key.rawStatus, largerThanOrEqualToInt: MessageStatus.sent.rawValue)
        }
        static var isLocationMessage: NSPredicate {
            NSPredicate(PersistedMessage.Predicate.Key.isLocation, is: true)
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
        static func withPermanentID(_ permanentID: MessageSentPermanentID) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(withEntity: PersistedMessageSent.entity()),
                PersistedMessage.Predicate.withPermanentID(permanentID.downcast),
            ])
        }
        static func withSenderThreadIdentifier(_ senderThreadIdentifier: UUID) -> NSPredicate {
            NSPredicate(Key.senderThreadIdentifier, EqualToUuid: senderThreadIdentifier)
        }
        static func withMessageIdentifierFromEngine(_ messageIdentifierFromEngine: Data) -> NSPredicate {
            NSPredicate(Key.messageIdentifierFromEngine, EqualToData: messageIdentifierFromEngine)
        }
        static func fromOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.ownedIdentityIdentity, EqualToData: ownedCryptoId.getIdentity())
        }
        static func fromPersistedObvOwnedIdentity(_ ownedIdentity: PersistedObvOwnedIdentity) -> NSPredicate {
            fromOwnedCryptoId(ownedIdentity.cryptoId)
        }
        static func withObjectID(_ objectID: NSManagedObjectID) -> NSPredicate {
            NSPredicate(withObjectID: objectID)
        }
        static func withMessageWriterIdentifier(_ identifier:  MessageWriterIdentifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                PersistedMessage.Predicate.withOwnedIdentityIdentity(identifier.senderIdentifier),
                PersistedMessage.Predicate.withSenderSequenceNumberEqualTo(identifier.senderSequenceNumber),
                withSenderThreadIdentifier(identifier.senderThreadIdentifier),
            ])
        }
        static var withStrictlyMoreThanOneRecipientsInfos: NSPredicate {
            NSPredicate(withStrictlyMoreThanOneCountForKey: Key.unsortedRecipientsInfos)
        }
    }

    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedMessageSent> {
        return NSFetchRequest<PersistedMessageSent>(entityName: PersistedMessageSent.entityName)
    }
    
    
    static func getPersistedMessageSent(discussion: PersistedDiscussion, messageId: SentMessageIdentifier) throws -> PersistedMessageSent? {
        guard let context = discussion.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        let request: NSFetchRequest<PersistedMessageSent> = PersistedMessageSent.fetchRequest()
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
    
    public static func getPersistedLocationMessagesSent(discussion: PersistedDiscussion) throws -> [PersistedMessageSent] {
        guard let context = discussion.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        let request: NSFetchRequest<PersistedMessageSent> = PersistedMessageSent.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.isLocationMessage,
                Predicate.withinDiscussion(discussion),
            ])
        return try context.fetch(request)
    }


    /// Returns all `PersistedMessageSent` entities that have Location datas
    public static func getAllPersistedLocationMessagesSent(within context: NSManagedObjectContext) throws -> [PersistedMessageSent] {
        let request: NSFetchRequest<PersistedMessageSent> = PersistedMessageSent.fetchRequest()
        request.predicate = Predicate.isLocationMessage
        return try context.fetch(request)
    }

    private static func getNextMessageBySenderSequenceNumber(_ sequenceNumber: Int, senderThreadIdentifier: UUID, within discussion: PersistedDiscussion) -> PersistedMessageReceived? {
        guard let context = discussion.managedObjectContext else { return nil }
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            Predicate.withSenderThreadIdentifier(senderThreadIdentifier),
            PersistedMessage.Predicate.withSenderSequenceNumberLargerThan(sequenceNumber),
        ])
        request.sortDescriptors = [NSSortDescriptor(key: PersistedMessage.Predicate.Key.senderSequenceNumber.rawValue, ascending: true)]
        request.fetchLimit = 1
        do { return try context.fetch(request).first } catch { return nil }
    }

    
    private static func getPreviousMessageBySenderSequenceNumber(_ sequenceNumber: Int, senderThreadIdentifier: UUID, within discussion: PersistedDiscussion) -> PersistedMessageReceived? {
        guard let context = discussion.managedObjectContext else { return nil }
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            Predicate.withSenderThreadIdentifier(senderThreadIdentifier),
            PersistedMessage.Predicate.withSenderSequenceNumberLessThan(sequenceNumber),
        ])
        request.sortDescriptors = [NSSortDescriptor(key: PersistedMessage.Predicate.Key.senderSequenceNumber.rawValue, ascending: false)]
        request.fetchLimit = 1
        do { return try context.fetch(request).first } catch { return nil }
    }

    
    static func getPersistedMessageSentFromOtherOwnedDevice(messageIdentifierFromEngine: Data, in discussion: PersistedDiscussion) throws -> PersistedMessageSent? {
        guard let context = discussion.managedObjectContext else {
            assertionFailure()
            throw ObvUICoreDataError.noContext
        }
        let request: NSFetchRequest<PersistedMessageSent> = PersistedMessageSent.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withMessageIdentifierFromEngine(messageIdentifierFromEngine),
            Predicate.withinDiscussion(discussion),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    static func getPersistedMessageSentFromOtherOwnedDevice(messageIdentifierFromEngine: Data, from ownedIdentity: PersistedObvOwnedIdentity) throws -> PersistedMessageSent? {
        guard let context = ownedIdentity.managedObjectContext else {
            assertionFailure()
            throw ObvUICoreDataError.noContext
        }
        let request: NSFetchRequest<PersistedMessageSent> = PersistedMessageSent.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withMessageIdentifierFromEngine(messageIdentifierFromEngine),
            Predicate.fromPersistedObvOwnedIdentity(ownedIdentity),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    public static func get(messageId: ObvMessageIdentifier, within context: NSManagedObjectContext) throws -> PersistedMessageSent? {
        return try Self.get(ownedCryptoId: ObvCryptoId(cryptoIdentity: messageId.ownedCryptoIdentity), messageIdentifierFromEngine: messageId.uid.raw, within: context)
    }

    
    public static func get(ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data, within context: NSManagedObjectContext) throws -> PersistedMessageSent? {
        let request: NSFetchRequest<PersistedMessageSent> = PersistedMessageSent.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withMessageIdentifierFromEngine(messageIdentifierFromEngine),
            Predicate.fromOwnedCryptoId(ownedCryptoId),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    public static func getPersistedMessageSent(objectID: TypeSafeManagedObjectID<PersistedMessageSent>, within context: NSManagedObjectContext) throws -> PersistedMessageSent? {
        let request: NSFetchRequest<PersistedMessageSent> = PersistedMessageSent.fetchRequest()
        request.predicate = PersistedMessage.Predicate.withObjectID(objectID.objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    public static func getManagedObject(withPermanentID permanentID: MessageSentPermanentID, within context: NSManagedObjectContext) throws -> PersistedMessageSent? {
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
        guard let context = discussion.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        let request: NSFetchRequest<PersistedMessageSent> = PersistedMessageSent.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            PersistedMessage.Predicate.withSenderSequenceNumberEqualTo(senderSequenceNumber),
            Predicate.withSenderThreadIdentifier(senderThreadIdentifier),
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
        guard let context = discussion.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
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
        guard let context = discussion.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        let request: NSFetchRequest<PersistedMessageSent> = PersistedMessageSent.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            Predicate.wasSent,
        ])
        return try context.count(for: request)
    }

    
    /// This method is exclusively called from ``ConsolidateLegacyTimestampsOfPersistedMessageSentRecipientInfosOperation``.
    /// It makes sure the statuses of all sent messages are appropriate, and reflect the new statuses introduced in version 3.1.
    public static func updateLegacyStatuses(within context: NSManagedObjectContext, maxNumberOfChanges: Int) throws {
        
        var numberOfChanges = 0
        
        let request: NSFetchRequest<PersistedMessageSent> = PersistedMessageSent.fetchRequest()
        request.predicate = Predicate.withStrictlyMoreThanOneRecipientsInfos
        request.fetchBatchSize = 1_000
        request.propertiesToFetch = [PersistedMessage.Predicate.Key.rawStatus.rawValue]
        request.includesPendingChanges = true
        let messages = try context.fetch(request)
        for message in messages {
            message.refreshStatus()
            if message.hasChanges {
                numberOfChanges += 1
                guard numberOfChanges < maxNumberOfChanges else {
                    return
                }
            }
        }

    }

}


extension PersistedMessageSent {

    public var fyleMessageJoinWithStatusesOfImageType: [SentFyleMessageJoinWithStatus] {
        fyleMessageJoinWithStatuses.filter({ Self.supportedImageTypeIdentifiers.contains($0.uti)  })
    }

    public var fyleMessageJoinWithStatusesOfAudioType: [SentFyleMessageJoinWithStatus] {
        fyleMessageJoinWithStatuses.filter({ $0.contentType.conforms(to: .audio) })
    }
    
    public var fyleMessageJoinWithStatusesOfPDFOrOtherDocumentLikeType: [SentFyleMessageJoinWithStatus] {
        fyleMessageJoinWithStatuses.filter({ $0.contentType.conforms(to: .pdf) })
    }

    /**
     * Get attachments of type `olvidLinkPreview` that are used to display preview links within a message
     *  - Returns fyleMessageJoinWithStatusesOfPreviewType: [ReceivedFyleMessageJoinWithStatus]
     */
    public var fyleMessageJoinWithStatusesOfPreviewType: [SentFyleMessageJoinWithStatus] {
        fyleMessageJoinWithStatuses.filter({ $0.isPreviewType })
    }
    
    public var sharableFyleMessageJoinWithStatuses: [SentFyleMessageJoinWithStatus] {
        fyleMessageJoinWithStatuses.filter({ !$0.isPreviewType })
    }
    
    /**
     * Get attachments that can be downloaded now.
     * An attachment is downloadable if there is no size limit set by the user *OR* if the attachment's size is less than the value set by the user as a threshold *OR* if it is a preview (which should always be downloaded)
     *  - Returns fyleMessageJoinWithStatusesToDownload: [ReceivedFyleMessageJoinWithStatus]
     */
    public var fyleMessageJoinWithStatusesToDownload: [SentFyleMessageJoinWithStatus] {
        // If the message is wiped, we never request the download of its attachments
        guard !self.isWiped else { return [] }
        return fyleMessageJoinWithStatuses
            .filter { join in
                // A negative maxAttachmentSizeForAutomaticDownload means "unlimited"
                return ObvMessengerSettings.Downloads.maxAttachmentSizeForAutomaticDownload < 0
                || join.totalByteCount < ObvMessengerSettings.Downloads.maxAttachmentSizeForAutomaticDownload
                || join.isPreviewType
            }
            .filter {
                $0.status == .downloadable
            }
    }
    
    
    public var fyleMessageJoinWithStatusesFromOtherOwnedDeviceToDeleteFromServer: [SentFyleMessageJoinWithStatus] {
        fyleMessageJoinWithStatuses
            .filter { $0.messageIdentifierFromEngine != nil }
            .filter { $0.status == .cancelledByServer || $0.status == .complete || $0.isWiped }
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
        if let discussion, let objectPermanentID = try? self.objectPermanentID, changedKeys.contains(PersistedMessage.Predicate.Key.rawStatus.rawValue), self.status == .sent, self.readOnce {
            ObvMessengerCoreDataNotification.aReadOncePersistedMessageSentWasSent(persistedMessageSentPermanentID: objectPermanentID,
                                                                                  persistedDiscussionPermanentID: discussion.discussionPermanentID)
                .postOnDispatchQueue()
        }
        
        if isInserted {
            do {
                let messageSent = try self.toStructure()
                Task { await Self.observersHolder.aPersistedMessageSentWasInserted(messageSent: messageSent) }
            } catch {
                Self.logger.fault("Could not convert to structure: \(error)")
                assertionFailure()
            }
        }

    }
    
}


public extension TypeSafeManagedObjectID where T == PersistedMessageSent {
    var downcast: TypeSafeManagedObjectID<PersistedMessage> {
        TypeSafeManagedObjectID<PersistedMessage>(objectID: objectID)
    }
}


/**
 * typealias `MessageSentPermanentID`
 */

public typealias MessageSentPermanentID = ObvManagedObjectPermanentID<PersistedMessageSent>


// MARK: - PersistedMessageSent observers

public protocol PersistedMessageSentObserver {
    func aPersistedMessageSentWasInserted(messageSent: PersistedMessageSentStructure) async
}


private actor PersistedMessageSentObserversHolder: PersistedMessageSentObserver {
    
    private var observers = [PersistedMessageSentObserver]()
    
    func addObserver(_ newObserver: PersistedMessageSentObserver) {
        self.observers.append(newObserver)
    }
    
    // Implementing PersistedMessageSentObserver
    
    func aPersistedMessageSentWasInserted(messageSent: PersistedMessageSentStructure) async {
        for observer in observers {
            await observer.aPersistedMessageSentWasInserted(messageSent: messageSent)
        }
    }
    
}
