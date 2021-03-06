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
final class PersistedMessageSent: PersistedMessage {
    
    private static let entityName = "PersistedMessageSent"
    private static let expirationForSentLimitedExistenceKey = "expirationForSentLimitedExistence"
    private static let expirationForSentLimitedVisibilityKey = "expirationForSentLimitedVisibility"
    private static let discussionSenderThreadIdentifierKey = [PersistedMessage.Predicate.Key.discussion.rawValue, PersistedDiscussion.senderThreadIdentifierKey].joined(separator: ".")
    private static let discussionOwnedIdentityIdentityKey = [PersistedMessage.Predicate.Key.discussion.rawValue, PersistedDiscussion.ownedIdentityKey, PersistedObvOwnedIdentity.identityKey].joined(separator: ".")

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "PersistedMessageSent")
    
    private static func makeError(message: String) -> Error { NSError(domain: String(describing: Self.self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { PersistedMessageSent.makeError(message: message) }

    enum MessageStatus: Int, Comparable, CaseIterable {
        case unprocessed = 0
        case processing = 1
        case sent = 2
        case delivered = 3
        case read = 4
        
        static func < (lhs: PersistedMessageSent.MessageStatus, rhs: PersistedMessageSent.MessageStatus) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }

    }

    // MARK: - Attributes

    @NSManaged private var rawExistenceDuration: NSNumber?

    // MARK: - Relationships
    
    @NSManaged private(set) var expirationForSentLimitedExistence: PersistedExpirationForSentMessageWithLimitedExistence?
    @NSManaged private(set) var expirationForSentLimitedVisibility: PersistedExpirationForSentMessageWithLimitedVisibility?
    @NSManaged private(set) var unsortedRecipientsInfos: Set<PersistedMessageSentRecipientInfos>
    @NSManaged private var unsortedFyleMessageJoinWithStatuses: Set<SentFyleMessageJoinWithStatus>

    // MARK: - Computed variables

    override var kind: PersistedMessageKind { .sent }
    
    var wasSent: Bool {
        switch status {
        case .unprocessed, .processing:
            return false
        case .sent, .delivered, .read:
            return true
        }
    }
    
    private(set) var status: MessageStatus {
        get {
            if let status = MessageStatus(rawValue: self.rawStatus) {
                return status
            } else {
                return .delivered
            }
        }
        set {
            guard self.status < newValue else { return }
            self.rawStatus = newValue.rawValue
            switch self.status {
            case .unprocessed:
                break
            case .processing:
                break
            case .sent:
                // When a sent message is marked as "sent", we check whether it has a limited visibility.
                // If this is the case, we immediately create an appropriate expiration for this message.
                if let visibilityDuration = self.visibilityDuration {
                    assert(self.expirationForSentLimitedVisibility == nil)
                    self.expirationForSentLimitedVisibility = PersistedExpirationForSentMessageWithLimitedVisibility(messageSentWithLimitedVisibility: self,
                                                                                                                     visibilityDuration: visibilityDuration,
                                                                                                                     retainWipedMessageSent: retainWipedOutboundMessages)
                }
                // When a sent message is marked as "sent", we check whether it has a limited existence.
                // If this is the case, we immediately create an appropriate expiration for this message.
                if let existenceDuration = self.existenceDuration {
                    assert(self.expirationForSentLimitedExistence == nil)
                    self.expirationForSentLimitedExistence =  PersistedExpirationForSentMessageWithLimitedExistence(messageSentWithLimitedExistence: self,
                                                                                                                    existenceDuration: existenceDuration)
                }
            case .delivered:
                break
            case .read:
                break
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
    /// It loops through all infos and set the status to the "minimum" possible status.
    func refreshStatus() {
        let notDeletedUnsortedRecipientsInfos = unsortedRecipientsInfos.filter { !$0.isDeleted }

        let atLeastOneInfoHasMessageIdentifierFromEngine = notDeletedUnsortedRecipientsInfos.contains(where: { $0.messageIdentifierFromEngine != nil })
        let allMessageAndAttachmentsAreSent = notDeletedUnsortedRecipientsInfos.allSatisfy { $0.messageAndAttachmentsAreSent }
        let allInfosHaveTimestampDelivered = notDeletedUnsortedRecipientsInfos.allSatisfy { $0.timestampDelivered != nil }
        let allInfosHaveTimestampRead = notDeletedUnsortedRecipientsInfos.allSatisfy { $0.timestampRead != nil }

        if allInfosHaveTimestampRead {
            self.status = .read
        } else if allInfosHaveTimestampDelivered {
            self.status = .delivered
        } else if allMessageAndAttachmentsAreSent {
            self.status = .sent
        } else if atLeastOneInfoHasMessageIdentifierFromEngine {
            self.status = .processing
        } else {
            self.status = .unprocessed
        }
    }
    

    var fyleMessageJoinWithStatuses: [SentFyleMessageJoinWithStatus] {
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

    var isEphemeralMessage: Bool {
        readOnce || existenceDuration != nil || visibilityDuration != nil
    }

    var isEphemeralMessageWithLimitedVisibility: Bool {
        self.readOnce || self.visibilityDuration != nil
    }

    
    /// `true` when this instance can be edited after being sent
    override var textBodyCanBeEdited: Bool {
        guard self.discussion is PersistedOneToOneDiscussion || self.discussion is PersistedGroupDiscussion else { return false }
        guard !self.isLocallyWiped else { return false }
        guard !self.isRemoteWiped else { return false }
        return true
    }
    
    @objc override func editTextBody(newTextBody: String?) throws {
        guard self.textBodyCanBeEdited else {
            throw makeError(message: "The text body of this sent message cannot be edited now")
        }
        try super.editTextBody(newTextBody: newTextBody)
        try deleteMetadataOfKind(.edited)
        try addMetadata(kind: .edited, date: Date())
    }
    

    override func toMessageReferenceJSON() -> MessageReferenceJSON? {
        return toSentMessageReferenceJSON()
    }

    override var fyleMessageJoinWithStatus: [FyleMessageJoinWithStatus]? {
        fyleMessageJoinWithStatuses
    }

    override var messageIdentifiersFromEngine: Set<Data> {
        Set(unsortedRecipientsInfos.compactMap({ $0.messageIdentifierFromEngine }))
    }

    override var genericRepliesTo: PersistedMessage.RepliedMessage {
        repliesTo.toRepliedMessage
    }
    
    
    override var shouldBeDeleted: Bool {
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

    convenience init(body: String?, replyTo: PersistedMessage?, fyleJoins: [FyleJoin], discussion: PersistedDiscussion, readOnce: Bool, visibilityDuration: TimeInterval?, existenceDuration: TimeInterval?) throws {

        guard let context = discussion.managedObjectContext else { assertionFailure(); throw PersistedMessageSent.makeError(message: "Could not find context") }

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
                      forEntityName: PersistedMessageSent.entityName)

        self.existenceDuration = existenceDuration
        self.unsortedFyleMessageJoinWithStatuses = Set<SentFyleMessageJoinWithStatus>()
        fyleJoins.forEach {
            if let sentFyleMessageJoinWithStatuses = SentFyleMessageJoinWithStatus.init(fyleJoin: $0, persistedMessageSentObjectID: self.typedObjectID, within: context) {
                self.unsortedFyleMessageJoinWithStatuses.insert(sentFyleMessageJoinWithStatuses)
            } else {
                debugPrint("Could not create SentFyleMessageJoinWithStatus")
            }
        }

        // Create the recipient infos entries for the contact(s) that are part of the discussion
        self.unsortedRecipientsInfos = Set<PersistedMessageSentRecipientInfos>()
        if let oneToOneDiscussion = discussion as? PersistedOneToOneDiscussion {
            guard let contactIdentity = oneToOneDiscussion.contactIdentity else {
                os_log("Could not find contact identity. This is ok if it has just been deleted.", log: log, type: .error)
                throw makeError(message: "Could not find contact identity. This is ok if it has just been deleted.")
            }
            guard contactIdentity.isActive else {
                os_log("Trying to create PersistedMessageSentRecipientInfos for an inactive contact, which is not allowed.", log: log, type: .error)
                throw makeError(message: "Trying to create PersistedMessageSentRecipientInfos for an inactive contact, which is not allowed.")
            }
            let recipientIdentity = contactIdentity.cryptoId.getIdentity()
            guard let infos = PersistedMessageSentRecipientInfos(recipientIdentity: recipientIdentity,
                                                                 messageSent: self) else {
                throw makeError(message: "Could not find PersistedMessageSentRecipientInfos")
            }
            self.unsortedRecipientsInfos.insert(infos)
        } else if let groupDiscussion = discussion as? PersistedGroupDiscussion {
            guard let contactGroup = groupDiscussion.contactGroup else {
                os_log("Could find contact group (this is ok if it was just deleted)", log: log, type: .error)
                throw makeError(message: "Could find contact group (this is ok if it was just deleted)")
            }
            for recipient in contactGroup.contactIdentities {
                guard recipient.isActive else {
                    os_log("One of the group contacts is inactive. We do not create PersistedMessageSentRecipientInfos for this contact.", log: log, type: .error)
                    continue
                }
                let recipientIdentity = recipient.cryptoId.getIdentity()
                guard let infos = PersistedMessageSentRecipientInfos(recipientIdentity: recipientIdentity, messageSent: self) else {
                    throw makeError(message: "Could not find PersistedMessageSentRecipientInfos")
                }
                self.unsortedRecipientsInfos.insert(infos)
            }
            guard !self.unsortedRecipientsInfos.isEmpty else {
                os_log("We created no recipient infos. This happens when all the contacts of a group are inactive. We do not create a PersistedMessageSent in this case", log: log, type: .error)
                throw makeError(message: "We created no recipient infos. This happens when all the contacts of a group are inactive. We do not create a PersistedMessageSent in this case")
            }
        } else {
            throw makeError(message: "Unexpected discussion type.")
        }

        discussion.lastOutboundMessageSequenceNumber = self.senderSequenceNumber

    }

    convenience init(draft: Draft) throws {
        try self.init(body: draft.body,
                  replyTo: draft.replyTo,
                      fyleJoins: draft.fyleJoins,
                  discussion: draft.discussion,
                  readOnce: draft.readOnce,
                  visibilityDuration: draft.visibilityDuration,
                  existenceDuration: draft.existenceDuration)
    }
    
    
    /// Called when a sent message with limited visibility reached the end of this visibility (in which case the requester is nil)
    /// or when a message was globally wiped (in which case the requester is non nil)
    func wipe(requester: PersistedObvContactIdentity? = nil) throws {
        if requester == nil {
            guard !isLocallyWiped else { return }
        } else {
            guard !isRemoteWiped else { return }
        }
        for join in fyleMessageJoinWithStatuses {
            try join.wipe()
        }
        self.deleteBody()
        try? self.reactions.forEach { try $0.delete() }
        if let remoteCryptoId = requester?.cryptoId {
            try addMetadata(kind: .remoteWiped(remoteCryptoId: remoteCryptoId), date: Date())
        } else {
            try addMetadata(kind: .wiped, date: Date())
        }
        // It makes no sens to keep an existing visibility expiration (if one exists) since we just wiped the message.
        try expirationForSentLimitedVisibility?.delete()
    }
    
}


extension PersistedMessageSent {
    
    
    func toSentMessageReferenceJSON() -> MessageReferenceJSON? {
        guard let senderIdentifier = self.discussion.ownedIdentity?.cryptoId.getIdentity() else { return nil }
        return MessageReferenceJSON(senderSequenceNumber: self.senderSequenceNumber,
                                    senderThreadIdentifier: self.discussion.senderThreadIdentifier,
                                    senderIdentifier: senderIdentifier)
    }
    
    
    func toJSON() -> MessageJSON? {
        let groupId: (groupUid: UID, groupOwner: ObvCryptoId)?
        if let discussion = self.discussion as? PersistedGroupDiscussion {
            guard let contactGroup = discussion.contactGroup else {
                os_log("Could find contact group (this is ok if it was just deleted)", log: log, type: .error)
                return nil
            }
            let groupUid = contactGroup.groupUid
            let groupOwner: ObvCryptoId
            if let groupJoined = discussion.contactGroup as? PersistedContactGroupJoined {
                guard let owner = groupJoined.owner else {
                    os_log("The owner is nil. This is ok if it was just deleted.", log: log, type: .error)
                    return nil
                }
                groupOwner = owner.cryptoId
            } else  if let groupOwned = discussion.contactGroup as? PersistedContactGroupOwned {
                guard let owner = groupOwned.owner else {
                    os_log("The owner is nil. This is ok if it was just deleted.", log: log, type: .error)
                    return nil
                }
                groupOwner = owner.cryptoId
            } else {
                return nil
            }
            groupId = (groupUid, groupOwner)
        } else {
            groupId = nil
        }
        

        let replyToJSON: MessageReferenceJSON?
        switch self.repliesTo {
        case .available(message: let replyTo):
            replyToJSON = replyTo.toMessageReferenceJSON()
        case .none, .deleted:
            replyToJSON = nil
        }
        
        return MessageJSON(senderSequenceNumber: self.senderSequenceNumber,
                           senderThreadIdentifier: self.discussion.senderThreadIdentifier,
                           body: self.textBodyToSend,
                           groupId: groupId,
                           replyTo: replyToJSON,
                           expiration: self.expirationJSON)
    }
    
    
    private var expirationJSON: ExpirationJSON? {
        guard isEphemeralMessage else {
            return nil
        }
        return ExpirationJSON(readOnce: readOnce, visibilityDuration: visibilityDuration, existenceDuration: existenceDuration)
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

}


// MARK: - Convenience DB getters

extension PersistedMessageSent {
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedMessageSent> {
        return NSFetchRequest<PersistedMessageSent>(entityName: PersistedMessageSent.entityName)
    }
    
    struct Predicate {
        static var readOnce: NSPredicate { NSPredicate(format: "\(PersistedMessage.readOnceKey) == TRUE") }
        static var wasSent: NSPredicate { NSPredicate(format: "\(rawStatusKey) >= %d", MessageStatus.sent.rawValue) }
        static var expiresForSentLimitedVisibility: NSPredicate {
            NSPredicate(format: "\(PersistedMessageSent.expirationForSentLimitedVisibilityKey) != NIL")
        }
        static var expiresForSentLimitedExistence: NSPredicate {
            NSPredicate(format: "\(PersistedMessageSent.expirationForSentLimitedExistenceKey) != NIL")
        }
        static func expiredBefore(_ date: Date) -> NSPredicate {
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    expiresForSentLimitedVisibility,
                    NSPredicate(format: "\(PersistedMessageSent.expirationForSentLimitedVisibilityKey).\(PersistedMessageExpiration.expirationDateKey) < %@", date as NSDate),
                ]),
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    expiresForSentLimitedExistence,
                    NSPredicate(format: "\(PersistedMessageSent.expirationForSentLimitedExistenceKey).\(PersistedMessageExpiration.expirationDateKey) < %@", date as NSDate),
                ]),
            ])
        }
        static func withinDiscussion(_ discussion: PersistedDiscussion) -> NSPredicate {
            NSPredicate(format: "%K == %@", PersistedMessage.Predicate.Key.discussion.rawValue, discussion.objectID)
        }
        static func withinDiscussionWithObjectID(_ discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) -> NSPredicate {
            NSPredicate(format: "%K == %@", PersistedMessage.Predicate.Key.discussion.rawValue, discussionObjectID.objectID)
        }
        static func createdBefore(date: Date) -> NSPredicate {
            NSPredicate(format: "%K < %@", timestampKey, date as NSDate)
        }
        static func withLargerSortIndex(than message: PersistedMessage) -> NSPredicate {
            NSPredicate(format: "%K > %lf", sortIndexKey, message.sortIndex)
        }
    }

    static func getPersistedMessageSent(objectID: TypeSafeManagedObjectID<PersistedMessageSent>, within context: NSManagedObjectContext) throws -> PersistedMessageSent? {
        let request: NSFetchRequest<PersistedMessageSent> = PersistedMessageSent.fetchRequest()
        request.predicate = PersistedMessage.Predicate.withObjectID(objectID.objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func getAllProcessing(within context: NSManagedObjectContext) throws -> [PersistedMessageSent] {
        let request: NSFetchRequest<PersistedMessageSent> = PersistedMessageSent.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %d",
                                        rawStatusKey, MessageStatus.processing.rawValue)
        return try context.fetch(request)
    }

    static func getAllProcessingWithinDiscussion(persistedDiscussionObjectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> [PersistedMessageSent] {
        let request: NSFetchRequest<PersistedMessageSent> = PersistedMessageSent.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %d AND %K == %@",
                                        rawStatusKey, MessageStatus.processing.rawValue,
                                        PersistedMessage.Predicate.Key.discussion.rawValue, persistedDiscussionObjectID)
        return try context.fetch(request)
    }
    
    static func get(senderSequenceNumber: Int, senderThreadIdentifier: UUID, ownedIdentity: Data, discussion: PersistedDiscussion) throws -> PersistedMessageSent? {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Could not find context")}
        let request: NSFetchRequest<PersistedMessageSent> = PersistedMessageSent.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            NSPredicate(format: "%K == %d AND %K == %@",
                        senderSequenceNumberKey, senderSequenceNumber,
                        discussionSenderThreadIdentifierKey, senderThreadIdentifier as CVarArg,
                        discussionOwnedIdentityIdentityKey, ownedIdentity as NSData),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    static func getSentMessagesThatExpired(before date: Date, within context: NSManagedObjectContext) throws -> [PersistedMessageSent] {
        let request: NSFetchRequest<PersistedMessageSent> = PersistedMessageSent.fetchRequest()
        request.predicate = Predicate.expiredBefore(date)
        request.fetchBatchSize = 1_000
        return try context.fetch(request)
    }
    
    
    /// This method fetches all outbound messages that are marked as readOnce and that have a status set to "sent".
    /// This is typically used to determine to return all the sent messages to delete when exiting a discussion.
    static func getReadOnceThatWasSent(restrictToDiscussionWithObjectID discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>?, within context: NSManagedObjectContext) throws -> [PersistedMessageSent] {
        let request: NSFetchRequest<PersistedMessageSent> = PersistedMessageSent.fetchRequest()
        var predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.readOnce,
            Predicate.wasSent,
        ])
        if let discussionObjectID = discussionObjectID {
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                predicate,
                Predicate.withinDiscussionWithObjectID(discussionObjectID)
            ])
        }
        request.predicate = predicate
        request.fetchBatchSize = 1_000
        return try context.fetch(request)
    }
    
    /// This method returns all the outbound messages within the specified discussion, such that:
    /// - They are at least in the `sent` state
    /// - They were created before the specified date.
    /// This method is typically used for deleting messages that are older than the specified retention policy.
    static func getAllSentMessagesCreatedBeforeDate(discussion: PersistedDiscussion, date: Date) throws -> [PersistedMessageSent] {
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
    
    
    /// This method returns the number of outbound messages within the specified discussion that are at least in the `sent` state.
    /// This method is typically used for later deleting messages so as to respect a count based retention policy.
    static func countAllSentMessages(discussion: PersistedDiscussion) throws -> Int {
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

    var fyleMessageJoinWithStatusesOfImageType: [SentFyleMessageJoinWithStatus] {
        fyleMessageJoinWithStatuses.filter({ Self.supportedImageTypeIdentifiers.contains($0.uti)  })
    }

    var fyleMessageJoinWithStatusesOfAudioType: [SentFyleMessageJoinWithStatus] {
        fyleMessageJoinWithStatuses.filter({ ObvUTIUtils.uti($0.uti, conformsTo: kUTTypeAudio) })
    }

    var fyleMessageJoinWithStatusesOfOtherTypes: [SentFyleMessageJoinWithStatus] {
        var result = fyleMessageJoinWithStatuses
        result.removeAll(where: { fyleMessageJoinWithStatusesOfImageType.contains($0)})
        result.removeAll(where: { fyleMessageJoinWithStatusesOfAudioType.contains($0)})
        return result
    }

}


// MARK: - Notifying on save


extension PersistedMessageSent {
    
    override func willSave() {
        super.willSave()
        
        if isUpdated {
            changedKeys = Set<String>(self.changedValues().keys)
        }
        
    }

    
    override func didSave() {
        super.didSave()
        
        // When a readOnce message is sent, we notify. This is catched by the coordinator that checks whether the user is in the message's discussion or not. If this is the case, nothing happens. Otherwise the coordiantor deletes this readOnce message.
        if changedKeys.contains(PersistedMessageSent.rawStatusKey) && self.status == .sent && self.readOnce {
            ObvMessengerCoreDataNotification.aReadOncePersistedMessageSentWasSent(persistedMessageSentObjectID: self.objectID,
                                                                                  persistedDiscussionObjectID: self.discussion.typedObjectID)
                .postOnDispatchQueue()
        }

    }
    
}

extension TypeSafeManagedObjectID where T == PersistedMessageSent {
    var downcast: TypeSafeManagedObjectID<PersistedMessage> {
        TypeSafeManagedObjectID<PersistedMessage>(objectID: objectID)
    }
}
