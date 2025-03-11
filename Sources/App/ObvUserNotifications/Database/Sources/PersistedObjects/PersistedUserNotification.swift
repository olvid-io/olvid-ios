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
import ObvCrypto
import ObvTypes
import ObvAppTypes
import ObvUserNotificationsTypes


/// Persists `ObvMessages` and associated data when considering a received message or a received reaction leading to a remote or local user notification.
@objc(PersistedUserNotification)
public final class PersistedUserNotification: NSManagedObject {
    
    private static let entityName = "PersistedUserNotification"
    
    // MARK: - Attributes
    
    @NSManaged private var messageUploadTimestampFromServer: Date? // Expected to be non-nil
    @NSManaged private var rawCreator: NSNumber? // Expected to be non-nil, either the app or the notification extension
    @NSManaged private var rawKind: NSNumber? // A PersistedUserNotification is either about a received message or a reaction on a sent message
    @NSManaged private var rawMessageIdFromServer: Data? // Expected to be non-nil, part of the "primary key". It's the
    @NSManaged private var rawObvContactIdentifier: String? // Expected to be non-nil. It's the sender when considering a received message, and the person who reacted in case of a reaction on a sent message
    @NSManaged private var rawObvDiscussionIdentifier: String? // Expected to be non-nil
    @NSManaged private var rawObvMessageAppIdentifier: String? // Expected to be non-nil. It's the received message identifier when considering a received message, and the message reacted-to when considering a reaction
    @NSManaged private var rawOwnedIdentity: Data? // Expected to be non-nil, part of the "primary key"
    @NSManaged private var rawStatus: NSNumber? // Expected to be non-nil
    @NSManaged private var rawUserNotificationCategory: String?
    @NSManaged private var requestIdentifier: String?  // Expected to be non-nil, must be unique. When the notification request comes from the notification extension, this is forced by the OS.
    
    // MARK: - Relationships
    
    @NSManaged private var rawObvMessage: PersistedObvMessage? // Expected to be non-nil when the status is `initial`, nil otherwise
    @NSManaged private var rawObvMessageUpdate: PersistedObvMessage? // Most often nil, store the latest update received about the rawObvMessage (e.g., update text body for a received message)
    
    // MARK: - Accessors
    
    private enum Kind: Int {
        case receivedMessage = 0
        case reactionOnSentMessage = 1
    }
    
    public enum Status: Int {
        case shown = 0 // Default status set at creation
        case removed = 1
    }
    
    /// Expected to be non-nil
    private(set) var userNotificationCategory: ObvUserNotificationCategoryIdentifier? {
        get {
            guard let rawUserNotificationCategory,
                  let userNotificationCategory = ObvUserNotificationCategoryIdentifier(rawValue: rawUserNotificationCategory) else {
                assertionFailure()
                return nil
            }
            return userNotificationCategory
        }
        set {
            guard let newValue else { assertionFailure(); return }
            if self.rawUserNotificationCategory != newValue.rawValue {
                self.rawUserNotificationCategory = newValue.rawValue
            }
        }
    }
    
    /// Expected to be non-nil. It's the received message identifier, or the reacted-to message identifier.
    var messageAppIdentifier: ObvMessageAppIdentifier? {
        guard let rawObvMessageAppIdentifier,
              let messageAppIdentifier = ObvMessageAppIdentifier(rawObvMessageAppIdentifier) else {
            assertionFailure("We should not be trying to access this getter. Note that it is always nil for a received reaction")
            return nil
        }
        return messageAppIdentifier
    }
    
    private func setObvMessageAppIdentifier(to newValue: ObvMessageAppIdentifier) {
        if self.rawObvMessageAppIdentifier != newValue.description {
            self.rawObvMessageAppIdentifier = newValue.description
        }
    }
    
    /// Expected to be non-nil
    var discussionIdentifier: ObvDiscussionIdentifier? {
        guard let rawObvDiscussionIdentifier,
              let discussionIdentifier = ObvDiscussionIdentifier(rawObvDiscussionIdentifier) else {
            assertionFailure()
            return nil
        }
        return discussionIdentifier
    }
    
