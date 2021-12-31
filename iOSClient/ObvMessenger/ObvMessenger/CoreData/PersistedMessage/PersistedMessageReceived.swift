/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import UniformTypeIdentifiers
import MobileCoreServices


@objc(PersistedMessageReceived)
final class PersistedMessageReceived: PersistedMessage {
    
    private static let entityName = "PersistedMessageReceived"

    private static let contactIdentityKey = "contactIdentity"
    private static let contactIdentityIdentityKey = [contactIdentityKey, PersistedObvContactIdentity.identityKey].joined(separator: ".")
    private static let messageIdentifierFromEngineKey = "messageIdentifierFromEngine"
    private static let senderThreadIdentifierKey = "senderThreadIdentifier"
    private static let expirationForReceivedLimitedVisibilityKey = "expirationForReceivedLimitedVisibility"
    private static let expirationForReceivedLimitedExistenceKey = "expirationForReceivedLimitedExistence"
    private static let ownedIdentityKey = [contactIdentityKey, PersistedObvContactIdentity.rawOwnedIdentityKey].joined(separator: ".")

    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "PersistedMessageReceived")
    
    private static func makeError(message: String) -> Error { NSError(domain: String(describing: Self.self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { Self.makeError(message: message) }

    /// At reception, a message is marked as `new`. When it is displayed to the user, it is marked as `unread` if `readOnce` is `true` and to `read` otherwise. An unread message for which `readOnce` is `true` is marked as `read` as soon as the user reads it. In that case, the message is deleted as soon as the user exits the discussion.
    enum MessageStatus: Int {
        case new = 0
        case unread = 2
        case read = 1
    }

    // MARK: - Attributes

    @NSManaged private(set) var messageIdentifierFromEngine: Data
    @NSManaged private(set) var senderIdentifier: Data
    @NSManaged private(set) var senderThreadIdentifier: UUID
    @NSManaged private var serializedReturnReceipt: Data?
    @NSManaged private(set) var missedMessageCount: Int

    // MARK: - Relationships
    
    @NSManaged private(set) var contactIdentity: PersistedObvContactIdentity?
    @NSManaged private(set) var expirationForReceivedLimitedVisibility: PersistedExpirationForReceivedMessageWithLimitedVisibility?
    @NSManaged private(set) var expirationForReceivedLimitedExistence: PersistedExpirationForReceivedMessageWithLimitedExistence?
    @NSManaged private var unsortedFyleMessageJoinWithStatus: Set<ReceivedFyleMessageJoinWithStatus>

    // MARK: - Computed variables

    override var initialExistenceDuration: TimeInterval? {
        guard let existenceExpiration = expirationForReceivedLimitedExistence else { return nil }
        return existenceExpiration.initialExpirationDuration
    }
    
    override var earliestExpiration: PersistedMessageExpiration? {
        PersistedMessageExpiration.getEarliestExpiration(self.expirationForReceivedLimitedExistence, self.expirationForReceivedLimitedVisibility)
    }

    private(set) var status: MessageStatus {
        get { return MessageStatus(rawValue: self.rawStatus)! }
        set {
            guard self.status != newValue else { return }
            self.rawStatus = newValue.rawValue
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

    var fyleMessageJoinWithStatuses: [ReceivedFyleMessageJoinWithStatus] {
        switch unsortedFyleMessageJoinWithStatus.count {
        case 0:
            return []
        case 1:
            return [unsortedFyleMessageJoinWithStatus.first!]
        default:
            return unsortedFyleMessageJoinWithStatus.sorted(by: { $0.numberFromEngine < $1.numberFromEngine })
        }
    }
    
    private var userInfoForDeletion: [String: Any]?
    
    var returnReceipt: ReturnReceiptJSON? {
        guard let serializedReturnReceipt = self.serializedReturnReceipt else { return nil }
        do {
            return try ReturnReceiptJSON.decode(serializedReturnReceipt)
        } catch let error {
            os_log("Could not decode a return receipt of a received message: %{public}@", log: PersistedMessageReceived.log, type: .fault, error.localizedDescription)
            return nil
        }
    }

    private var changedKeys = Set<String>()

    var isEphemeralMessage: Bool {
        self.readOnce || self.visibilityDuration != nil || self.initialExistenceDuration != nil
    }
 
    var isEphemeralMessageWithUserAction: Bool {
        self.readOnce || self.visibilityDuration != nil
    }

    /// Called when a received message was globally wiped
    func wipe(requester: PersistedObvContactIdentity) throws {
        guard !isRemoteWiped else { return }
        for join in fyleMessageJoinWithStatuses {
            join.wipe()
        }
        self.deleteBody()
        let remoteCryptoId = requester.cryptoId
        try addMetadata(kind: .remoteWiped(remoteCryptoId: remoteCryptoId), date: Date())
    }

    
    func editTextBody(newTextBody: String?, requester: ObvCryptoId, messageUploadTimestampFromServer: Date) throws {
        guard self.contactIdentity?.cryptoId == requester else { throw makeError(message: "The requester is not the contact who created the original message") }
        try super.editTextBody(newTextBody: newTextBody)
        try deleteMetadataOfKind(.edited)
        try addMetadata(kind: .edited, date: messageUploadTimestampFromServer)
    }

    func updateMissedMessageCount(with missedMessageCount: Int) {
        self.missedMessageCount = missedMessageCount
    }
}


// MARK: - Initializer

extension PersistedMessageReceived {
    
    convenience init?(messageUploadTimestampFromServer: Date, downloadTimestampFromServer: Date, localDownloadTimestamp: Date, messageJSON: MessageJSON, contactIdentity: PersistedObvContactIdentity, messageIdentifierFromEngine: Data, returnReceiptJSON: ReturnReceiptJSON?, missedMessageCount: Int, discussion: PersistedDiscussion) throws {
        
        guard let context = discussion.managedObjectContext else { return nil }
        
        if let discussion = discussion as? PersistedGroupDiscussion {
            // We check that the received message comes from a member (likely) or a pending member (unlikely, but still)
            guard let contactGroup = discussion.contactGroup else {
                os_log("Could find contact group (this is ok if it was just deleted)", log: PersistedMessageReceived.log, type: .error)
                return nil
            }
            let pendingMembersCryptoIds = contactGroup.pendingMembers.map { $0.cryptoId }
            guard contactGroup.contactIdentities.contains(contactIdentity) || pendingMembersCryptoIds.contains(contactIdentity.cryptoId) else {
                os_log("The PersistedGroupDiscussion list of contacts does not contain the contact that sent a message within this discussion", log: PersistedMessageReceived.log, type: .error)
                return nil
            }
        } else if let discussion = discussion as? PersistedOneToOneDiscussion {
            guard discussion.contactIdentity == contactIdentity else {
                return nil
            }
        }
        
        guard let (sortIndex, adjustedTimestamp) = try? PersistedMessageReceived.determineAppropriateSortIndex(forSenderSequenceNumber: messageJSON.senderSequenceNumber,
                                                                                                               senderThreadIdentifier: messageJSON.senderThreadIdentifier,
                                                                                                               contactIdentity: contactIdentity,
                                                                                                               timestamp: messageUploadTimestampFromServer,
                                                                                                               within: discussion) else { return nil }

        self.init(timestamp: adjustedTimestamp,
                  body: messageJSON.body,
                  rawStatus: MessageStatus.new.rawValue,
                  senderSequenceNumber: messageJSON.senderSequenceNumber,
                  sortIndex: sortIndex,
                  replyToJSON: messageJSON.replyTo,
                  discussion: discussion,
                  readOnce: messageJSON.expiration?.readOnce ?? false,
                  visibilityDuration: messageJSON.expiration?.visibilityDuration,
                  forEntityName: PersistedMessageReceived.entityName,
                  within: context)

        self.contactIdentity = contactIdentity
        self.senderIdentifier = contactIdentity.cryptoId.getIdentity()
        self.senderThreadIdentifier = messageJSON.senderThreadIdentifier
        self.serializedReturnReceipt = try returnReceiptJSON?.encode()
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

    }
    
    func update(withMessageJSON json: MessageJSON, messageIdentifierFromEngine: Data, returnReceiptJSON: ReturnReceiptJSON?, messageUploadTimestampFromServer: Date, downloadTimestampFromServer: Date, localDownloadTimestamp: Date, discussion: PersistedDiscussion) throws {
        guard self.messageIdentifierFromEngine == messageIdentifierFromEngine else {
            throw makeError(message: "Invalid message identifier from engine")
        }
        try self.update(body: json.body,
                        senderSequenceNumber: json.senderSequenceNumber,
                        replyToJSON: json.replyTo,
                        discussion: discussion)
        do {
            self.serializedReturnReceipt = try returnReceiptJSON?.encode()
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

    
    func allowReading(now: Date) throws {
        assert(isEphemeralMessageWithUserAction)
        assert(AppStateManager.shared.currentState.isInitializedAndActive)
        guard AppStateManager.shared.currentState.isInitializedAndActive else { return }
        guard isEphemeralMessageWithUserAction else { assertionFailure("There is not reason why this is called on a message that is not marked as readOnce or with a certain visibility"); return }
        try self.markAsRead(now: now)
    }

    /// This allows to prevent auto-read for messages received with a more restrictive ephemerality than that of the discussion.
    var ephemeralityIsAtLeastAsPermissiveThanDiscussionSharedConfiguration: Bool {
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

// MARK: - Other methods

extension PersistedMessageReceived {

    func markAsNotNew(now: Date) throws {
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
        
    
    var readingRequiresUserAction: Bool {
        guard isEphemeralMessageWithUserAction else { return false }
        switch self.status {
        case .new, .unread:
            return true
        case .read:
            return false
        }
    }

}


// MARK: - Convenience DB getters

extension PersistedMessageReceived {
    
    struct Predicate {
        static var isNew: NSPredicate { NSPredicate(format: "%K == %d", PersistedMessageReceived.rawStatusKey, MessageStatus.new.rawValue) }
        static var isUnread: NSPredicate { NSPredicate(format: "%K == %d", PersistedMessageReceived.rawStatusKey, MessageStatus.unread.rawValue) }
        static var isRead: NSPredicate { NSPredicate(format: "%K == %d", PersistedMessageReceived.rawStatusKey, MessageStatus.read.rawValue) }
        static var isNotNewAnymore: NSPredicate { NSPredicate(format: "%K > %d", PersistedMessageReceived.rawStatusKey, MessageStatus.new.rawValue) }
        static func inDiscussion(_ discussion: PersistedDiscussion) -> NSPredicate { NSPredicate(format: "%K == %@", PersistedMessageReceived.discussionKey, discussion) }
        static func inDiscussionWithObjectID(_ discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) -> NSPredicate { NSPredicate(format: "%K == %@", PersistedMessageReceived.discussionKey, discussionObjectID.objectID) }
        static var readOnce: NSPredicate { NSPredicate(format: "%K == TRUE", PersistedMessage.readOnceKey) }
        static func forOwnedIdentity(_ ownedIdentity: PersistedObvOwnedIdentity) -> NSPredicate { NSPredicate(format: "%K == %@", PersistedMessageReceived.ownedIdentityKey, ownedIdentity) }
        static var expiresForReceivedLimitedVisibility: NSPredicate {
            NSPredicate(format: "\(PersistedMessageReceived.expirationForReceivedLimitedVisibilityKey) != NIL")
        }
        static var expiresForReceivedLimitedExistence: NSPredicate {
            NSPredicate(format: "\(PersistedMessageReceived.expirationForReceivedLimitedExistenceKey) != NIL")
        }
        static var hasVisibilityDuration: NSPredicate {
            NSPredicate(format: "\(PersistedMessageReceived.rawVisibilityDurationKey) != NIL")
        }
        static var expiredBeforeNow: NSPredicate {
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    expiresForReceivedLimitedVisibility,
                    NSPredicate(format: "\(PersistedMessageReceived.expirationForReceivedLimitedVisibilityKey).\(PersistedMessageExpiration.expirationDateKey) < %@", Date() as NSDate),
                ]),
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    expiresForReceivedLimitedExistence,
                    NSPredicate(format: "\(PersistedMessageReceived.expirationForReceivedLimitedExistenceKey).\(PersistedMessageExpiration.expirationDateKey) < %@", Date() as NSDate),
                ]),
            ])
        }
        static func createdBefore(date: Date) -> NSPredicate {
            return NSPredicate(format: "%K < %@", timestampKey, date as NSDate)
        }
        static func withLargerSortIndex(than message: PersistedMessage) -> NSPredicate {
            NSPredicate(format: "%K > %lf", sortIndexKey, message.sortIndex)
        }
        static var isDisussionUnmuted: NSPredicate {
            return NSPredicate(format: "%K == nil OR %K < %@", muteNotificationsEndDateKey, muteNotificationsEndDateKey, Date() as NSDate)
        }
        static func withObjectID(_ objectID: NSManagedObjectID) -> NSPredicate {
            NSPredicate(format: "self == %@", objectID)
        }
    }
    
    

    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedMessageReceived> {
        return NSFetchRequest<PersistedMessageReceived>(entityName: PersistedMessageReceived.entityName)
    }

    static func get(with objectID: TypeSafeManagedObjectID<PersistedMessageReceived>, within context: NSManagedObjectContext) throws -> PersistedMessageReceived? {
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = Predicate.withObjectID(objectID.objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func getNextMessageBySenderSequenceNumber(_ sequenceNumber: Int, senderThreadIdentifier: UUID, contactIdentity: PersistedObvContactIdentity, within discussion: PersistedDiscussion) -> PersistedMessageReceived? {
        guard let context = discussion.managedObjectContext else { return nil }
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@ AND %K == %@ AND %K > %d",
                                        discussionKey, discussion,
                                        contactIdentityKey, contactIdentity,
                                        senderThreadIdentifierKey, senderThreadIdentifier as CVarArg,
                                        senderSequenceNumberKey, sequenceNumber)
        request.sortDescriptors = [NSSortDescriptor(key: senderSequenceNumberKey, ascending: true)]
        request.fetchLimit = 1
        do { return try context.fetch(request).first } catch { return nil }
    }

    
    static func getPreviousMessageBySenderSequenceNumber(_ sequenceNumber: Int, senderThreadIdentifier: UUID, contactIdentity: PersistedObvContactIdentity, within discussion: PersistedDiscussion) -> PersistedMessageReceived? {
        guard let context = discussion.managedObjectContext else { return nil }
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@ AND %K == %@ AND %K < %d",
                                        discussionKey, discussion,
                                        contactIdentityKey, contactIdentity,
                                        senderThreadIdentifierKey, senderThreadIdentifier as CVarArg,
                                        senderSequenceNumberKey, sequenceNumber)
        request.sortDescriptors = [NSSortDescriptor(key: senderSequenceNumberKey, ascending: false)]
        request.fetchLimit = 1
        do { return try context.fetch(request).first } catch { return nil }
    }

    
    /// Each message of the discussion that is in the status `new` changes status as follows:
    /// - If the message is such that `hasWipeAfterRead` is `true`, the new status is `unread`
    /// - Otherwise, the new status is `read`.
    static func markAllAsNotNew(within discussion: PersistedDiscussion) throws {
        os_log("Call to markAllAsNotNew in PersistedMessageReceived for discussion %{public}@", log: log, type: .debug, discussion.objectID.debugDescription)
        guard let context = discussion.managedObjectContext else { return }
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.includesSubentities = true
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [Predicate.inDiscussion(discussion), Predicate.isNew])
        let messages = try context.fetch(request)
        guard !messages.isEmpty else { return }
        let now = Date()
        try messages.forEach {
            try $0.markAsNotNew(now: now)
        }
    }


    static func getAllReadOnceThatAreRead(within context: NSManagedObjectContext) throws -> Set<PersistedMessageReceived> {
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.isRead,
            Predicate.readOnce,
        ])
        let messages = try context.fetch(request)
        return Set(messages)
    }
    
    
    static func countNew(for ownedIdentity: PersistedObvOwnedIdentity) throws -> Int {
        guard let context = ownedIdentity.managedObjectContext else { throw NSError() }
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                                                    Predicate.isNew,
                                                    Predicate.isDisussionUnmuted,
                                                    Predicate.forOwnedIdentity(ownedIdentity)])
        return try context.count(for: request)
    }

    
    static func countNew(within discussion: PersistedDiscussion) throws -> Int {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Could not find context") }
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                                                    Predicate.isNew,
                                                    Predicate.isDisussionUnmuted,
                                                    Predicate.inDiscussion(discussion)])
        return try context.count(for: request)
    }

    
    static func countNewForAllOwnedIdentities(within context: NSManagedObjectContext) throws -> Int {
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                                                    Predicate.isNew,
                                                    Predicate.isDisussionUnmuted])
        return try context.count(for: request)
    }

    
    /// This method returns "all" the received messages with the given identifier from engine. In practice, we do not expect more than on message within the array.
    static func getAll(messageIdentifierFromEngine: Data, within context: NSManagedObjectContext) throws -> [PersistedMessageReceived] {
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", messageIdentifierFromEngineKey, messageIdentifierFromEngine as CVarArg)
        request.fetchBatchSize = 10
        return try context.fetch(request)
    }
    
    static func get(messageIdentifierFromEngine: Data, from contact: ObvContactIdentity, within context: NSManagedObjectContext) throws -> PersistedMessageReceived? {
        guard let persistedContact = try? PersistedObvContactIdentity.get(persisted: contact, within: context) else { return nil }
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                        messageIdentifierFromEngineKey, messageIdentifierFromEngine as CVarArg,
                                        contactIdentityKey, persistedContact)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    static func get(messageIdentifierFromEngine: Data, from persistedContact: PersistedObvContactIdentity) -> PersistedMessageReceived? {
        guard let context = persistedContact.managedObjectContext else { return nil }
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                        messageIdentifierFromEngineKey, messageIdentifierFromEngine as CVarArg,
                                        contactIdentityKey, persistedContact)
        request.fetchLimit = 1
        do { return try context.fetch(request).first } catch { return nil }
    }

    static func get(senderSequenceNumber: Int, senderThreadIdentifier: UUID, contactIdentity: Data, discussion: PersistedDiscussion) throws -> PersistedMessageReceived? {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Could not find context") }
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.inDiscussion(discussion),
            NSPredicate(format: "%K == %d AND %K == %@ AND %K == %@",
                        senderSequenceNumberKey, senderSequenceNumber,
                        senderThreadIdentifierKey, senderThreadIdentifier as CVarArg,
                        contactIdentityIdentityKey, contactIdentity as NSData)
        ])
        request.fetchLimit = 1
        do { return try context.fetch(request).first } catch { return nil }
    }
    
    static func getAllNew(with context: NSManagedObjectContext) throws -> [PersistedMessageReceived] {
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = Predicate.isNew
        return try context.fetch(request)
    }
    
    static func getAllNew(in discussion: PersistedDiscussion) throws -> [PersistedMessageReceived] {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Could not find context in discussion object") }
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.inDiscussion(discussion),
            Predicate.isNew,
        ])
        return try context.fetch(request)
    }
    
    static func getFirstNew(in discussion: PersistedDiscussion) throws -> PersistedMessageReceived? {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Could not find context in discussion")}
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.inDiscussion(discussion),
            Predicate.isNew,
        ])
        request.sortDescriptors = [NSSortDescriptor(key: sortIndexKey, ascending: true)]
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    static func getPersistedMessageReceived(with objectID: NSManagedObjectID, within context: NSManagedObjectContext) -> PersistedMessageReceived? {
        let persistedMessageReceived: PersistedMessageReceived
        do {
            guard let res = try context.existingObject(with: objectID) as? PersistedMessageReceived else { throw NSError() }
            persistedMessageReceived = res
        } catch {
            return nil
        }
        return persistedMessageReceived
    }

    
    static func getReceivedMessagesThatExpired(within context: NSManagedObjectContext) throws -> [PersistedMessageReceived] {
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = Predicate.expiredBeforeNow
        request.fetchBatchSize = 1_000
        return try context.fetch(request)
    }

    
    /// This method fetches all inbound messages that are marked as readOnce and that have a status set to "read".
    /// This is typically used to return all the received messages to delete when exiting a discussion.
    static func getReadOnceMarkedAsRead(restrictToDiscussionWithObjectID discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>?, within context: NSManagedObjectContext) throws -> [PersistedMessageReceived] {
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        var predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.readOnce,
            Predicate.isRead,
        ])
        if let discussionObjectID = discussionObjectID {
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                predicate,
                Predicate.inDiscussionWithObjectID(discussionObjectID)
            ])
        }
        request.predicate = predicate
        request.fetchBatchSize = 1_000
        return try context.fetch(request)
    }

    /// This method returns all outbound messages within the specified discussion, such that :
    /// - The message was created before the specified date
    /// - The message is not new anymore (thus, either unread or read)
    /// This method is typically used for deleting messages that are older than the specified retention policy.
    static func getAllNonNewReceivedMessagesCreatedBeforeDate(discussion: PersistedDiscussion, date: Date) throws -> [PersistedMessageReceived] {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Cannot find context in PersistedDiscussion") }
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.inDiscussion(discussion),
            Predicate.createdBefore(date: date),
            Predicate.isNotNewAnymore,
        ])
        request.fetchBatchSize = 1_000
        return try context.fetch(request)
    }
    
    
    /// This method returns the number of inbound messages of the discussion that are not new (thus either unread or read).
    /// This method is typically used for later deleting messages so as to respect a count based retention policy.
    static func countAllNonNewMessages(discussion: PersistedDiscussion) throws -> Int {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Cannot find context in PersistedDiscussion") }
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.inDiscussion(discussion),
            Predicate.isNotNewAnymore,
        ])
        return try context.count(for: request)
    }
    
    /// This method returns the number of inbound messages of the discussion that are not new (thus either unread or read) and
    /// that occur after the message passed as a parameter.
    /// This method is typically used for displaying count based retention information for a specific message.
    static func countAllSentMessages(after messageObjectID: NSManagedObjectID, discussion: PersistedDiscussion) throws -> Int {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Cannot find context in PersistedDiscussion") }
        guard let message = try PersistedMessage.get(with: messageObjectID, within: context) else {
            throw makeError(message: "Cannot find message to compare to")
        }
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.inDiscussion(discussion),
            Predicate.isNotNewAnymore,
            Predicate.withLargerSortIndex(than: message),
        ])
        return try context.count(for: request)
    }
    
    
    static func getAllReceivedMessagesThatRequireUserActionForReading(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, within context: NSManagedObjectContext) throws -> [PersistedMessageReceived] {
        let request: NSFetchRequest<PersistedMessageReceived> = PersistedMessageReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.inDiscussionWithObjectID(discussionObjectID),
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
    
    var supportedImageTypeIdentifiers: Set<String> {
        Set<String>(([UTType.jpeg.identifier, UTType.png.identifier, UTType.gif.identifier]))
    }
    
    var fyleMessageJoinWithStatusesOfImageType: [ReceivedFyleMessageJoinWithStatus] {
        fyleMessageJoinWithStatuses.filter({ supportedImageTypeIdentifiers.contains($0.uti)  })
    }

    var fyleMessageJoinWithStatusesOfAudioType: [ReceivedFyleMessageJoinWithStatus] {
        fyleMessageJoinWithStatuses.filter({                                            ObvUTIUtils.uti($0.uti, conformsTo: kUTTypeAudio) })
    }

    var fyleMessageJoinWithStatusesOfOtherTypes: [ReceivedFyleMessageJoinWithStatus] {
        var result = fyleMessageJoinWithStatuses
        result.removeAll(where: { fyleMessageJoinWithStatusesOfImageType.contains($0)})
        result.removeAll(where: { fyleMessageJoinWithStatusesOfAudioType.contains($0)})
        return result
    }

}


