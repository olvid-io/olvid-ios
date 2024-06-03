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
import os.log
import ObvMetaManager
import ObvCrypto
import ObvTypes
import OlvidUtils
import ObvEncoder
import ObvServerInterface

@objc(InboxMessage)
final class InboxMessage: NSManagedObject, ObvManagedObject, ObvErrorMaker {
    
    enum InternalError: Error {
        case aMessageWithTheSameMessageIdAlreadyExists
        case tryingToInsertAMessageThatWasAlreadyDeleted
        
        var localizedDescription: String {
            switch self {
            case .aMessageWithTheSameMessageIdAlreadyExists:
                return "A message with the same messageId already exists in DB"
            case .tryingToInsertAMessageThatWasAlreadyDeleted:
                return "Trying to insert a message in DB with a messageId that is identical to the one of a message that was recently deleted"
            }
        }
    }

    // MARK: Internal constants
    
    private static let entityName = "InboxMessage"
    private static let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: "InboxMessage")
    static var errorDomain = "InboxMessage"


    // MARK: Attributes
    
    @NSManaged private(set) var downloadTimestampFromServer: Date
    @NSManaged private(set) var encryptedContent: EncryptedData
    @NSManaged private(set) var extendedMessagePayload: Data?
    @NSManaged private(set) var fromCryptoIdentity: ObvCryptoIdentity? // Only set for application messages, at the same time than the attachments' infos
    @NSManaged private(set) var hasEncryptedExtendedMessagePayload: Bool
    @NSManaged private(set) var localDownloadTimestamp: Date
    @NSManaged private(set) var markedForDeletion: Bool // If true, a message will be deleted asap (i.e., when all its attachments are also marked for deletion)
    @NSManaged private(set) var markedAsListedOnServer: Bool // Set to true after having notified the server that we are aware of a message. Once this Boolean is true, this message won't appear again when listing messages.
    @NSManaged private(set) var messagePayload: Data? // Not set at download time, but at the same time than the attachments' infos
    @NSManaged private var rawMessageIdOwnedIdentity: Data? // Expected to be non-nil. Non nil in the model. This is just to make sure we do not crash when accessing this attribute on a deleted instance.
    @NSManaged private var rawMessageIdUid: Data? // Expected to be non-nil. Non nil in the model. This is just to make sure we do not crash when accessing this attribute on a deleted instance.
    @NSManaged private(set) var messageUploadTimestampFromServer: Date
    @NSManaged private var rawExtendedMessagePayloadKey: Data?
    @NSManaged private(set) var wrappedKey: EncryptedData
    
    // MARK: Relationships
    
    /// The var `dbAttachments` shall only be accessed through the `attachments`. The mechanism implemented here allows to make sure that an `InboxAttachment` instance accessed by means of an `InboxMessage` always has a non-nil `delegateManager`.
    @NSManaged private var dbAttachments: [InboxAttachment]?
    
    var attachments: [InboxAttachment] {
        let values = dbAttachments
        return values?.map { $0.obvContext = self.obvContext; return $0 } ?? []
    }
    
    var attachmentIds: [ObvAttachmentIdentifier] {
        return attachments.compactMap { $0.attachmentId }
    }

    // MARK: Other variables
    
    private(set) var extendedMessagePayloadKey: AuthenticatedEncryptionKey? {
        get {
            guard let rawEncoded = rawExtendedMessagePayloadKey else { return nil }
            guard let encodedKey = ObvEncoded(withRawData: rawEncoded) else { assertionFailure(); return nil }
            guard let key = try? AuthenticatedEncryptionKeyDecoder.decode(encodedKey) else { assertionFailure(); return nil }
            return key
        }
        set {
            self.rawExtendedMessagePayloadKey = newValue?.obvEncode().rawData
        }
    }
    
    /// This identifier is expected to be non nil, unless this `InboxMessage` was deleted on another thread.
    private(set) var messageId: ObvMessageIdentifier? {
        get {
            guard !self.isDeleted else { return nil }
            guard let rawMessageIdOwnedIdentity = self.rawMessageIdOwnedIdentity else { return nil }
            guard let rawMessageIdUid = self.rawMessageIdUid else { return nil }
            return ObvMessageIdentifier(rawOwnedCryptoIdentity: rawMessageIdOwnedIdentity, rawUid: rawMessageIdUid)
        }
        set {
            guard let newValue else { assertionFailure("We should not be setting a nil value"); return }
            self.rawMessageIdOwnedIdentity = newValue.ownedCryptoIdentity.getIdentity()
            self.rawMessageIdUid = newValue.uid.raw
        }
    }
    
    var obvContext: ObvContext?
    
    var canBeDeletedFromServer: Bool {
        return markedForDeletion && attachments.allSatisfy({ $0.markedForDeletion })
    }

    
    private func deleteInboxMessage(inbox: URL, obvContext: ObvContext) throws {
        guard let context = self.managedObjectContext else {
            assertionFailure()
            throw ObvError.contextIsNil
        }
        guard self.managedObjectContext == obvContext.context else {
            assertionFailure()
            throw ObvError.unexpectedContext
        }
        guard self.canBeDeletedFromServer else {
            throw ObvError.cannotBeDeleted
        }
        if let dbAttachments {
            dbAttachments.forEach { attachment in
                try? attachment.deleteDownload(fromInbox: inbox, within: obvContext)
            }
        }
        try? self.deleteAttachmentsDirectory(fromInbox: inbox)
        context.delete(self)
    }
    
    
    /// We expect to return a non-nil URL, unless this `InboxMessage` was deleted on another thread.
    func getAttachmentDirectory(withinInbox inbox: URL) -> URL? {
        guard let messageId else { return nil }
        // Return a legacy value if appropriate
        if let url = Self.getLegacyAttachmentDirectoryIfItExistsOnDisk(withinInbox: inbox, messageId: messageId) {
            return url
        }
        // Since we did not find any file at the legacy URL, we compute an appropriate, deterministic, URL.
        let directoryName = messageId.directoryNameForMessageAttachments
        return inbox.appendingPathComponent(directoryName, isDirectory: true)
    }
    
    
    private static func getLegacyAttachmentDirectoryIfItExistsOnDisk(withinInbox inbox: URL, messageId: ObvMessageIdentifier) -> URL? {
        let directoryNames = messageId.legacyDirectoryNamesForMessageAttachments
        for directoryName in directoryNames {
            let url = inbox.appendingPathComponent(directoryName, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }
    
    // MARK: - Initializer
    
    convenience init(messageId: ObvMessageIdentifier, encryptedContent: EncryptedData, hasEncryptedExtendedMessagePayload: Bool, wrappedKey: EncryptedData, messageUploadTimestampFromServer: Date, downloadTimestampFromServer: Date, localDownloadTimestamp: Date, within obvContext: ObvContext) throws {
        
        guard !Self.thisMessageWasRecentlyDeleted(messageId: messageId) else {
            throw InternalError.tryingToInsertAMessageThatWasAlreadyDeleted
        }
        
        os_log("🔑 Creating InboxMessage with id %{public}@", log: Self.log, type: .info, messageId.debugDescription)
        
        guard try InboxMessage.get(messageId: messageId, within: obvContext) == nil else {
            os_log("🔑 An InboxMessage with id %{public}@ already exists", log: Self.log, type: .info, messageId.debugDescription)
            throw InternalError.aMessageWithTheSameMessageIdAlreadyExists
        }
        let entityDescription = NSEntityDescription.entity(forEntityName: InboxMessage.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        
        self.encryptedContent = encryptedContent
        self.extendedMessagePayload = nil
        self.fromCryptoIdentity = nil
        self.hasEncryptedExtendedMessagePayload = hasEncryptedExtendedMessagePayload
        self.localDownloadTimestamp = localDownloadTimestamp
        self.messageId = messageId
        self.messageUploadTimestampFromServer = messageUploadTimestampFromServer
        self.rawExtendedMessagePayloadKey = nil
        self.downloadTimestampFromServer = downloadTimestampFromServer
        self.wrappedKey = wrappedKey
        
    }
    
    
    /// We keep in memory a list of all messages that were "recently" deleted. This prevents the re-creation of a message that we would list from the server and delete at the same time.
    /// Every 10 minutes or so, we remove old entries.
    private static var _messagesRecentlyDeleted = [ObvMessageIdentifier: Date]()
    
    /// This queue allows to synchronise access to `_messagesRecentlyDeleted`
    private static var messagesRecentlyDeletedQueue = DispatchQueue(label: "MessagesRecentlyDeletedQueue", attributes: .concurrent)
    
    /// Allows to keep track of the date when we last removed old entries from `messagesRecentlyDeleted`
    private static var lastRemovalOfOldEntriesInMessagesRecentlyDeleted = Date.distantPast
    
    
    /// Removes old entries from `messagesRecentlyDeleted` but only if we did not do this recently.
    private static func removeOldEntriesFromMessagesRecentlyDeletedIfAppropriate() {
        // We do not remove old entries from `messagesRecentlyDeleted` if we did this already less than 10 minutes ago
        guard Date().timeIntervalSince(lastRemovalOfOldEntriesInMessagesRecentlyDeleted) > TimeInterval(minutes: 10) else { return }
        lastRemovalOfOldEntriesInMessagesRecentlyDeleted = Date()
        let threshold = Date(timeInterval: -TimeInterval(minutes: 10), since: lastRemovalOfOldEntriesInMessagesRecentlyDeleted)
        // Keep the most recent values in messagesRecentlyDeleted
        messagesRecentlyDeletedQueue.async(flags: .barrier) {
            _messagesRecentlyDeleted = _messagesRecentlyDeleted.filter({ $0.value > threshold })
        }
    }
    
    
    /// Returns `true` iff we recently deleted a message with the given message identifier.
    private static func thisMessageWasRecentlyDeleted(messageId: ObvMessageIdentifier) -> Bool {
        removeOldEntriesFromMessagesRecentlyDeletedIfAppropriate()
        var result = false
        messagesRecentlyDeletedQueue.sync {
            result = _messagesRecentlyDeleted.keys.contains(messageId)
        }
        return result
    }

    
    private static func trackRecentlyDeletedMessage(messageId: ObvMessageIdentifier) {
        messagesRecentlyDeletedQueue.async(flags: .barrier) {
            _messagesRecentlyDeleted[messageId] = Date()
        }
    }
    
}


// MARK: - Utility methods

extension InboxMessage {
        
    func createAttachmentsDirectoryIfRequired(withinInbox inbox: URL) throws {
        let attachmentsDirectory = getAttachmentDirectory(withinInbox: inbox)
        guard let attachmentsDirectory else {
            throw Self.makeError(message: "Could not create the attachments directory for this InboxMessage. This happens if this message was deleted on another thread")
        }
        guard !FileManager.default.fileExists(atPath: attachmentsDirectory.path) else { return }
        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: false)
    }
    
    
    private func deleteAttachmentsDirectory(fromInbox inbox: URL) throws {
        let attachmentsDirectory = getAttachmentDirectory(withinInbox: inbox)
        guard let attachmentsDirectory else {
            throw Self.makeError(message: "Could not delete the attachments directory for this InboxMessage. This happens if this message was deleted on another thread")
        }
        guard FileManager.default.fileExists(atPath: attachmentsDirectory.path) else { return }
        try FileManager.default.removeItem(at: attachmentsDirectory)
    }
    
    
    func setFromCryptoIdentity(_ fromCryptoIdentity: ObvCryptoIdentity, andMessagePayload messagePayload: Data, extendedMessagePayloadKey: AuthenticatedEncryptionKey?) throws {
        os_log("🔑 Setting fromCryptoIdentity and messagePayload of message %{public}@", log: Self.log, type: .info, messageId.debugDescription)
        if self.fromCryptoIdentity == nil {
           self.fromCryptoIdentity = fromCryptoIdentity
        } else {
            guard self.fromCryptoIdentity == fromCryptoIdentity else {
                assertionFailure()
                throw Self.makeError(message: "Incoherent from identity")
            }
        }
        if self.messagePayload == nil {
            self.messagePayload = messagePayload
        } else {
            guard self.messagePayload == messagePayload else {
                assertionFailure()
                throw Self.makeError(message: "Incoherent message payload")
            }
        }
        self.extendedMessagePayloadKey = extendedMessagePayloadKey
    }
    
    
    var isProcessed: Bool { self.fromCryptoIdentity != nil && self.messagePayload != nil }
    
    // MARK: - Setters
    
    func markMessageAndAttachmentsForDeletion(attachmentToMarkForDeletion: InboxAttachmentsSet, within obvContext: ObvContext) throws {
        guard !isDeleted else { return }
        if !markedForDeletion {
            markedForDeletion = true
        }
        switch attachmentToMarkForDeletion {
        case .none:
            break
        case .all:
            attachments.forEach { $0.markForDeletion() }
        case .subset(attachmentNumbers: let attachmentNumbers):
            attachments
                .filter { attachmentNumbers.contains($0.attachmentNumber) }
                .forEach { $0.markForDeletion() }
        }
    }
    
    
    private func markAsListedOnServer() {
        assert(fromCryptoIdentity != nil, "We should be marking a message as 'listed' until whe determined who is the sender.")
        guard !markedAsListedOnServer else { return }
        markedAsListedOnServer = true
    }
    
    
    var receivedByteCount: Int {
        return encryptedContent.count
    }
    
    func setExtendedMessagePayload(to data: Data) {
        self.extendedMessagePayload = data
    }
    
    func deleteExtendedMessagePayload() {
        assert(extendedMessagePayload == nil)
        assert(hasEncryptedExtendedMessagePayload)
        assert(extendedMessagePayloadKey != nil)
        extendedMessagePayload = nil
        hasEncryptedExtendedMessagePayload = false
        extendedMessagePayloadKey = nil
    }
}


// MARK: - Convenience DB getters

extension InboxMessage {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<InboxMessage> {
        return NSFetchRequest<InboxMessage>(entityName: InboxMessage.entityName)
    }
    
    
    struct Predicate {
        enum Key: String {
            // Attributes
            case encryptedContentKey = "encryptedContent"
            case fromCryptoIdentityKey = "fromCryptoIdentity"
            case messagePayloadKey = "messagePayload"
            case rawMessageIdOwnedIdentityKey = "rawMessageIdOwnedIdentity"
            case rawMessageIdUidKey = "rawMessageIdUid"
            case downloadTimestampFromServer = "downloadTimestampFromServer"
            case messageUploadTimestampFromServer = "messageUploadTimestampFromServer"
            case markedForDeletion = "markedForDeletion"
            case markedAsListedOnServer = "markedAsListedOnServer"
            // Relationships
            case dbAttachments = "dbAttachments"
        }
        static func withMessageIdOwnedCryptoId(_ ownedCryptoId: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(Key.rawMessageIdOwnedIdentityKey, EqualToData: ownedCryptoId.getIdentity())
        }
        static func withMessageIdUid(_ uid: UID) -> NSPredicate {
            NSPredicate(Key.rawMessageIdUidKey, EqualToData: uid.raw)
        }
        static func withMessageIdentifier(_ messageId: ObvMessageIdentifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withMessageIdOwnedCryptoId(messageId.ownedCryptoIdentity),
                withMessageIdUid(messageId.uid),
            ])
        }
        static var isUnprocessed: NSPredicate {
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(withNilValueForKey: Key.fromCryptoIdentityKey),
                NSPredicate(withNilValueForKey: Key.messagePayloadKey),
            ])
        }
        static var isProcessed: NSPredicate {
            NSCompoundPredicate(notPredicateWithSubpredicate: Self.isUnprocessed)
        }
        static var isMarkedForDeletion: NSPredicate {
            NSPredicate(Key.markedForDeletion, is: true)
        }
        static var isNotMarkedForDeletion: NSPredicate {
            NSPredicate(Key.markedForDeletion, is: false)
        }
        static func markedAsListedOnServerIs(_ bool: Bool) -> NSPredicate {
            NSPredicate(Key.markedAsListedOnServer, is: bool)
        }
        static var allDBAttachmentsAreMarkedForDeletion: NSPredicate {
            let dbAttachments = Predicate.Key.dbAttachments.rawValue
            let rawStatus = InboxAttachment.Predicate.Key.rawStatus.rawValue
            return NSPredicate(format: "SUBQUERY(\(dbAttachments), $attachment, $attachment.\(rawStatus) == %d).@count == \(dbAttachments).@count", InboxAttachment.Status.markedForDeletion.rawValue)
        }
        static var canBeDeletedFromServer: NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.isMarkedForDeletion,
                Predicate.allDBAttachmentsAreMarkedForDeletion,
            ])
        }
    }
    
    
    static func getAll(forIdentity cryptoIdentity: ObvCryptoIdentity? = nil, within obvContext: ObvContext) throws -> [InboxMessage] {
        let request: NSFetchRequest<InboxMessage> = InboxMessage.fetchRequest()
        if let cryptoIdentity = cryptoIdentity {
            request.predicate = Predicate.withMessageIdOwnedCryptoId(cryptoIdentity)
        }
        // Make sure we fetch the properties requires to compute the messageId. This ensure we don't crash if the message gets deleted concurrently.
        request.propertiesToFetch = [
            Predicate.Key.rawMessageIdUidKey.rawValue,
            Predicate.Key.rawMessageIdOwnedIdentityKey.rawValue,
        ]
        return try obvContext.fetch(request)
    }
    
    
    static func getBatchOfUnprocessedMessages(ownedCryptoIdentity: ObvCryptoIdentity, batchSize: Int, within obvContext: ObvContext) throws -> [InboxMessage] {
        let request: NSFetchRequest<InboxMessage> = InboxMessage.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withMessageIdOwnedCryptoId(ownedCryptoIdentity),
            Predicate.isUnprocessed,
            Predicate.isNotMarkedForDeletion,
        ])
        
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.messageUploadTimestampFromServer.rawValue, ascending: true)]
        request.fetchLimit = batchSize
        return try obvContext.fetch(request)
    }
    

    /// This method returns all the ``InboxMessage`` instances that can be marked as listed on the server for the given owned identity.
    ///
    /// An ``InboxMessage`` can be marked as listed from server when:
    /// - it is "processed" (i.e., when ``fromCryptoIdentity`` and ``messagePayload`` are set),
    /// - not marked for deletion,
    /// - and not yet marked as listed on the server.
    private static func getAllMessagesThatCanBeMarkedAsListedOnServer(ownedCryptoIdentity: ObvCryptoIdentity, fetchLimit: Int, within context: NSManagedObjectContext) throws -> [ObvMessageIdentifier] {
        
        guard fetchLimit > 0 else { return [] }
        
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        request.resultType = .dictionaryResultType
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withMessageIdOwnedCryptoId(ownedCryptoIdentity),
            Predicate.isProcessed,
            Predicate.isNotMarkedForDeletion,
            Predicate.markedAsListedOnServerIs(false),
        ])
        request.propertiesToFetch = [
            Predicate.Key.rawMessageIdOwnedIdentityKey.rawValue,
            Predicate.Key.rawMessageIdUidKey.rawValue,
        ]
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.messageUploadTimestampFromServer.rawValue, ascending: true)]
        request.fetchLimit = fetchLimit

        guard let results = try context.fetch(request) as? [[String: Data]] else { assertionFailure(); throw makeError(message: "Could cast fetched result") }

        let valueToReturn: [ObvMessageIdentifier] = results.compactMap { dict in
            guard let rawMessageIdOwnedIdentity = dict[Predicate.Key.rawMessageIdOwnedIdentityKey.rawValue] else {
                assertionFailure(); return nil
            }
            guard let rawMessageIdUid = dict[Predicate.Key.rawMessageIdUidKey.rawValue] else {
                assertionFailure(); return nil
            }
            return ObvMessageIdentifier(rawOwnedCryptoIdentity: rawMessageIdOwnedIdentity, rawUid: rawMessageIdUid)
        }
        
        return valueToReturn
        
    }

    
    /// This method returns all the ``InboxMessage`` instances that can be deleted from server for the given owned identity.
    ///
    /// An ``InboxMessage`` can be deleted from server when it is marked for deletion, and when all its attachments are marked for deletion as well.
    private static func getAllMessagesThatCanBeDeletedFromServer(ownedCryptoIdentity: ObvCryptoIdentity, fetchLimit: Int, within context: NSManagedObjectContext) throws -> [ObvMessageIdentifier] {
        
        guard fetchLimit > 0 else { return [] }

        let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        request.resultType = .dictionaryResultType
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withMessageIdOwnedCryptoId(ownedCryptoIdentity),
            Predicate.canBeDeletedFromServer,
        ])
        request.propertiesToFetch = [
            Predicate.Key.rawMessageIdOwnedIdentityKey.rawValue,
            Predicate.Key.rawMessageIdUidKey.rawValue,
        ]
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.messageUploadTimestampFromServer.rawValue, ascending: true)]
        request.fetchLimit = fetchLimit
        
        guard let results = try context.fetch(request) as? [[String: Data]] else { assertionFailure(); throw makeError(message: "Could cast fetched result") }

        let valueToReturn: [ObvMessageIdentifier] = results.compactMap { dict in
            guard let rawMessageIdOwnedIdentity = dict[Predicate.Key.rawMessageIdOwnedIdentityKey.rawValue] else {
                assertionFailure(); return nil
            }
            guard let rawMessageIdUid = dict[Predicate.Key.rawMessageIdUidKey.rawValue] else {
                assertionFailure(); return nil
            }
            return ObvMessageIdentifier(rawOwnedCryptoIdentity: rawMessageIdOwnedIdentity, rawUid: rawMessageIdUid)
        }
        
        return valueToReturn

    }

    
    /// This method returns up to `fetchLimit` ``InboxMessage`` suitable for the work done by the ``BatchDeleteAndMarkAsListedCoordinator``.
    ///
    /// The messages returned all concern the same `ownedCryptoIdentity` and are composed of:
    /// - messages that can be deleted from server, and
    /// - messages that can be marked as listed on the server.
    static func fetchMessagesThatCanBeDeletedFromServerOrMarkedAsListed(ownedCryptoIdentity: ObvCryptoIdentity, fetchLimit: Int, within context: NSManagedObjectContext) throws -> [ObvServerDeleteMessageAndAttachmentsMethod.MessageUIDAndCategory] {

        guard fetchLimit > 0 else { return [] }
        
        let messagesToMarkAsListed = try getAllMessagesThatCanBeMarkedAsListedOnServer(ownedCryptoIdentity: ownedCryptoIdentity, fetchLimit: fetchLimit, within: context)
        assert(messagesToMarkAsListed.allSatisfy({ $0.ownedCryptoIdentity == ownedCryptoIdentity }))
        
        let messagesToDelete = try getAllMessagesThatCanBeDeletedFromServer(ownedCryptoIdentity: ownedCryptoIdentity, fetchLimit: max(0, fetchLimit - messagesToMarkAsListed.count), within: context)
        assert(messagesToDelete.allSatisfy({ $0.ownedCryptoIdentity == ownedCryptoIdentity }))
        
        var messageUIDsAndCategories = [ObvServerDeleteMessageAndAttachmentsMethod.MessageUIDAndCategory]()
        
        messageUIDsAndCategories += messagesToMarkAsListed.compactMap {
            .init(messageUID: $0.uid, category: .markAsListed)
        }

        messageUIDsAndCategories += messagesToDelete.compactMap {
            .init(messageUID: $0.uid, category: .requestDeletion)
        }

        return messageUIDsAndCategories

    }
    
    
    /// This method is used by the ``BootstrapWorker`` in order to re-notify the app.
    static func fetchMessagesThatCannotBeDeletedFromServer(within obvContext: ObvContext) throws -> [InboxMessage] {
        let request: NSFetchRequest<InboxMessage> = InboxMessage.fetchRequest()
        request.predicate = NSCompoundPredicate(notPredicateWithSubpredicate: Predicate.canBeDeletedFromServer)
        request.fetchBatchSize = 500
        // Make sure we fetch the properties requires to compute the messageId. This ensure we don't crash if the message gets deleted concurrently.
        request.propertiesToFetch = [
            Predicate.Key.rawMessageIdUidKey.rawValue,
            Predicate.Key.rawMessageIdOwnedIdentityKey.rawValue,
        ]
        return try obvContext.fetch(request)
    }

    
    static func get(messageId: ObvMessageIdentifier, within obvContext: ObvContext) throws -> InboxMessage? {
        let request: NSFetchRequest<InboxMessage> = InboxMessage.fetchRequest()
        request.predicate = Predicate.withMessageIdentifier(messageId)
        request.fetchLimit = 1
        return (try obvContext.fetch(request)).first
    }

    
    static func markAsListedOnServer(messageId: ObvMessageIdentifier, within obvContext: ObvContext) throws {
        let request: NSFetchRequest<InboxMessage> = InboxMessage.fetchRequest()
        request.predicate = Predicate.withMessageIdentifier(messageId)
        request.fetchLimit = 1
        request.propertiesToFetch = [Predicate.Key.markedAsListedOnServer.rawValue]
        guard let message = (try obvContext.fetch(request)).first else { return }
        message.markAsListedOnServer()
    }
    
    
    static func deleteMessage(messageId: ObvMessageIdentifier, inbox: URL, within obvContext: ObvContext) throws {
        let request: NSFetchRequest<InboxMessage> = InboxMessage.fetchRequest()
        request.predicate = Predicate.withMessageIdentifier(messageId)
        request.fetchLimit = 1
        request.propertiesToFetch = []
        guard let message = (try obvContext.fetch(request)).first else { return }
        try message.deleteInboxMessage(inbox: inbox, obvContext: obvContext)
    }
    
    /// Marks the message and all this attachments for deletion. Since they are all marked for deletion, we expect ``canBeDeletedFromServer`` to `true`.
    static func markMessageAndAttachmentsForDeletion(messageId: ObvMessageIdentifier, within obvContext: ObvContext) throws {
        let request: NSFetchRequest<InboxMessage> = InboxMessage.fetchRequest()
        request.predicate = Predicate.withMessageIdentifier(messageId)
        request.fetchLimit = 1
        request.propertiesToFetch = [Predicate.Key.markedForDeletion.rawValue]
        guard let message = (try obvContext.fetch(request)).first else { return }
        try message.markMessageAndAttachmentsForDeletion(attachmentToMarkForDeletion: .all, within: obvContext)
        assert(message.canBeDeletedFromServer)
    }
    
}


// MARK: - Other callbacks

extension InboxMessage {
    
    override func willSave() {
        super.willSave()
        
        // We do not wait until the context is saved for inserting the current message in the list of recently deleted messages.
        // The reason is the following :
        // - Either the save fails: in that case, the message stays in the database and we won't be able to create a new one with the same Id anyway.
        //   This message will eventually be deleted and the list of recently deleted messages will be updated with a new, more recent, timestamp.
        // - Either the save succeeds: in that case, we make sure that there won't be a time interval during which the message does not exists in DB without being stored in the list of recently deleted messages.
        
        assert(managedObjectContext?.concurrencyType != .mainQueueConcurrencyType)
        if isDeleted, self.managedObjectContext?.concurrencyType != .mainQueueConcurrencyType {
            guard let messageId else { return }
            Self.trackRecentlyDeletedMessage(messageId: messageId)
        }

    }
    
}


// MARK: - Errors

extension InboxMessage {
    
    enum ObvError: Error {
        case contextIsNil
        case cannotDetermineMessageId
        case cannotBeDeleted
        case unexpectedContext
    }
    
}