    private func setObvDiscussionIdentifier(to newValue: ObvDiscussionIdentifier) {
        if self.rawObvDiscussionIdentifier != newValue.description {
            self.rawObvDiscussionIdentifier = newValue.description
        }
    }
    
    
    private(set) var status: Status {
        get {
            guard let rawValue = rawStatus?.intValue,
                  let status = Status(rawValue: rawValue) else { assertionFailure(); return .shown }
            return status
        }
        set {
            guard self.status != newValue else { return }
            self.rawStatus = NSNumber(integerLiteral: newValue.rawValue)
        }
    }
    

    /// The only status that can be changed is the `.shown` status.
    private func setStatus(to newStatus: Status) {
        if self.status != newStatus && self.status == .shown {
            self.status = newStatus
        }
        if self.status != .shown {
            removeObvMessage()
        }
    }
    
    
    private func removeObvMessage() {
        if self.rawObvMessage != nil {
            do {
                try self.rawObvMessage?.deletePersistedObvMessage()
            } catch {
                assertionFailure(error.localizedDescription)
            }
            self.rawObvMessage = nil
            do {
                try self.rawObvMessageUpdate?.deletePersistedObvMessage()
            } catch {
                assertionFailure(error.localizedDescription)
            }
            self.rawObvMessageUpdate = nil
        }
    }
    
    
    var messageIdFromServer: UID {
        get throws {
            guard let rawMessageIdFromServer else {
                throw ObvError.rawMessageIdFromServerIsNil
            }
            guard let uid = UID(uid: rawMessageIdFromServer) else {
                throw ObvError.couldNotParseMessageIdFromServer
            }
            return uid
        }
    }
    
    
    var ownedCryptoId: ObvCryptoId {
        get throws {
            guard let rawOwnedIdentity else {
                assertionFailure()
                throw ObvError.rawOwnedIdentityIsNil
            }
            return try ObvCryptoId(identity: rawOwnedIdentity)
        }
    }
    
    
    public enum Creator: Int {
        case notificationExtension = 0
        case mainApp = 1
    }
    
    
    var creator: Creator {
        guard let rawValue = rawCreator?.intValue,
              let creator = Creator(rawValue: rawValue) else {
            assertionFailure()
            return .mainApp
        }
        return creator
    }
    
    
    // MARK: - Initializer
    
    private convenience init(Kind: Kind, creator: Creator, requestIdentifier: String, obvMessage: ObvMessage, messageAppIdentifier: ObvMessageAppIdentifier, reactor: ObvContactIdentifier?, userNotificationCategory: ObvUserNotificationCategoryIdentifier, within context: NSManagedObjectContext) throws {
        
        let entityDescription = NSEntityDescription.entity(forEntityName: Self.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        assert(reactor != nil || messageAppIdentifier.contactIdentifier != nil)
        
        self.rawCreator = NSNumber(integerLiteral: creator.rawValue)
        self.requestIdentifier = requestIdentifier
        self.rawMessageIdFromServer = obvMessage.messageId.uid.raw
        self.rawOwnedIdentity = obvMessage.fromContactIdentity.ownedCryptoId.getIdentity()
        self.rawStatus = NSNumber(integerLiteral: Status.shown.rawValue)
        self.rawObvContactIdentifier = reactor?.description ?? messageAppIdentifier.contactIdentifier?.description
        self.rawObvDiscussionIdentifier = messageAppIdentifier.discussionIdentifier.description
        self.rawObvMessageAppIdentifier = messageAppIdentifier.description
        self.rawUserNotificationCategory = userNotificationCategory.rawValue
        self.messageUploadTimestampFromServer = obvMessage.messageUploadTimestampFromServer
        self.rawKind = NSNumber(integerLiteral: Kind.rawValue)
        
        self.rawObvMessage = try PersistedObvMessage.createContent(obvMessage: obvMessage, within: context)
        self.rawObvMessageUpdate = nil // Only set if the message sender update her message, or when the reactor updates her reaction.
        
    }
    
    
    public static func createForReceivedMessage(creator: Creator, requestIdentifier: String, obvMessage: ObvMessage, receivedMessageAppIdentifier: ObvMessageAppIdentifier, userNotificationCategory: ObvUserNotificationCategoryIdentifier, within context: NSManagedObjectContext) throws -> Self {
        assert(userNotificationCategory == .newMessage || userNotificationCategory == .newMessageWithLimitedVisibility || userNotificationCategory == .newMessageWithHiddenContent)
        return try self.init(Kind: .receivedMessage,
                             creator: creator,
                             requestIdentifier: requestIdentifier,
                             obvMessage: obvMessage,
                             messageAppIdentifier: receivedMessageAppIdentifier,
                             reactor: nil, // Makes no sense for a notification about a received message
                             userNotificationCategory: userNotificationCategory,
                             within: context)
    }

    
    public static func createForReactionOnSentMessage(creator: Creator, requestIdentifier: String, obvMessage: ObvMessage, sentMessageReactedTo: ObvMessageAppIdentifier, reactor: ObvContactIdentifier, userNotificationCategory: ObvUserNotificationCategoryIdentifier, within context: NSManagedObjectContext) throws -> Self {
        assert(sentMessageReactedTo.isSent)
        assert(userNotificationCategory == .newReaction)
        return try self.init(Kind: .reactionOnSentMessage,
                             creator: creator,
                             requestIdentifier: requestIdentifier,
                             obvMessage: obvMessage,
                             messageAppIdentifier: sentMessageReactedTo,
                             reactor: reactor,
                             userNotificationCategory: userNotificationCategory,
                             within: context)
    }

    
    /// When the app is launched, we persist the `ObvMessages` contained in persisted user notification. Each time such an `ObvMessage` is persisted, we call this method.
    /// This allows not to try to persist it again.
    private func markObvMessageAndObvMessageUpdateAsPersistedInApp() {
        rawObvMessage?.markAsPersistedInApp()
        rawObvMessageUpdate?.markAsPersistedInApp()
    }
    
}


// MARK: - Deletion

extension PersistedUserNotification {
    