// MARK: - Sending notifications on change

extension PersistedMessageReceived {

    override func prepareForDeletion() {
        super.prepareForDeletion()
        // Note that the following line may return nil if we are currently deleting a message that is part of a locked discussion.
        // In that case, we do not notify that the message is being deleted, but this is not an issue at this time
        guard let ownedCryptoId = contactIdentity?.ownedIdentity?.cryptoId else { return }
        userInfoForDeletion = ["objectID": objectID,
                               "messageIdentifierFromEngine": messageIdentifierFromEngine,
                               "ownedCryptoId": ownedCryptoId,
                               "sortIndex": sortIndex,
                               "discussionObjectID": discussion.typedObjectID]
    }
    
    override func willSave() {
        super.willSave()
        if isUpdated {
            changedKeys = Set<String>(self.changedValues().keys)
        }
    }
    
    override func didSave() {
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
            ObvMessengerInternalNotification.persistedMessageReceivedWasDeleted(objectID: objectID, messageIdentifierFromEngine: messageIdentifierFromEngine, ownedCryptoId: ownedCryptoId, sortIndex: sortIndex, discussionObjectID: discussionObjectID)
                .postOnDispatchQueue()
            
        } else if (self.changedKeys.contains(PersistedMessageReceived.rawStatusKey) || isInserted) && self.status == .read {
            ObvMessengerInternalNotification.persistedMessageReceivedWasRead(persistedMessageReceivedObjectID: self.objectID)
                .postOnDispatchQueue()
        }
        
        if self.changedKeys.contains(PersistedMessage.bodyKey) {
            ObvMessengerInternalNotification.theBodyOfPersistedMessageReceivedDidChange(persistedMessageReceivedObjectID: self.objectID)
                .postOnDispatchQueue()
        }
    }
}

extension TypeSafeManagedObjectID where T == PersistedMessageReceived {
    var downcast: TypeSafeManagedObjectID<PersistedMessage> {
        TypeSafeManagedObjectID<PersistedMessage>(objectID: objectID)
    }
}