    private func deletePersistedUserNotification() throws {
        guard let managedObjectContext else { assertionFailure(); throw ObvError.contentIsNil }
        try self.rawObvMessage?.deletePersistedObvMessage()
        try self.rawObvMessageUpdate?.deletePersistedObvMessage()
        managedObjectContext.delete(self)
    }
    
}


// MARK: - Convenience DB getters

extension PersistedUserNotification {
    
    private struct Predicate {
        enum Key: String {
            // Properties
            case messageUploadTimestampFromServer = "messageUploadTimestampFromServer"
            case rawIsCreatedByNotificationExtension = "rawIsCreatedByNotificationExtension"
            case rawKind = "rawKind"
            case rawMessageIdFromServer = "rawMessageIdFromServer"
            case rawObvDiscussionIdentifier = "rawObvDiscussionIdentifier"
            case rawObvContactIdentifier = "rawObvContactIdentifier"
            case rawObvMessageAppIdentifier = "rawObvMessageAppIdentifier"
            case rawOwnedIdentity = "rawOwnedIdentity"
            case rawStatus = "rawStatus"
            case rawUserNotificationCategory = "rawUserNotificationCategory"
            case requestIdentifier = "requestIdentifier"
            // Relationships
            case rawObvMessage = "rawObvMessage"
            case rawObvMessageUpdate = "rawObvMessageUpdate"
        }
        static func withObvContactIdentifier(_ contactIdentifier: ObvContactIdentifier) -> NSPredicate {
            return .init(Key.rawObvContactIdentifier, EqualToString: contactIdentifier.description)
        }
        static func forKind(_ kind: Kind) -> NSPredicate {
            .init(Key.rawKind, EqualToInt: kind.rawValue)
        }
        static func withRequestIdentifier(requestIdentifier: String) -> NSPredicate {
            .init(Key.requestIdentifier, EqualToString: requestIdentifier)
        }
        static func withOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> NSPredicate {
            .init(Key.rawOwnedIdentity, EqualToData: ownedCryptoId.getIdentity())
        }
        static func withMessageIdFromServer(_ messageIdFromServer: UID) -> NSPredicate {
            .init(Key.rawMessageIdFromServer, EqualToData: messageIdFromServer.raw)
        }
        static func withUserNotificationCategory(_ userNotificationCategory: ObvUserNotificationCategoryIdentifier) -> NSPredicate {
            .init(Key.rawUserNotificationCategory, EqualToString: userNotificationCategory.rawValue)
        }
        static func withObvDiscussionIdentifier(_ obvDiscussionIdentifier: ObvDiscussionIdentifier) -> NSPredicate {
            .init(Key.rawObvDiscussionIdentifier, EqualToString: obvDiscussionIdentifier.description)
        }
        static func withObvMessageAppIdentifier(_ obvMessageAppIdentifier: ObvMessageAppIdentifier) -> NSPredicate {
            .init(Key.rawObvMessageAppIdentifier, EqualToString: obvMessageAppIdentifier.description)
        }
        static func withStatus(_ status: Status) -> NSPredicate {
            .init(Key.rawStatus, EqualToInt: status.rawValue)
        }
        static var nonNilObvMessage: NSPredicate {
            .init(withNonNilValueForKey: Key.rawObvMessage)
        }
        static var nonNilObvMessageUpdate: NSPredicate {
            .init(withNonNilValueForKey: Key.rawObvMessageUpdate)
        }
        static var obvMessageNotYetPersistedByApp: NSPredicate {
            let key = [Key.rawObvMessage.rawValue, PersistedObvMessage.Predicate.Key.wasPersistedInApp.rawValue].joined(separator: ".")
            return NSPredicate(key, is: false)
        }
        static var obvMessageUpdateNotYetPersistedByApp: NSPredicate {
            let key = [Key.rawObvMessageUpdate.rawValue, PersistedObvMessage.Predicate.Key.wasPersistedInApp.rawValue].joined(separator: ".")
            return NSPredicate(key, is: false)
        }
        static func withMaxMessageUploadTimestampFromServer(_ maxMessageUploadTimestampFromServer: Date) -> NSPredicate {
            let rawKey = [Predicate.Key.rawObvMessage.rawValue, PersistedObvMessage.Predicate.Key.messageUploadTimestampFromServer.rawValue].joined(separator: ".")
            return .init(rawKey, earlierOrEqualTo: maxMessageUploadTimestampFromServer)
        }
        static func withMessageUploadTimestampFromServerEarlierThan(_ date: Date) -> NSPredicate {
            return .init(Key.messageUploadTimestampFromServer, earlierThan: date)
        }
    }
    
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<PersistedUserNotification> {
        return NSFetchRequest<PersistedUserNotification>(entityName: Self.entityName)
    }


    private static func withRequestIdentifier(requestIdentifier: String, within context: NSManagedObjectContext) throws -> PersistedUserNotification? {
        let request: NSFetchRequest<PersistedUserNotification> = Self.fetchRequest()
        request.predicate = Predicate.withRequestIdentifier(requestIdentifier: requestIdentifier)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    

    /// When the user interacts with a notification, we want to persist the content of the notification. This means, persisting the ObvMessage received when creating the notification.
    /// We might have received updates on that ObvMessage. For example, when considering a received message, the sender might have updated the body of the message.
    /// When this happens, we keep the latest update and return a non-nil value for obvMessageUpdate. The caller of this method will persist the obvMessage then, if it exists,
    /// also persist the obvMessageUpdate.
    public static func getObvMessageFromPersistedUserNotification(requestIdentifier: String, within context: NSManagedObjectContext) throws -> (obvMessage: ObvMessage, obvMessageUpdate: ObvMessage?)? {
        guard let persistedUserNotification = try Self.withRequestIdentifier(
            requestIdentifier: requestIdentifier,
            within: context) else {
            return nil
        }
        guard let obvMessage = try persistedUserNotification.rawObvMessage?.obvMessage else {
            return nil
        }
        let obvMessageUpdate = try persistedUserNotification.rawObvMessageUpdate?.obvMessage
        return (obvMessage, obvMessageUpdate)
    }
    
    
    public static func markObvMessageAndObvMessageUpdateAsPersistedInApp(requestIdentifier: String, within context: NSManagedObjectContext) throws {
        guard let persistedUserNotification = try Self.withRequestIdentifier(
            requestIdentifier: requestIdentifier,
            within: context) else {
            return
        }
        persistedUserNotification.markObvMessageAndObvMessageUpdateAsPersistedInApp()
    }
    
    
    /// During bootstraping, we fetch all `ObvMessages` found in the persisted user notifications to persist them in the messages database.
    public static func getAllObvMessagesFromPersistedUserNotifications(within context: NSManagedObjectContext) throws -> [(requestIdentifier: String, obvMessage: ObvMessage, obvMessageUpdate: ObvMessage?)] {
        let request: NSFetchRequest<PersistedUserNotification> = Self.fetchRequest()
        // Restrict to ObvMessages that were not yet persisted by the app
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.nonNilObvMessage,
                Predicate.obvMessageNotYetPersistedByApp,
            ]),
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.nonNilObvMessageUpdate,
                Predicate.obvMessageUpdateNotYetPersistedByApp,
            ]),
        ])
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.messageUploadTimestampFromServer.rawValue, ascending: true)]
        request.fetchBatchSize = 500
        let items = try context.fetch(request)
        return try items.compactMap { item in
            guard let obvMessage = try item.rawObvMessage?.obvMessage else { return nil }
            guard let requestIdentifier = item.requestIdentifier else { return nil }
            return (requestIdentifier, obvMessage, try? item.rawObvMessageUpdate?.obvMessage)
        }
    }
    
    
    public static func updateStatus(to newStatus: Status, requestIdentifier: String, within context: NSManagedObjectContext) throws {
        guard let persistedUserNotification = try Self.withRequestIdentifier(
            requestIdentifier: requestIdentifier,
            within: context) else {
            return
        }
        persistedUserNotification.setStatus(to: newStatus)
    }
    
    
    public static func exists(requestIdentifier: String, obvMessage: ObvMessage, within context: NSManagedObjectContext) throws -> Bool {
        let request: NSFetchRequest<PersistedUserNotification> = Self.fetchRequest()
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            Predicate.withRequestIdentifier(requestIdentifier: requestIdentifier),
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.withOwnedCryptoId(obvMessage.fromContactIdentity.ownedCryptoId),
                Predicate.withMessageIdFromServer(obvMessage.messageId.uid)
            ]),
        ])
        request.resultType = .countResultType
        request.fetchLimit = 1
        let count = try context.count(for: request)
        return count > 0
    }
    
    
    public static func getRequestIdentifierForShownReceivedMessage(ownedCryptoId: ObvCryptoId, messageIdFromServer: UID, within context: NSManagedObjectContext) throws -> String? {
        let request: NSFetchRequest<PersistedUserNotification> = Self.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.forKind(.receivedMessage),
            Predicate.withStatus(.shown),
            Predicate.withOwnedCryptoId(ownedCryptoId),
            Predicate.withMessageIdFromServer(messageIdFromServer),
        ])
        request.fetchLimit = 1
        request.propertiesToFetch = [Predicate.Key.requestIdentifier.rawValue]
        return try context.fetch(request).first?.requestIdentifier
    }
    
    
    public static func getRequestIdentifiersForShownReactionsOnSentMessages(discussionIdentifier: ObvDiscussionIdentifier, within context: NSManagedObjectContext) throws -> [String] {
        let request: NSFetchRequest<PersistedUserNotification> = Self.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.forKind(.reactionOnSentMessage),
            Predicate.withStatus(.shown),
            Predicate.withObvDiscussionIdentifier(discussionIdentifier),
        ])
        request.fetchBatchSize = 100
        request.propertiesToFetch = [Predicate.Key.requestIdentifier.rawValue]
        return try context.fetch(request).compactMap(\.requestIdentifier)
    }
    
    
    public static func getRequestIdentifiersForShownUserNotifications(discussionIdentifier: ObvDiscussionIdentifier, lastReadMessageServerTimestamp: Date?, within context: NSManagedObjectContext) throws -> [String] {
        let request: NSFetchRequest<PersistedUserNotification> = Self.fetchRequest()
        var predicates: [NSPredicate] = [
            Predicate.withStatus(.shown),
            Predicate.withObvDiscussionIdentifier(discussionIdentifier),
        ]
        if let lastReadMessageServerTimestamp {
            predicates += [
                Predicate.withMaxMessageUploadTimestampFromServer(lastReadMessageServerTimestamp),
            ]
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.fetchBatchSize = 100
        request.propertiesToFetch = [Predicate.Key.requestIdentifier.rawValue]
        return try context.fetch(request).compactMap(\.requestIdentifier)
    }
    
    
    public static func getRequestIdentifiersForShownUserNotifications(ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> [String] {
        let request: NSFetchRequest<PersistedUserNotification> = Self.fetchRequest()
        let predicates: [NSPredicate] = [
            Predicate.withOwnedCryptoId(ownedCryptoId),
            Predicate.withStatus(.shown),
        ]
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.fetchBatchSize = 100
        request.propertiesToFetch = [Predicate.Key.requestIdentifier.rawValue]
        return try context.fetch(request).compactMap(\.requestIdentifier)
    }

    
    public static func getRequestIdentifierForShownUserNotification(messageAppIdentifier: ObvMessageAppIdentifier, within context: NSManagedObjectContext) throws -> String? {
        let request: NSFetchRequest<PersistedUserNotification> = Self.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withStatus(.shown),
            Predicate.withObvMessageAppIdentifier(messageAppIdentifier),
        ])
        request.fetchLimit = 1
        request.propertiesToFetch = [Predicate.Key.requestIdentifier.rawValue]
        return try context.fetch(request).first?.requestIdentifier
    }
    

    /// When a user notification about a received message or reaction on a sent message is updated, because the sender updated her message, we call this method. Returns the previous request identifier iff we consider that the shown user notification should be updated.
    public static func markReceivedMessageNotificationAsUpdated(messageAppIdentifier: ObvMessageAppIdentifier, dateOfUpdate: Date, newRequestIdentifier: String, obvMessageUpdate: ObvMessage, within context: NSManagedObjectContext) throws -> String? {
        let request: NSFetchRequest<PersistedUserNotification> = Self.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withStatus(.shown),
            Predicate.withObvMessageAppIdentifier(messageAppIdentifier),
        ])
        request.fetchLimit = 1
        request.propertiesToFetch = [
            Predicate.Key.messageUploadTimestampFromServer.rawValue,
            Predicate.Key.requestIdentifier.rawValue,
        ]
        guard let notification = try context.fetch(request).first else { return nil }
        guard let previousRequestIdentifier = notification.requestIdentifier else { assertionFailure(); return nil }
        if let previousDateOfLastUpdate = notification.messageUploadTimestampFromServer {
            if previousDateOfLastUpdate < dateOfUpdate {
                notification.messageUploadTimestampFromServer = dateOfUpdate
                notification.requestIdentifier = newRequestIdentifier
                try notification.rawObvMessageUpdate?.deletePersistedObvMessage()
                notification.rawObvMessageUpdate = try PersistedObvMessage.createContent(obvMessage: obvMessageUpdate, within: context)
                return previousRequestIdentifier
            } else {
                return nil
            }
        } else {
            notification.messageUploadTimestampFromServer = dateOfUpdate
            notification.requestIdentifier = newRequestIdentifier
            try notification.rawObvMessageUpdate?.deletePersistedObvMessage()
            notification.rawObvMessageUpdate = try PersistedObvMessage.createContent(obvMessage: obvMessageUpdate, within: context)
            return previousRequestIdentifier
        }
    }
    
    
    public static func messageUploadTimestampFromServerForReaction(sentMessageReactedTo: ObvMessageAppIdentifier, reactor: ObvContactIdentifier, within context: NSManagedObjectContext) throws -> Date? {
        let request: NSFetchRequest<PersistedUserNotification> = Self.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.forKind(.reactionOnSentMessage),
            Predicate.withObvContactIdentifier(reactor),
            Predicate.withObvMessageAppIdentifier(sentMessageReactedTo),
        ])
        request.fetchLimit = 1
        request.propertiesToFetch = [Predicate.Key.messageUploadTimestampFromServer.rawValue]
        return try context.fetch(request).first?.messageUploadTimestampFromServer
    }

    
    /// During bootstrap, we remove old `PersistedUserNotification` if they are no longer shown in the notification center.
    static func deleteOldPersistedUserNotificationThatAreNoLongerShown(dateThreshold: TimeInterval, requestIdentifiersOfDeliveredNotifications: Set<String>, within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<PersistedUserNotification> = Self.fetchRequest()
        let now = Date.now
        let oldDate = now.addingTimeInterval(-abs(dateThreshold))
        guard oldDate < now else { assertionFailure(); return }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withMessageUploadTimestampFromServerEarlierThan(oldDate),
        ])
        request.fetchBatchSize = 500
        let items = try context.fetch(request)
        let itemsToDelete = items.filter { item in
            guard let requestIdentifier = item.requestIdentifier else { return true }
            return !requestIdentifiersOfDeliveredNotifications.contains(requestIdentifier)
        }
        for itemToDelete in itemsToDelete {
            do {
                try itemToDelete.deletePersistedUserNotification()
            } catch {
                assertionFailure(error.localizedDescription) // In production continue anyway
            }
        }
    }
    
}


// MARK: - Errors

extension PersistedUserNotification {
    
    enum ObvError: Error {
        case rawMessageIdFromServerIsNil
        case couldNotParseMessageIdFromServer
        case contentIsNil
        case couldNotDetermineContactIdentifier
        case rawOwnedIdentityIsNil
        case persistedUserNotificationAlreadyExistForThisMessage
    }
    
}
