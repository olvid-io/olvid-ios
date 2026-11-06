/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvMetaManager
import ObvCrypto
import ObvTypes
import ObvEncoder
import ObvServerInterface
import OlvidUtils


@objc(InboxMessage)
final class InboxMessage: NSManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "InboxMessage"
    private static let logger = Logger(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: "InboxMessage")


    // MARK: Attributes
    @NSManaged private(set) var deletedFromServer: Bool // Set to true after the server confirmed it no longer holds this message. Stronger than `markedAsListedOnServer`: the message will never be listed again *and* no further server request is required. The row survives until the app is done with the message.
    @NSManaged private(set) var downloadTimestampFromServer: Date
    @NSManaged private(set) var extendedMessagePayload: Data?
    @NSManaged private(set) var fromRawDeviceUID: Data? // Only set for application messages, at the same time than the attachments' infos
    @NSManaged private(set) var hasEncryptedExtendedMessagePayload: Bool
    @NSManaged private(set) var isOnHold: Bool // If the app cannot process a message yet, it can requests this message to be put on hold. It will request it at a later time, when it can process it.
    @NSManaged private(set) var localDownloadTimestamp: Date
    @NSManaged private(set) var markedAsListedOnServer: Bool // Set to true after having notified the server that we are aware of a message. Once this Boolean is true, this message won't appear again when listing messages.
    @NSManaged private(set) var markedForDeletion: Bool // If true, a message will be deleted asap (i.e., when all its attachments are also marked for deletion)
    @NSManaged private(set) var messagePayload: Data? // Not set at download time, but at the same time than the attachments' infos
    @NSManaged private(set) var messageUploadTimestampFromServer: Date
    @NSManaged private var rawEncryptedContent: Data? // Expected to be non nil
    @NSManaged private var rawExpectedContactForReProcessing: Data? // Non-nil iff the received message could be decrypted using a PreKey, but sent by an unknown remote identity
    @NSManaged private var rawExtendedMessagePayloadKey: Data?
    @NSManaged private var rawFromIdentity: Data? // Only set for application messages, at the same time than the attachments' infos
    @NSManaged private var rawMessageIdOwnedIdentity: Data? // Expected to be non-nil. Non nil in the model. This is just to make sure we do not crash when accessing this attribute on a deleted instance.
    @NSManaged private var rawMessageIdUid: Data? // Expected to be non-nil. Non nil in the model. This is just to make sure we do not crash when accessing this attribute on a deleted instance.
    @NSManaged private var rawWrappedKey: Data? // Expected to be non-nil
    
    // MARK: Relationships
    
    /// The var `dbAttachments` shall only be accessed through the `attachments`. The mechanism implemented here allows to make sure that an `InboxAttachment` instance accessed by means of an `InboxMessage` always has a non-nil `delegateManager`.
    @NSManaged private var dbAttachments: [InboxAttachment]?
    
    var attachments: [InboxAttachment] {
        return dbAttachments ?? []
    }
    
    var attachmentIds: [ObvAttachmentIdentifier] {
        return attachments.compactMap { try? $0.attachmentId }
    }

    // MARK: Other variables
    
    /// Expected to be non-nil
    var wrappedKey: EncryptedData? {
        guard let rawWrappedKey else { assertionFailure(); return nil }
        return EncryptedData(data: rawWrappedKey)
    }
    
    // Non-nil only for application messages. Set to a non-nil value at the same time than the attachments' infos
    private(set) var fromCryptoIdentity: ObvCryptoIdentity? {
        get {
            guard let rawFromIdentity else { return nil }
            guard let fromCryptoIdentity = ObvCryptoIdentity(from: rawFromIdentity) else { assertionFailure(); return nil }
            return fromCryptoIdentity
        }
        set {
            guard let newValue else { assertionFailure("Should never be reset to nil, except in the initializer"); return }
            if let currentValue = self.rawFromIdentity {
                assertionFailure("We don't expect to set this value twice.")
                guard currentValue == newValue.getIdentity() else { return }
            } else {
                self.rawFromIdentity = newValue.getIdentity()
            }
        }
    }
    
    /// Expected to be non-nil
    var encryptedContent: EncryptedData? {
        guard let rawEncryptedContent else { assertionFailure(); return nil }
        return EncryptedData(data: rawEncryptedContent)
    }
    
    private var fromDeviceUID: UID? {
        get {
            guard let fromRawDeviceUID else { return nil }
            return UID(uid: fromRawDeviceUID)
        }
        set {
            guard let newValue else { assertionFailure(); return }
            self.fromRawDeviceUID = newValue.raw
        }
    }
    
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
        
    var canBeDeletedFromServer: Bool {
        return markedForDeletion && attachments.allSatisfy({ $0.markedForDeletion })
    }

    
    /// What makes it right to remove a row. Every deletion but one rests on the app having finished with the message; the exception is a message whose owned
    /// identity no longer exists, which nothing will ever mark and nothing will ever read.
    enum WhatMakesTheRowRemovable {
        case theAppIsDoneWithIt
        case itsOwnedIdentityNoLongerExists
    }


    /// Returns the attachments
    private func deleteInboxMessage(inbox: URL, given: WhatMakesTheRowRemovable) throws -> URL? {
        guard let context = self.managedObjectContext else {
            assertionFailure()
            throw ObvError.contextIsNil
        }
        switch given {
        case .theAppIsDoneWithIt:
            guard self.canBeDeletedFromServer else {
                throw ObvError.cannotBeDeleted
            }
        case .itsOwnedIdentityNoLongerExists:
            break
        }
        if let dbAttachments {
            dbAttachments.forEach { attachment in
                _ = try? attachment.deleteDownload(fromInbox: inbox)
            }
        }
        let attachmentsDirectory = getAttachmentsDirectory(withinInbox: inbox)
        // Read before the deletion, never after: what a deleted-but-unsaved object answers for its own relationships is not something a probe should be
        // resting on, and a probe that reports the wrong number is worse than no probe at all.
        let messageDescription = self.messageId?.debugDescription ?? "unknown message"
        let numberOfAttachments = self.attachments.count
        //try? self.deleteAttachmentsDirectory(fromInbox: inbox)
        context.delete(self)
        // The row goes now and the directory goes when the context saves — see the caller. This is the moment at which a message's attachment files are
        // committed to being destroyed, and nothing here asks whether one of them is being downloaded as we speak.
        Self.logger.info("📁 [\(messageDescription, privacy: .public)] Deleting the InboxMessage and its \(numberOfAttachments) attachment(s). The directory \(attachmentsDirectory?.path ?? "nil", privacy: .public) is handed to the caller to delete once the context is saved")
        return attachmentsDirectory
    }
    
    
    /// We expect to return a non-nil URL, unless this `InboxMessage` was deleted on another thread.
    func getAttachmentsDirectory(withinInbox inbox: URL) -> URL? {
        guard let messageId else { return nil }
        // Return a legacy value if appropriate
        if let url = Self.getLegacyAttachmentDirectoryIfItExistsOnDisk(withinInbox: inbox, messageId: messageId) {
            // **This method's answer depends on what is on disk**, which makes it the one place where a file can be written at one path and looked for at
            // another: while a legacy directory exists the legacy path is returned, and the moment it goes the deterministic one is, whereupon the file is
            // reported missing by a path it was never written to. Said out loud whenever the legacy branch is taken, which for a message of the last two
            // years should be never.
            Self.logger.info("📁 [\(messageId.debugDescription, privacy: .public)] Answering with the LEGACY attachments directory \(url.lastPathComponent, privacy: .public), which exists on disk, rather than with the deterministic \(messageId.directoryNameForMessageAttachments, privacy: .public)")
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
    
    convenience init(messageId: ObvMessageIdentifier,
                     encryptedContent: EncryptedData,
                     hasEncryptedExtendedMessagePayload: Bool,
                     wrappedKey: EncryptedData,
                     messageUploadTimestampFromServer: Date,
                     downloadTimestampFromServer: Date,
                     localDownloadTimestamp: Date,
                     within context: NSManagedObjectContext
    ) throws {
        
        guard !Self.thisMessageWasRecentlyDeleted(messageId: messageId) else {
            throw ObvError.tryingToInsertAMessageThatWasAlreadyDeleted
        }
        
        Self.logger.info("🔑 Creating InboxMessage with id \(messageId.debugDescription)")
        
        guard try InboxMessage.get(messageId: messageId, within: context) == nil else {
            Self.logger.info("🔑 An InboxMessage with id \(messageId.debugDescription) already exists")
            throw ObvError.aMessageWithTheSameMessageIdAlreadyExists
        }
        let entityDescription = NSEntityDescription.entity(forEntityName: InboxMessage.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        self.rawEncryptedContent = encryptedContent.raw
        self.extendedMessagePayload = nil
        self.rawFromIdentity = nil
        self.fromRawDeviceUID = nil
        self.deletedFromServer = false
        self.hasEncryptedExtendedMessagePayload = hasEncryptedExtendedMessagePayload
        self.isOnHold = false
        self.localDownloadTimestamp = localDownloadTimestamp
        self.markedAsListedOnServer = false
        self.markedForDeletion = false
        self.messageId = messageId
        self.messagePayload = nil
        self.messageUploadTimestampFromServer = messageUploadTimestampFromServer
        self.rawExpectedContactForReProcessing = nil
        self.rawExtendedMessagePayloadKey = nil
        self.downloadTimestampFromServer = downloadTimestampFromServer
        self.rawWrappedKey = wrappedKey.raw
        
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


// MARK: - Getting an ObvMessage or an ObvOwnMessage

extension InboxMessage {
    
    func getObvMessageOrObvOwnedMessage(inbox: URL) -> ObvMessageOrObvOwnedMessage? {

        guard let messageId = self.messageId else { assert(self.isDeleted); return nil }
        guard let fromCryptoIdentity = self.fromCryptoIdentity else { assert(self.isDeleted); return nil }
        let ownedCryptoIdentity = messageId.ownedCryptoIdentity
        guard let messagePayload = self.messagePayload else { assert(self.isDeleted); return nil }

        if fromCryptoIdentity == ownedCryptoIdentity {
            
            let attachments: [ObvOwnedAttachment] = self.attachments.compactMap { inboxAttachment in
                return try? inboxAttachment.getObvOwnedAttachment(
                    messageUploadTimestampFromServer: self.messageUploadTimestampFromServer,
                    inbox: inbox)
            }

            let message = ObvOwnedMessage(messageId: messageId,
                                          attachments: attachments,
                                          messageUploadTimestampFromServer: self.messageUploadTimestampFromServer,
                                          downloadTimestampFromServer: self.downloadTimestampFromServer,
                                          localDownloadTimestamp: self.localDownloadTimestamp,
                                          messagePayload: messagePayload,
                                          extendedMessagePayload: self.extendedMessagePayload,
                                          deviceUID: self.fromDeviceUID)
            
            return .obvOwnedMessage(message)
            
        } else {
            
            let fromContactIdentity = ObvContactIdentifier(contactCryptoIdentity: fromCryptoIdentity, ownedCryptoIdentity: messageId.ownedCryptoIdentity)

            let attachments: [ObvAttachment] = self.attachments.compactMap { inboxAttachment in
                return try? inboxAttachment.getObvAttachment(
                    fromCryptoIdentity: fromContactIdentity,
                    messageUploadTimestampFromServer: self.messageUploadTimestampFromServer,
                    inbox: inbox)
            }

            let message = ObvMessage(fromContactIdentity: fromContactIdentity,
                                     fromContactDeviceUID: self.fromDeviceUID,
                                     messageId: messageId,
                                     attachments: attachments,
                                     messageUploadTimestampFromServer: self.messageUploadTimestampFromServer,
                                     downloadTimestampFromServer: self.downloadTimestampFromServer,
                                     localDownloadTimestamp: self.localDownloadTimestamp,
                                     messagePayload: messagePayload,
                                     extendedMessagePayload: self.extendedMessagePayload)
            
            return .obvMessage(message)

        }
        
    }
    
}


// MARK: - Utility methods

extension InboxMessage {
        
    func createAttachmentsDirectoryIfRequired(withinInbox inbox: URL) throws {
        let attachmentsDirectory = getAttachmentsDirectory(withinInbox: inbox)
        guard let attachmentsDirectory else {
            Self.logger.error("📁 [\(self.messageId?.debugDescription ?? "unknown message", privacy: .public)] Could not make the attachments directory: the message cannot say which directory is its own")
            throw ObvError.couldNotCreateAttachmentsDirectory // This happens if this message was deleted on another thread
        }
        // Both branches, because "the directory was already there" and "the directory was made now" are different facts about the same message, and a log
        // holding neither cannot say whether an attachment's file was ever written where it is now being looked for.
        guard !FileManager.default.fileExists(atPath: attachmentsDirectory.path) else {
            Self.logger.info("📁 [\(self.messageId?.debugDescription ?? "unknown message", privacy: .public)] The attachments directory \(attachmentsDirectory.lastPathComponent, privacy: .public) is already there")
            return
        }
        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: false)
        Self.logger.info("📁 [\(self.messageId?.debugDescription ?? "unknown message", privacy: .public)] Made the attachments directory \(attachmentsDirectory.lastPathComponent, privacy: .public) at \(attachmentsDirectory.path, privacy: .public)")
    }
    
    
//    private func deleteAttachmentsDirectory(fromInbox inbox: URL) throws {
//        let attachmentsDirectory = getAttachmentsDirectory(withinInbox: inbox)
//        guard let attachmentsDirectory else {
//            throw ObvError.couldNotDeleteAttachmentsDirectory // This happens if this message was deleted on another thread
//        }
//        guard FileManager.default.fileExists(atPath: attachmentsDirectory.path) else { return }
//        try FileManager.default.removeItem(at: attachmentsDirectory)
//    }
    
    
    func setFromCryptoIdentity(_ fromCryptoIdentity: ObvCryptoIdentity, remoteDeviceUID: UID, andMessagePayload messagePayload: Data, extendedMessagePayloadKey: AuthenticatedEncryptionKey?) throws {
        let messageIdDebugDescription = messageId.debugDescription
        Self.logger.info("🔑 Setting fromCryptoIdentity and messagePayload of message \(messageIdDebugDescription)")
        if self.fromCryptoIdentity == nil {
           self.fromCryptoIdentity = fromCryptoIdentity
        } else {
            guard self.fromCryptoIdentity == fromCryptoIdentity else {
                assertionFailure()
                throw ObvError.incoherentFromIdentity
            }
        }
        if self.fromDeviceUID == nil {
            self.fromDeviceUID = remoteDeviceUID
        } else {
            guard self.fromDeviceUID == remoteDeviceUID else {
                assertionFailure()
                throw ObvError.incoherentFromContactDevice
            }
        }
        if self.messagePayload == nil {
            self.messagePayload = messagePayload
        } else {
            guard self.messagePayload == messagePayload else {
                assertionFailure()
                throw ObvError.incoherentMessagePayload
            }
        }
        self.extendedMessagePayloadKey = extendedMessagePayloadKey
    }
    
    
    //var isProcessed: Bool { self.fromCryptoIdentity != nil && self.messagePayload != nil }
    
    
    private var expectedContactForReProcessing: ObvContactIdentifier? {
        guard let rawExpectedContactForReProcessing else { return nil }
        guard let rawMessageIdOwnedIdentity else { return nil }
        guard let contactCryptoIdentity = ObvCryptoIdentity(from: rawExpectedContactForReProcessing) else { assertionFailure(); return nil }
        guard let ownedCryptoIdentity = ObvCryptoIdentity(from: rawMessageIdOwnedIdentity) else { assertionFailure(); return nil }
        return ObvContactIdentifier(contactCryptoIdentity: contactCryptoIdentity, ownedCryptoIdentity: ownedCryptoIdentity)
    }
    
    // MARK: - Setters
    
    /// Marks the message for deletion, and those of its attachments the caller names.
    ///
    /// Returns the identifiers of the attachments marked, so that the caller can cancel their downloads: until a download is cancelled, a
    /// `URLSession` can still write into the file of a message that is about to be deleted.
    func markMessageAndAttachmentsForDeletion(attachmentToMarkForDeletion: InboxAttachmentsSet) throws -> [ObvAttachmentIdentifier] {
        guard !isDeleted else { return [] }
        if !markedForDeletion {
            markedForDeletion = true
        }
        let attachmentsToMarkForDeletion: [InboxAttachment]
        switch attachmentToMarkForDeletion {
        case .none:
            attachmentsToMarkForDeletion = []
        case .all:
            attachmentsToMarkForDeletion = attachments
        case .subset(attachmentNumbers: let attachmentNumbers):
            attachmentsToMarkForDeletion = attachments.filter { attachmentNumbers.contains($0.attachmentNumber) }
        }
        attachmentsToMarkForDeletion.forEach { $0.markForDeletion() }
        return attachmentsToMarkForDeletion.compactMap { try? $0.attachmentId }
    }
    
    
    private func markAsListedOnServer() {
        guard !markedAsListedOnServer else { return }
        markedAsListedOnServer = true
    }


    /// Called when the server confirmed the deletion of a message the app is not done with yet.
    ///
    /// Shall only be called on a server `.ok` for a `.requestDeletion`: it is what allows the row to be deleted later without asking the server again, so
    /// setting it without a confirmation would strand the message on the server until server-side expiry force-deleted it.
    ///
    /// Also marks the message as listed, which is implied and then some: a message the server no longer holds cannot be listed again.
    private func setDeletedFromServer() {
        if !deletedFromServer {
            deletedFromServer = true
        }
        markAsListedOnServer()
    }
    
    
    var receivedByteCount: Int {
        return encryptedContent?.count ?? 0
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
    
    
    /// If this message was sent through a PreKey channel by a remote identity that is not a contact (yet), we keep the message in the inbox until the
    /// remote identity becomes a contact. This method is called to indicate which remote identity we should wait for.
    func unwrapSucceededButRemoteCryptoIdIsUnknown(remoteCryptoIdentity: ObvCryptoIdentity) {
        if self.rawExpectedContactForReProcessing != remoteCryptoIdentity.getIdentity() {
            self.rawExpectedContactForReProcessing = remoteCryptoIdentity.getIdentity()
        }
    }
    
}

// MARK: On hold feature

extension InboxMessage {
    
    private func putOnHold() {
        guard !self.isOnHold else { return }
        self.isOnHold = true
    }
    
}


// MARK: - Convenience DB getters

extension InboxMessage {
    
    struct Predicate {
        enum Key: String {
            // Attributes
            case deletedFromServer = "deletedFromServer"
            case downloadTimestampFromServer = "downloadTimestampFromServer"
            case extendedMessagePayload = "extendedMessagePayload"
            case fromRawDeviceUID = "fromRawDeviceUID"
            case hasEncryptedExtendedMessagePayload = "hasEncryptedExtendedMessagePayload"
            case isOnHold = "isOnHold"
            case localDownloadTimestamp = "localDownloadTimestamp"
            case markedAsListedOnServer = "markedAsListedOnServer"
            case markedForDeletion = "markedForDeletion"
            case messagePayload = "messagePayload"
            case messageUploadTimestampFromServer = "messageUploadTimestampFromServer"
            case rawEncryptedContent = "rawEncryptedContent"
            case rawExpectedContactForReProcessing = "rawExpectedContactForReProcessing"
            case rawExtendedMessagePayloadKey = "rawExtendedMessagePayloadKey"
            case rawFromIdentity = "rawFromIdentity"
            case rawMessageIdOwnedIdentity = "rawMessageIdOwnedIdentity"
            case rawMessageIdUid = "rawMessageIdUid"
            case rawWrappedKey = "rawWrappedKey"
            // Relationships
            case dbAttachments = "dbAttachments"
        }
        
        static func withObjectID(_ objectID: NSManagedObjectID) -> NSPredicate {
            NSPredicate(withObjectID: objectID)
        }

        static func isOnHold(is bool: Bool) -> NSPredicate {
            NSPredicate(Key.isOnHold, is: bool)
        }
        
        static func withMessageIdOwnedCryptoId(_ ownedCryptoId: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(Key.rawMessageIdOwnedIdentity, EqualToData: ownedCryptoId.getIdentity())
        }

        /// Messages belonging to one of these owned identities. **An empty set matches nothing**, which is the answer that makes sense here: a device with no
        /// active profile has no message that anything will ever process.
        static func withMessageIdOwnedCryptoIdIn(_ ownedCryptoIds: [ObvCryptoIdentity]) -> NSPredicate {
            NSPredicate(Key.rawMessageIdOwnedIdentity, in: ownedCryptoIds.map { $0.getIdentity() })
        }

        static func withMessageIdUid(_ uid: UID) -> NSPredicate {
            NSPredicate(Key.rawMessageIdUid, EqualToData: uid.raw)
        }

        static func withMessageIdentifier(_ messageId: ObvMessageIdentifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withMessageIdOwnedCryptoId(messageId.ownedCryptoIdentity),
                withMessageIdUid(messageId.uid),
            ])
        }

        /// The predicates that, together, match the messages named by these identifiers. Loop over them, one fetch per predicate:
        ///
        ///     for predicate in Predicate.predicatesForMessageIdentifiers(messageIds) {
        ///         // one fetch, using this predicate
        ///     }
        ///
        /// Why an array and not a single predicate: matching many identifiers at once means an `IN` clause, and SQLite limits how
        /// many values one statement may carry. A predicate becomes a statement, so no single predicate can safely match an
        /// unlimited number of rows. Putting several smaller `IN` clauses inside one predicate would not help, because they would
        /// still end up in that same statement. The answer is more fetches, each asking about fewer messages. Returning one
        /// predicate per fetch makes the caller do that without having to know why.
        ///
        /// Each predicate covers at most ``numberOfIdentifiersPerFetch`` messages of a single owned identity. They are grouped that
        /// way so that a fetch is one `IN` over the second column of the uniqueness constraint. An empty input returns no
        /// predicates, so the caller's loop simply performs no fetch.
        static func predicatesForMessageIdentifiers(_ messageIds: [ObvMessageIdentifier]) -> [NSPredicate] {
            Dictionary(grouping: messageIds, by: { $0.ownedCryptoIdentity }).flatMap { ownedCryptoIdentity, messageIds in
                messageIds.map(\.uid).toSlices(ofMaxSize: numberOfIdentifiersPerFetch).map { uids in
                    NSCompoundPredicate(andPredicateWithSubpredicates: [
                        withMessageIdOwnedCryptoId(ownedCryptoIdentity),
                        NSPredicate(Key.rawMessageIdUid, in: uids.map { $0.raw }),
                    ])
                }
            }
        }

        static var toBeProcessByChannel: NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                isNotMarkedForDeletion,
                Predicate.isOnHold(is: false),
                isNotExpectingContactForReProcessing,
                hasNoFromIdentityOrNoMessagePayload,
            ])
        }

        static var toBeProcessByApp: NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                isNotMarkedForDeletion,
                Predicate.isOnHold(is: false),
                hasFromIdentityAndMessagePayload,
            ])
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

        static func deletedFromServerIs(_ bool: Bool) -> NSPredicate {
            NSPredicate(Key.deletedFromServer, is: bool)
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

        static var cannotBeDeletedFromServer: NSPredicate {
            NSCompoundPredicate(notPredicateWithSubpredicate: Predicate.canBeDeletedFromServer)
        }

        private static var isNotExpectingContactForReProcessing: NSPredicate {
            NSPredicate(withNilValueForKey: Key.rawExpectedContactForReProcessing)
        }

        static var isExpectingContactForReProcessing: NSPredicate {
            NSPredicate(withNonNilValueForKey: Key.rawExpectedContactForReProcessing)
        }

        private static var hasNoFromIdentityOrNoMessagePayload: NSPredicate {
            NSCompoundPredicate(notPredicateWithSubpredicate: Predicate.hasFromIdentityAndMessagePayload)
        }

        static var hasFromIdentityAndMessagePayload: NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(withNonNilValueForKey: Key.rawFromIdentity),
                NSPredicate(withNonNilValueForKey: Key.messagePayload),
            ])
        }

        static func withExpectedContactForReProcessing(contactIdentifier: ObvContactIdentifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.withMessageIdOwnedCryptoId(contactIdentifier.ownedCryptoId.cryptoIdentity),
                NSPredicate(Key.rawExpectedContactForReProcessing, EqualToData: contactIdentifier.contactCryptoId.getIdentity()),
            ])
        }

        static var hasSomeExpectedContactForReProcessing: NSPredicate {
            NSPredicate(withNonNilValueForKey: Key.rawExpectedContactForReProcessing)
        }

        fileprivate static func downloadTimestampFromServer(earlierThan date: Date) -> NSPredicate {
            NSPredicate(Key.downloadTimestampFromServer, earlierThan: date)
        }

        static var hasAtLeastOneAttachment: NSPredicate {
            NSPredicate(withStrictlyPositiveCountForKey: Key.dbAttachments)
        }

        static var hasAtLeastOneAttachmentNotMarkedForDeletion: NSPredicate {
            let dbAttachments = Predicate.Key.dbAttachments.rawValue
            let rawStatus = InboxAttachment.Predicate.Key.rawStatus.rawValue
            return NSPredicate(format: "SUBQUERY(\(dbAttachments), $attachment, $attachment.\(rawStatus) != %d).@count > 0", InboxAttachment.Status.markedForDeletion.rawValue)
        }

        /// A message the app has finished with, whose attachments have not all been released — so it stays in the inbox and the server keeps its copy.
        ///
        /// Note that this has to be composed: `cannotBeDeletedFromServer` on its own is the negation of a conjunction, and so is satisfied by every message
        /// that is not marked for deletion at all, which is nearly the whole inbox.
        ///
        /// **Says *has one that is not* rather than negating *has all of them*, and the two are the same question at different prices.** This one is counted
        /// on the drain's path, where the other four counts of ``ObvInboxCounts`` cost 12–14ms each; asked as `NOT(all are marked)` — two correlated
        /// subqueries per row, which is what ``canBeDeletedFromServer`` composes — it measured **98ms** against **72ms** for this shape, on a store of
        /// 81'210 messages carrying one attachment apiece (2026-09-11, both formulations agreeing on 8'093). Both are equivalent on a message with no
        /// attachments at all, which is in neither population: *all of none are marked* is vacuously true, and *one of none is unmarked* is false.
        static var isMarkedForDeletionYetCannotBeDeletedFromServer: NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.isMarkedForDeletion,
                Predicate.hasAtLeastOneAttachmentNotMarkedForDeletion,
            ])
        }

    }

    
    @nonobjc class func fetchRequest() -> NSFetchRequest<InboxMessage> {
        return NSFetchRequest<InboxMessage>(entityName: InboxMessage.entityName)
    }
    
    
    static func putOnHold(messageId: ObvMessageIdentifier, within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<InboxMessage> = InboxMessage.fetchRequest()
        request.predicate = Predicate.withMessageIdentifier(messageId)
        request.fetchLimit = 1
        request.propertiesToFetch = [Predicate.Key.isOnHold.rawValue]
        let item = try context.fetch(request).first
        item?.putOnHold()
    }
    
    
    static func fetchOnHoldMessage(messageId: ObvMessageIdentifier, inbox: URL, within context: NSManagedObjectContext) throws -> ObvMessageOrObvOwnedMessage? {
        let request: NSFetchRequest<InboxMessage> = InboxMessage.fetchRequest()
        request.predicate = Predicate.withMessageIdentifier(messageId)
        request.fetchLimit = 1
        guard let item = try context.fetch(request).first else { return nil }
        return item.getObvMessageOrObvOwnedMessage(inbox: inbox)
    }
    
    
    /// Called during bootstrap, to delete orphaned directories, and during an owned identity deletion.
    static func getAll(forIdentity cryptoIdentity: ObvCryptoIdentity? = nil, within context: NSManagedObjectContext) throws -> [InboxMessage] {
        let request: NSFetchRequest<InboxMessage> = InboxMessage.fetchRequest()
        if let cryptoIdentity = cryptoIdentity {
            request.predicate = Predicate.withMessageIdOwnedCryptoId(cryptoIdentity)
        }
        request.fetchBatchSize = 500
        // Make sure we fetch the properties requires to compute the messageId. This ensures we don't crash if the message gets deleted concurrently.
        request.propertiesToFetch = [
            Predicate.Key.rawMessageIdUid.rawValue,
            Predicate.Key.rawMessageIdOwnedIdentity.rawValue,
        ]
        return try context.fetch(request)
    }
    
    
    static func getBatchOfMessagesToBeProcessByChannel(ownedCryptoIdentity: ObvCryptoIdentity, fetchLimit: Int, within context: NSManagedObjectContext) throws -> [InboxMessage] {
        let request: NSFetchRequest<InboxMessage> = InboxMessage.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withMessageIdOwnedCryptoId(ownedCryptoIdentity),
            Predicate.toBeProcessByChannel,
        ])
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.messageUploadTimestampFromServer.rawValue, ascending: true)]
        request.fetchLimit = fetchLimit
        return try context.fetch(request)
    }
    
    
    static func getBatchOfMessagesToBeProcessByChannel(restrictTo messageIdentifiers: [ObvMessageIdentifier], within context: NSManagedObjectContext) throws -> [InboxMessage] {

        var unprocessedMessages = [InboxMessage]()

        for messageIdentifier in messageIdentifiers {
            do {
                if let message = try getMessageToBeProcessedByChannel(messageIdentifier: messageIdentifier, within: context) {
                    unprocessedMessages.append(message)
                }
            } catch {
                Self.logger.fault("Could not fetch InboxMessage: \(error.localizedDescription)")
                assertionFailure() // In production, continue with the next message
            }
        }
        
        return unprocessedMessages
        
    }
    
    
    static func getMessageToBeProcessedByChannel(messageIdentifier: ObvMessageIdentifier, within context: NSManagedObjectContext) throws -> InboxMessage? {
        
        let request: NSFetchRequest<InboxMessage> = InboxMessage.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withMessageIdentifier(messageIdentifier),
            Predicate.toBeProcessByChannel,
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first

    }
    
    
    static func getObvMessageOrObvOwnedMessageToBeProcessedByApp(inboxMessageObjectID: NSManagedObjectID, inbox: URL, within context: NSManagedObjectContext) throws -> ObvMessageOrObvOwnedMessage? {
        let request: NSFetchRequest<InboxMessage> = InboxMessage.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withObjectID(inboxMessageObjectID),
            Predicate.toBeProcessByApp,
        ])
        request.fetchLimit = 1
        guard let item = try context.fetch(request).first else { return nil }
        return item.getObvMessageOrObvOwnedMessage(inbox: inbox)
    }
    
    
    /// Returns the object IDs of every message still to be handed to the app, oldest first.
    ///
    /// The order is load-bearing: `MessagesCoordinator.getAsyncStreamOfObvMessageOrObvOwnedMessages()` slices this array at
    /// `ObvNetworkFetchDelegateManager.numberOfMessagesStreamedToTheAppAtOnce` and yields the slices in turn, so this sort descriptor alone decides the order in
    /// which the app receives its backlog. The constant is named rather than written out: it was ten when this was written, and is a hundred now.
    ///
    /// **Dictionaries rather than `managedObjectIDResultType`, whose *order* cannot be relied on.** Never rely on the
    /// order of an object-ID fetch. Measured on 2026-08-19 against `PersistedMessage.getObjectIDsOfAllMessagesWithinDiscussion`, where the same
    /// request asked both ways returned the same 948 rows in two orders that differed **from position 0**, once the context had had deletions merged into it.
    /// This context has deletions merged into it constantly, from the sweep, which is exactly that precondition.
    ///
    /// **The engine has never been measured, and this was changed without measuring it.** Building a backlog large enough to test is expensive, the change is a
    /// straight adaptation of ``fetchMessageIdsAndUploadTimestamps(predicate:fetchLimit:within:)`` a few lines below, and the signature is unchanged — so there
    /// is no outcome in which the previous version is the better one to have. Do not read this comment as evidence that the fault was observed here; it was
    /// not. What is recorded is a convention being applied, not a bug being fixed.
    ///
    /// A dictionary fetch keeps what the object-ID fetch was for: it reads columns and **materialises no `InboxMessage`**, which matters here because a message
    /// row carries its whole encrypted content inline in `rawEncryptedContent`. `messageUploadTimestampFromServer` is selected beside the ID deliberately — a
    /// column sorted on but never selected is the sort of thing an optimiser may treat differently, and the request measured ordered elsewhere selected it.
    ///
    /// `fetchBatchSize` is gone with the old request. Batching returns a faulting array, which buys nothing for a fetch whose every row is read immediately and
    /// whose rows are an identifier and a date.
    static func getObjectIDsOfInboxMessagesToBeProcessedByApp(within context: NSManagedObjectContext) throws -> [NSManagedObjectID] {

        let theObjectID = NSExpressionDescription()
        theObjectID.name = Self.nameOfTheObjectIDInTheFetchedDictionaries
        theObjectID.expression = NSExpression.expressionForEvaluatedObject()
        theObjectID.expressionResultType = .objectIDAttributeType

        let request = NSFetchRequest<NSDictionary>(entityName: Self.entityName)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = [theObjectID, Predicate.Key.messageUploadTimestampFromServer.rawValue]
        request.predicate = Predicate.toBeProcessByApp
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.messageUploadTimestampFromServer.rawValue, ascending: true)]

        let rows = try context.fetch(request)
        let objectIDs = rows.compactMap({ $0[Self.nameOfTheObjectIDInTheFetchedDictionaries] as? NSManagedObjectID })
        guard objectIDs.count == rows.count else {
            assertionFailure()
            throw ObvError.couldNotCastFetchedResult
        }
        return objectIDs

    }


    /// The key the object ID comes back under in ``getObjectIDsOfInboxMessagesToBeProcessedByApp(within:)``, which has to name it itself because a dictionary
    /// fetch has no other way of asking for one.
    private static let nameOfTheObjectIDInTheFetchedDictionaries = "theObjectID"


    /// The identifier of an ``InboxMessage`` together with the server timestamp that orders the work of the ``BatchDeleteAndMarkAsListedCoordinator``.
    ///
    /// The timestamp is carried out of the fetch rather than read back off the message afterwards, which is what lets the caller merge two sets by age without
    /// ever instantiating an `InboxMessage` — see ``fetchMessageIdsAndUploadTimestamps(predicate:fetchLimit:within:)``.
    private struct MessageIdAndUploadTimestamp {
        let messageId: ObvMessageIdentifier
        let messageUploadTimestampFromServer: Date
    }


    /// One candidate for the `deleteMessageAndAttachments` server method, before the budget is spent.
    private struct CandidateForServer {
        let messageId: ObvMessageIdentifier
        let messageUploadTimestampFromServer: Date
        let category: ObvServerDeleteMessageAndAttachmentsMethod.Category
    }


    /// The single fetch behind all three sets the ``BatchDeleteAndMarkAsListedCoordinator`` needs: given the predicate that defines a set, it returns the
    /// oldest `fetchLimit` messages of that set.
    ///
    /// It is a `dictionaryResultType` fetch, so Core Data hands back one dictionary of the three requested columns per row and **never instantiates an
    /// `InboxMessage`**. That is deliberate rather than incidental: a message row carries its whole encrypted content inline in `rawEncryptedContent`, so a
    /// fetch of managed objects would read that blob into the row cache for every message of the batch — all to obtain an identifier and a date. That is the convention
    /// for batches of this shape: read the columns, instantiate nothing.
    private static func fetchMessageIdsAndUploadTimestamps(predicate: NSPredicate, fetchLimit: Int, within context: NSManagedObjectContext) throws -> [MessageIdAndUploadTimestamp] {

        guard fetchLimit > 0 else { return [] }

        let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        request.resultType = .dictionaryResultType
        request.predicate = predicate
        request.propertiesToFetch = [
            Predicate.Key.rawMessageIdOwnedIdentity.rawValue,
            Predicate.Key.rawMessageIdUid.rawValue,
            Predicate.Key.messageUploadTimestampFromServer.rawValue,
        ]
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.messageUploadTimestampFromServer.rawValue, ascending: true)]
        request.fetchLimit = fetchLimit

        guard let results = try context.fetch(request) as? [[String: Any]] else { assertionFailure(); throw ObvError.couldNotCastFetchedResult }

        return results.compactMap { dict in
            guard let rawMessageIdOwnedIdentity = dict[Predicate.Key.rawMessageIdOwnedIdentity.rawValue] as? Data else {
                assertionFailure(); return nil
            }
            guard let rawMessageIdUid = dict[Predicate.Key.rawMessageIdUid.rawValue] as? Data else {
                assertionFailure(); return nil
            }
            guard let messageUploadTimestampFromServer = dict[Predicate.Key.messageUploadTimestampFromServer.rawValue] as? Date else {
                assertionFailure(); return nil
            }
            guard let messageId = ObvMessageIdentifier(rawOwnedCryptoIdentity: rawMessageIdOwnedIdentity, rawUid: rawMessageIdUid) else {
                assertionFailure(); return nil
            }
            return MessageIdAndUploadTimestamp(messageId: messageId, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        }

    }


    /// What allows a row to be removed although no server request was made for it.
    ///
    /// Named rather than implied, because the two cases leave the server in opposite states and only one of them is a confirmation.
    enum GroundsForLocalDeletion {

        /// The server has confirmed it no longer holds the message. This is the second half of the early-deletion optimisation: the confirmation was recorded
        /// on the row (`deletedFromServer`), and deleting on the strength of a request we merely *sent* would leave nothing behind to ask again.
        case theServerHasConfirmed

        /// The owned identity is inactive, so nothing will ever ask the server: no listing enumerates it, and the batch sweep has no session to ask with. The
        /// message expires on the server by itself, and keeping the row only costs space.
        ///
        /// **A message removed on these grounds can come back, and that is accepted rather than overlooked.** What stops the server listing a message again is
        /// `markedAsListedOnServer`, and a row the app finished with before either server round trip completed does not carry it — so if the profile is ever
        /// reactivated, the server lists those messages afresh and the app receives them a second time. The alternative is to keep every such row for a
        /// profile that may never be reactivated, against a server that expires them anyway.
        case nothingWillEverAskTheServer

    }


    /// The messages whose row can be deleted without asking the server anything at all, the app being done with them. See ``GroundsForLocalDeletion`` for
    /// what makes that safe.
    ///
    /// This is a fetch of its own, and it deliberately does not share the server's budget. The `fetchLimit` of the method below is
    /// what the server accepts in one request: it is halved when the server answers 413, and never grown back. Removing these rows
    /// sends nothing, so inheriting that number limited free work to the size of a network batch. Asking for it in the same breath
    /// as the two server-side sets also meant paying all three scans even when there was nothing to send.
    ///
    /// The coordinator drains this set first, for that reason, and because every row it removes makes the scans below cheaper.
    static func fetchMessagesToDeleteLocally(ownedCryptoIdentity: ObvCryptoIdentity, grounds: GroundsForLocalDeletion, fetchLimit: Int, within context: NSManagedObjectContext) throws -> [ObvMessageIdentifier] {

        guard fetchLimit > 0 else { return [] }

        var predicates = [
            Predicate.withMessageIdOwnedCryptoId(ownedCryptoIdentity),
            Predicate.canBeDeletedFromServer,
        ]
        switch grounds {
        case .theServerHasConfirmed:
            predicates.append(Predicate.deletedFromServerIs(true))
        case .nothingWillEverAskTheServer:
            break
        }

        let toDeleteLocally = try fetchMessageIdsAndUploadTimestamps(
            predicate: NSCompoundPredicate(andPredicateWithSubpredicates: predicates),
            fetchLimit: fetchLimit,
            within: context)
        assert(toDeleteLocally.allSatisfy({ $0.messageId.ownedCryptoIdentity == ownedCryptoIdentity }))

        return toDeleteLocally.map(\.messageId)

    }


    /// The work the ``BatchDeleteAndMarkAsListedCoordinator`` has to send to the server for one owned identity, oldest message first, at most `fetchLimit` of
    /// them.
    ///
    /// Two sets are considered, and they are mutually exclusive by construction:
    /// - messages that can be deleted from the server (marked for deletion, with every attachment marked too) and that the server still holds;
    /// - messages that cannot be deleted from the server yet and are not marked as listed on it.
    ///
    /// The third set this method used to return is now ``fetchMessagesToDeleteLocally(ownedCryptoIdentity:grounds:fetchLimit:within:)``; see there for why.
    ///
    /// **Note that no early deletion is decided here.** An attachment-less message is asked to be deleted from the server as soon as it is saved, but that
    /// decision is made in the `MessagesCoordinator`, from the server's own listing, which is the only authoritative account of what the server holds. It
    /// cannot be made from the database: `SaveMessagesAndAttachmentsFromServerOperation` continues past a failed attachment insertion, so a message row can
    /// survive with fewer `InboxAttachment` rows than the server has — possibly none — and a database-side "has no attachment" test would then delete from the
    /// server an attachment that was never recorded. A failed early deletion therefore falls through to being marked as listed by the second set above,
    /// which is what happened to every such message before the optimisation existed.
    static func fetchMessagesToProcessOnServer(ownedCryptoIdentity: ObvCryptoIdentity, fetchLimit: Int, within context: NSManagedObjectContext) throws -> [ObvServerDeleteMessageAndAttachmentsMethod.MessageUIDAndCategory] {

        guard fetchLimit > 0 else { return [] }

        // Each of the two fetches asks for the whole budget and the merge below decides how it is actually spent. Asking for the messages to mark
        // as listed first, with the full budget, and giving the deletions whatever remained meant that a backlog of more than `fetchLimit` unlisted messages
        // deleted nothing at all in a round: the deletions were deferred behind every listing.

        let toDeleteFromServer = try fetchMessageIdsAndUploadTimestamps(
            predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.withMessageIdOwnedCryptoId(ownedCryptoIdentity),
                Predicate.deletedFromServerIs(false),
                Predicate.canBeDeletedFromServer,
            ]),
            fetchLimit: fetchLimit,
            within: context)
        assert(toDeleteFromServer.allSatisfy({ $0.messageId.ownedCryptoIdentity == ownedCryptoIdentity }))

        // Keyed on `cannotBeDeletedFromServer` rather than on "not marked for deletion", which is what used to leave a message marked for deletion with only
        // some of its attachments marked in neither set: excluded from the markable set for being marked for deletion, and from the deletable set for having an
        // attachment that was not. Nothing picked such a message up, and the server re-listed it on every listing until its last attachment was dealt with.
        let toMarkAsListed = try fetchMessageIdsAndUploadTimestamps(
            predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.withMessageIdOwnedCryptoId(ownedCryptoIdentity),
                Predicate.deletedFromServerIs(false),
                Predicate.cannotBeDeletedFromServer,
                Predicate.markedAsListedOnServerIs(false),
            ]),
            fetchLimit: fetchLimit,
            within: context)
        assert(toMarkAsListed.allSatisfy({ $0.messageId.ownedCryptoIdentity == ownedCryptoIdentity }))

        let candidates: [CandidateForServer] =
            toDeleteFromServer.map { .init(messageId: $0.messageId, messageUploadTimestampFromServer: $0.messageUploadTimestampFromServer, category: .requestDeletion) }
            + toMarkAsListed.map { .init(messageId: $0.messageId, messageUploadTimestampFromServer: $0.messageUploadTimestampFromServer, category: .markAsListed) }

        let messageUIDsAndCategories = candidates
            .sorted { $0.messageUploadTimestampFromServer < $1.messageUploadTimestampFromServer }
            .prefix(fetchLimit)
            .map { ObvServerDeleteMessageAndAttachmentsMethod.MessageUIDAndCategory(messageUID: $0.messageId.uid, category: $0.category) }

        return Array(messageUIDsAndCategories)

    }
    
    
    /// Used during bootstrap to notify the app about decrypted application messages (either ones that were never notified, or about attachments' statuses of notified ones).
    static func fetchApplicationMessagesToReNotify(within context: NSManagedObjectContext) throws -> [InboxMessage] {
        let request: NSFetchRequest<InboxMessage> = InboxMessage.fetchRequest()
        request.fetchBatchSize = 500
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.messageUploadTimestampFromServer.rawValue, ascending: true)]
        // Make sure we fetch the properties required to compute the messageId. This ensure we don't crash if the message gets deleted concurrently.
        request.propertiesToFetch = [
            Predicate.Key.rawMessageIdUid.rawValue,
            Predicate.Key.rawMessageIdOwnedIdentity.rawValue,
        ]
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.hasFromIdentityAndMessagePayload,
            Predicate.cannotBeDeletedFromServer,
        ])
        return try context.fetch(request)
    }
    

    static func get(messageId: ObvMessageIdentifier, within context: NSManagedObjectContext) throws -> InboxMessage? {
        let request: NSFetchRequest<InboxMessage> = InboxMessage.fetchRequest()
        request.predicate = Predicate.withMessageIdentifier(messageId)
        request.fetchLimit = 1
        return (try context.fetch(request)).first
    }

    
    static func markAsListedOnServer(messageId: ObvMessageIdentifier, within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<InboxMessage> = InboxMessage.fetchRequest()
        request.predicate = Predicate.withMessageIdentifier(messageId)
        request.fetchLimit = 1
        request.propertiesToFetch = [Predicate.Key.markedAsListedOnServer.rawValue]
        guard let message = (try context.fetch(request)).first else { return }
        message.markAsListedOnServer()
    }
    
    
    /// What ``processServerConfirmationOfDeletion(messageId:inbox:within:)`` did — which is decided by the row, never by the request.
    ///
    /// The three cases used to be squeezed into a single `URL?`, where `nil` meant *either* "the row was kept", which is the ordinary and correct outcome of an
    /// early deletion, *or* "there was no row at all". Those are the optimisation working and a message having gone missing, and nothing downstream could tell
    /// them apart — the same conflation met in the inbox sweep, where one report meant both "the box is empty" and "the box could not be
    /// read", and the whole diagnosis turned on which of the two it was.
    enum ServerConfirmationOfDeletionOutcome {

        /// The app had finished with the message, so its row is gone. The attachments' directory, when there is one, is to be deleted once the context saves.
        case rowDeleted(attachmentsDirectory: URL?)

        /// The app has not finished with the message, so the row stays and merely records that the server no longer holds it. This is the ordinary outcome of
        /// an early deletion.
        case rowKeptAndMarkedAsDeletedFromServer

        /// No row carries this identifier any more. Legitimate — an earlier round may already have removed it — but worth saying out loud rather than leaving
        /// it to look like the case above.
        case noRowFound

    }


    /// Called on the server's confirmation that it deleted a message, in response to a `.requestDeletion`.
    ///
    /// **The row decides what happens here, never the request**, which may have been built while the message was in the other state — the app can finish with a
    /// message while the request is in flight. Two cases reach this:
    /// - the app is done with the message (``canBeDeletedFromServer``), so the row goes, exactly as it always has;
    /// - we asked the server to delete a message the app has *not* processed yet. That is the point of the early deletion: an attachment-less message is fully
    ///   in this database the moment its row is committed, so there is no reason for the server to keep holding it. The row must stay — no listing will ever
    ///   return the message again, so deleting it here would lose it — and only records that the server no longer holds it.
    static func processServerConfirmationOfDeletion(messageId: ObvMessageIdentifier, inbox: URL, within context: NSManagedObjectContext) throws -> ServerConfirmationOfDeletionOutcome {
        let request: NSFetchRequest<InboxMessage> = InboxMessage.fetchRequest()
        request.predicate = Predicate.withMessageIdentifier(messageId)
        request.fetchLimit = 1
        guard let message = (try context.fetch(request)).first else { return .noRowFound }
        guard message.canBeDeletedFromServer else {
            message.setDeletedFromServer()
            return .rowKeptAndMarkedAsDeletedFromServer
        }
        return .rowDeleted(attachmentsDirectory: try message.deleteInboxMessage(inbox: inbox, given: .theAppIsDoneWithIt))
    }


    /// Deletes the rows of messages the app is done with and that need no server request, on the `grounds` given.
    ///
    /// Returns the attachments' directories to remove once the context is saved (empty when the server has confirmed — a message eligible for early deletion
    /// has no attachments — but returned rather than assumed, and an inactive identity's messages may have any number of them).
    static func deleteMessagesNeedingNoServerRequest(messageIds: [ObvMessageIdentifier], grounds: GroundsForLocalDeletion, inbox: URL, within context: NSManagedObjectContext) throws -> (numberOfRowsDeleted: Int, directoriesToDelete: [URL]) {
        var numberOfRowsDeleted = 0
        var directoriesToDelete = [URL]()
        // One fetch per hundred messages, instead of one fetch per message. The caller works on pages of
        // ``BatchDeleteAndMarkAsListedCoordinator/localDeletionFetchLimit`` messages, and calls this again as long as such messages
        // remain, so a fetch per message is 500 round trips to the store for each of those pages.
        for predicate in Predicate.predicatesForMessageIdentifiers(messageIds) {
            let request: NSFetchRequest<InboxMessage> = InboxMessage.fetchRequest()
            request.predicate = predicate
            let messages = try context.fetch(request)
            for message in messages {
                let theRowStillQualifies: Bool
                switch grounds {
                case .theServerHasConfirmed: theRowStillQualifies = message.deletedFromServer && message.canBeDeletedFromServer
                case .nothingWillEverAskTheServer: theRowStillQualifies = message.canBeDeletedFromServer
                }
                guard theRowStillQualifies else {
                    // The row moved since it was fetched. Leave it to the next round rather than guessing.
                    assertionFailure()
                    continue
                }
                if let directory = try message.deleteInboxMessage(inbox: inbox, given: .theAppIsDoneWithIt) {
                    directoriesToDelete.append(directory)
                }
                numberOfRowsDeleted += 1
            }
        }
        // The count can be smaller than the number of messageIds: a message that no longer exists is not fetched at all, and the
        // `continue` above skips a row that no longer satisfies the conditions for deletion. The caller needs this count, because a
        // count of 0 means that asking again for the same messageIds would delete nothing again.
        return (numberOfRowsDeleted, directoriesToDelete)
    }


    /// Deletes one page of the rows belonging to an owned identity that no longer exists, whatever state those rows are in.
    ///
    /// This is the one deletion in this file that removes a row nobody marked, and what makes it right is that the questions the others ask have nobody left
    /// to answer them: no listing enumerates a profile that is gone, no session can be made for it, and no app side will ever finish with its messages. A row
    /// in any state is therefore rubbish, where the same row under a profile that still exists might be work in progress.
    ///
    /// Returns the attachments' directories to remove once the context is saved, as ``deleteMessagesNeedingNoServerRequest(messageIds:grounds:inbox:within:)``
    /// does, and the number of rows removed, so that a caller paging through a large inbox knows when to stop.
    static func deleteMessagesOfNonExistingOwnedIdentities(existingOwnedCryptoIds: Set<ObvCryptoIdentity>, fetchLimit: Int, inbox: URL, within context: NSManagedObjectContext) throws -> (numberOfRowsDeleted: Int, directoriesToDelete: [URL]) {

        var numberOfRowsDeleted = 0
        var directoriesToDelete = [URL]()

        // An empty set needs no special case: `withMessageIdOwnedCryptoIdIn([])` matches nothing, so its negation matches every row — which is exactly right
        // for a device whose last profile has just been deleted.
        let request: NSFetchRequest<InboxMessage> = InboxMessage.fetchRequest()
        request.predicate = NSCompoundPredicate(notPredicateWithSubpredicate: Predicate.withMessageIdOwnedCryptoIdIn(Array(existingOwnedCryptoIds)))
        request.fetchLimit = fetchLimit
        let messages = try context.fetch(request)

        for message in messages {
            if let directory = try message.deleteInboxMessage(inbox: inbox, given: .itsOwnedIdentityNoLongerExists) {
                directoriesToDelete.append(directory)
            }
            numberOfRowsDeleted += 1
        }

        return (numberOfRowsDeleted, directoriesToDelete)

    }


    /// Removes the attachments' directories handed back by one of the deletions above, once the context has saved.
    ///
    /// Every outcome is reported, including having nothing to remove: this is one of the few places that can take a whole message directory, and a removal
    /// that took a download's bytes with it would otherwise be indistinguishable from silence.
    static func removeAttachmentsDirectoriesOnceSaved(_ directoriesToDelete: [URL], within obvContext: ObvContext) throws {

        guard !directoriesToDelete.isEmpty else { return }

        try obvContext.addContextDidSaveCompletionHandler { error in
            guard error == nil else {
                logger.info("📁 Not removing \(directoriesToDelete.count) attachments directory(ies): the context failed to save")
                return
            }
            for directoryToDelete in directoriesToDelete {
                guard FileManager.default.fileExists(atPath: directoryToDelete.path) else {
                    logger.info("📁 Not removing \(directoryToDelete.path, privacy: .public): there is nothing there any more")
                    continue
                }
                do {
                    try FileManager.default.removeItem(at: directoryToDelete)
                    logger.info("📁 Removed the attachments directory \(directoryToDelete.path, privacy: .public), and every attachment file in it")
                } catch {
                    logger.error("📁 Could not remove the attachments directory \(directoryToDelete.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }

    }


    /// The payloads of the messages named by `messageIds` that are still on hold, keyed by identifier. A message may have left that
    /// state since the caller listed it, and one that has is no longer this method's business.
    ///
    /// This is a dictionary fetch. A row carries its `rawEncryptedContent` inline, so loading the whole object just to read its payload
    /// is the cost worth avoiding.
    static func getPayloadsOfMessagesOnHold(messageIds: [ObvMessageIdentifier], within context: NSManagedObjectContext) throws -> [ObvMessageIdentifier: Data] {

        var payloads = [ObvMessageIdentifier: Data]()

        for predicate in Predicate.predicatesForMessageIdentifiers(messageIds) {

            let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            request.resultType = .dictionaryResultType
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                predicate,
                Predicate.isOnHold(is: true),
            ])
            request.propertiesToFetch = [
                Predicate.Key.rawMessageIdOwnedIdentity.rawValue,
                Predicate.Key.rawMessageIdUid.rawValue,
                Predicate.Key.messagePayload.rawValue,
            ]

            guard let results = try context.fetch(request) as? [[String: Any]] else { assertionFailure(); throw ObvError.couldNotCastFetchedResult }

            for dict in results {
                guard let rawMessageIdOwnedIdentity = dict[Predicate.Key.rawMessageIdOwnedIdentity.rawValue] as? Data else { assertionFailure(); continue }
                guard let rawMessageIdUid = dict[Predicate.Key.rawMessageIdUid.rawValue] as? Data else { assertionFailure(); continue }
                guard let messageId = ObvMessageIdentifier(rawOwnedCryptoIdentity: rawMessageIdOwnedIdentity, rawUid: rawMessageIdUid) else { assertionFailure(); continue }
                // A decrypted message always has one; an undecrypted one is simply not what the caller is looking for, so it is left out rather than asserted on.
                guard let messagePayload = dict[Predicate.Key.messagePayload.rawValue] as? Data else { continue }
                payloads[messageId] = messagePayload
            }

        }

        return payloads

    }


    /// Marks every message named by `messageIds`, and all of their attachments, for deletion. Returns the attachments so marked.
    ///
    /// This fetches objects rather than dictionaries. That is unavoidable here, because marking has to walk each message's attachments.
    static func markMessagesAndAttachmentsForDeletion(messageIds: [ObvMessageIdentifier], within context: NSManagedObjectContext) throws -> [ObvAttachmentIdentifier] {

        var attachmentsMarkedForDeletion = [ObvAttachmentIdentifier]()

        for predicate in Predicate.predicatesForMessageIdentifiers(messageIds) {

            let request: NSFetchRequest<InboxMessage> = InboxMessage.fetchRequest()
            request.predicate = predicate
            let messages = try context.fetch(request)

            for message in messages {
                attachmentsMarkedForDeletion.append(contentsOf: try message.markMessageAndAttachmentsForDeletion(attachmentToMarkForDeletion: .all))
            }

        }

        return attachmentsMarkedForDeletion

    }


    /// Marks the message and all this attachments for deletion. Since they are all marked for deletion, we expect ``canBeDeletedFromServer`` to `true`.
    static func markMessageAndAttachmentsForDeletion(messageId: ObvMessageIdentifier, within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<InboxMessage> = InboxMessage.fetchRequest()
        request.predicate = Predicate.withMessageIdentifier(messageId)
        request.fetchLimit = 1
        request.propertiesToFetch = [Predicate.Key.markedForDeletion.rawValue]
        guard let message = (try context.fetch(request)).first else { return }
        // Nothing to cancel: this is called while processing a message the app will never see, so no download was ever resumed for it.
        _ = try message.markMessageAndAttachmentsForDeletion(attachmentToMarkForDeletion: .all)
        assert(message.canBeDeletedFromServer)
    }
    
    
    /// Returns a set of all the remote identities we are waiting to become contacts before re-processing messages. This is used during bootstrap so as to make
    /// sure those remote identities did not become contacts.
    static func getExpectedContactsForReProcessing(within context: NSManagedObjectContext) throws -> Set<ObvContactIdentifier> {
        let request: NSFetchRequest<InboxMessage> = InboxMessage.fetchRequest()
        request.fetchBatchSize = 500
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.isExpectingContactForReProcessing,
            Predicate.cannotBeDeletedFromServer,
        ])
        request.propertiesToFetch = [
            Predicate.Key.rawMessageIdOwnedIdentity.rawValue,
            Predicate.Key.rawExpectedContactForReProcessing.rawValue,
        ]
        let messages = try context.fetch(request)
        return Set(messages.compactMap({ $0.expectedContactForReProcessing }))
    }
    
    
    static func removeExpectedContactForReProcessing(contactIdentifier: ObvContactIdentifier, within context: NSManagedObjectContext) throws -> Bool {
        let request: NSFetchRequest<InboxMessage> = InboxMessage.fetchRequest()
        request.fetchBatchSize = 500
        request.predicate = Predicate.withExpectedContactForReProcessing(contactIdentifier: contactIdentifier)
        request.propertiesToFetch = []
        let messages = try context.fetch(request)
        messages.forEach { $0.rawExpectedContactForReProcessing = nil }
        let didRemoveExpectedContactForReProcessing = !messages.isEmpty
        return didRemoveExpectedContactForReProcessing
    }
    
    
    /// Inbox messages expecting a contact before re-processing shall be deleted after a certain retention period.
    static func markMessagesAndAttachmentsForDeletionIfOldAndExpectingContactForReProcessing(with context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<InboxMessage> = InboxMessage.fetchRequest()
        request.fetchBatchSize = 500
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.hasSomeExpectedContactForReProcessing,
            Predicate.downloadTimestampFromServer(earlierThan: Date.now.addingTimeInterval(-ObvConstants.inboxMessageRetentionWhenContactIsExpected))
        ])
        request.propertiesToFetch = [Predicate.Key.markedForDeletion.rawValue]
        let messages = try context.fetch(request)
        try messages.forEach { message in
            assertionFailure("During development, it is unlikely to reach this point")
            // Nothing to cancel: a message still expecting a contact was never processed, so no download was ever resumed for it.
            _ = try message.markMessageAndAttachmentsForDeletion(attachmentToMarkForDeletion: .all)
        }
    }

}


// MARK: - Counting the inbox, for the diagnostics the app can show

extension InboxMessage {

    /// Whose messages a question is about.
    ///
    /// **Named, and never defaulted, because the two answers belong to two different questions and the wrong one is silently plausible.** A figure about
    /// the *store* — how many rows are there, what is the oldest — wants every profile. A figure about *work outstanding* wants only the active ones: the
    /// listing enumerates `getOwnedIdentities(restrictToActive: true)`, and the batches that decrypt and delete are both per owned identity, so a message
    /// of a deactivated profile is one nothing will ever move and counting it as work is a claim that something will.
    ///
    /// This was an optional argument defaulting to *every profile* until 2026-09-13, which made the wrong answer the one a caller got by saying nothing —
    /// and one had: the Engine-diagnostics rows counted every profile while the Inbox-maintenance rows beside them counted the active ones, so a device
    /// with a deactivated profile showed two figures that no arithmetic reconciled. Requiring the scope is what stops the next call site repeating it.
    enum OwnedIdentityScope {

        /// Every message, whatever it belongs to.
        case everyProfile

        /// Only messages belonging to one of these — in practice, the active profiles.
        case theseProfiles([ObvCryptoIdentity])

        fileprivate var predicate: NSPredicate? {
            switch self {
            case .everyProfile: return nil
            case .theseProfiles(let ownedCryptoIdentities): return Predicate.withMessageIdOwnedCryptoIdIn(ownedCryptoIdentities)
            }
        }

    }


    /// A population of inbox messages worth counting.
    ///
    /// Named here rather than left to the caller so that the predicates stay with the entity, and so that a count and the age of that population's oldest
    /// member cannot drift apart: both read this one definition.
    enum Population: CaseIterable {
        case all
        case notYetDecrypted
        case awaitingTheApp
        case onHold
        case markedForDeletion
        case awaitingAContactForReProcessing
        case markedAsListedOnTheServer
        case deletedFromTheServer
        case withAtLeastOneAttachment
        /// Those that ought to have a directory on disk: an attachment's directory is made when its message is decrypted, so an undecrypted one has none
        /// yet. This is the count to compare the inbox's contents against.
        case decryptedWithAtLeastOneAttachment
        /// Ordinary, and usually the largest of these: a message whose attachments the reader has not asked for yet.
        case markedForDeletionYetNotDeletableFromTheServer

        fileprivate var predicate: NSPredicate? {
            switch self {
            case .all: return nil
            case .notYetDecrypted: return Predicate.toBeProcessByChannel
            case .awaitingTheApp: return Predicate.toBeProcessByApp
            case .onHold: return Predicate.isOnHold(is: true)
            case .markedForDeletion: return Predicate.isMarkedForDeletion
            case .awaitingAContactForReProcessing: return Predicate.isExpectingContactForReProcessing
            case .markedAsListedOnTheServer: return Predicate.markedAsListedOnServerIs(true)
            case .deletedFromTheServer: return Predicate.deletedFromServerIs(true)
            case .withAtLeastOneAttachment: return Predicate.hasAtLeastOneAttachment
            case .decryptedWithAtLeastOneAttachment:
                return NSCompoundPredicate(andPredicateWithSubpredicates: [
                    Predicate.hasAtLeastOneAttachment,
                    Predicate.hasFromIdentityAndMessagePayload,
                ])
            case .markedForDeletionYetNotDeletableFromTheServer: return Predicate.isMarkedForDeletionYetCannotBeDeletedFromServer
            }
        }
    }


    /// Counts, without materialising a single row.
    ///
    /// That is not a nicety here: an affected device is thought to hold six figures of these, and a row carries its whole encrypted content inline, so a
    /// diagnostic that fetched them would be worse than no diagnostic at all.
    /// - Parameter scope: whose messages to count. Has no default on purpose — see ``OwnedIdentityScope``. A count of work outstanding wants
    /// `.theseProfiles(the active ones)`; a count describing the store wants `.everyProfile`, and then
    /// ``countOfMessagesBelongingToNoneOf(_:within:)`` is what explains the difference between the two.
    static func count(_ population: Population, over scope: OwnedIdentityScope, within context: NSManagedObjectContext) throws -> Int {
        let request = NSFetchRequest<InboxMessage>(entityName: Self.entityName)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            population.predicate,
            scope.predicate,
        ].compactMap { $0 })
        return try context.count(for: request)
    }


    /// How many messages belong to none of these owned identities — in practice, to a profile that is no longer active.
    ///
    /// **A count of the stranded, and it exists so that a report's parts can be reconciled with its total.** Once the work-owed counts are restricted to the
    /// active identities they no longer sum to ``Population/all``, and an unexplained gap in a diagnostic is worse than no figure at all. This is the gap.
    ///
    /// Nothing lists, decrypts, marks or sweeps a message of an inactive identity: the listing enumerates `getOwnedIdentities(restrictToActive: true)`, and
    /// the batch that processes and the batch that deletes are both per owned identity. Deactivation itself leaves the inbox untouched, deliberately —
    /// deactivation is reversible and those messages may still be wanted — so the rows simply stay until the profile is reactivated or deleted.
    static func countOfMessagesBelongingToNoneOf(_ ownedCryptoIdentities: [ObvCryptoIdentity], within context: NSManagedObjectContext) throws -> Int {
        let request = NSFetchRequest<InboxMessage>(entityName: Self.entityName)
        request.predicate = NSCompoundPredicate(notPredicateWithSubpredicate: Predicate.withMessageIdOwnedCryptoIdIn(ownedCryptoIdentities))
        return try context.count(for: request)
    }


    /// When the oldest message of this population reached the server, or nil if the population is empty.
    ///
    /// Worth as much as the count beside it: a thousand undecrypted messages an hour old is a device catching up, and the same thousand three weeks old is
    /// a device that is stuck.
    static func dateOfTheOldestMessage(in population: Population, over scope: OwnedIdentityScope, within context: NSManagedObjectContext) throws -> Date? {
        let request = NSFetchRequest<NSDictionary>(entityName: Self.entityName)
        request.resultType = .dictionaryResultType
        // Scoped exactly as the count beside it is, which is the promise written on ``Population``: an age and a count of the same population must not be
        // answering about different sets of profiles.
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            population.predicate,
            scope.predicate,
        ].compactMap { $0 })
        request.propertiesToFetch = [Predicate.Key.messageUploadTimestampFromServer.rawValue]
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.messageUploadTimestampFromServer.rawValue, ascending: true)]
        request.fetchLimit = 1
        guard let item = try context.fetch(request).first else { return nil }
        return item[Predicate.Key.messageUploadTimestampFromServer.rawValue] as? Date
    }


    /// The three timestamps of the most recently uploaded messages we still hold, newest first.
    ///
    /// Two differences of these are worth reading. `downloadTimestampFromServer − messageUploadTimestampFromServer` is on the server's clock alone, so it
    /// says how long a message waited before we listed it with no clock skew in the way. `localDownloadTimestamp − downloadTimestampFromServer` compares
    /// this device's clock against the server's at what is nearly the same instant, so it is an estimate of the skew itself.
    ///
    /// **The population is biased and any reading of it has to say so**: rows leave the inbox once the app has finished with them, so the ones that survive
    /// are the ones that did not. This describes the messages that are stuck, not ordinary traffic.
    static func timestampsOfTheMostRecentMessages(limit: Int, within context: NSManagedObjectContext) throws -> [(messageUploadTimestampFromServer: Date, downloadTimestampFromServer: Date, localDownloadTimestamp: Date)] {
        let uploadKey = Predicate.Key.messageUploadTimestampFromServer.rawValue
        let downloadKey = Predicate.Key.downloadTimestampFromServer.rawValue
        let localKey = Predicate.Key.localDownloadTimestamp.rawValue
        let request = NSFetchRequest<NSDictionary>(entityName: Self.entityName)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = [uploadKey, downloadKey, localKey]
        request.sortDescriptors = [NSSortDescriptor(key: uploadKey, ascending: false)]
        request.fetchLimit = limit
        return try context.fetch(request).compactMap { item in
            guard let upload = item[uploadKey] as? Date,
                  let download = item[downloadKey] as? Date,
                  let local = item[localKey] as? Date else { return nil }
            return (upload, download, local)
        }
    }


    /// What the inbox holds in the way of discussion shared settings.
    struct DiscussionSharedSettingsTally {

        /// How many decrypted messages are a shared-settings item and nothing else.
        let numberOfMessages: Int

        /// How many decrypted payloads had to be read to find them. **The denominator**: without it the figure above cannot be read at all.
        let numberOfPayloadsExamined: Int

        /// These three *are* a partition of ``numberOfMessages``, which the inbox populations counted above are deliberately not: every message examined here
        /// already satisfies `hasFromIdentityAndMessagePayload`, and given that, `awaitingTheApp` is exactly *neither marked for deletion nor on hold* — which
        /// is the whole of ``Predicate/toBeProcessByApp``. So they add up, and a reader may check that they do.
        let awaitingTheApp: Int
        let onHold: Int
        let markedForDeletion: Int

        /// When the oldest of them reached the server, or nil when there are none. Worth as much as the count: a thousand of these an hour old is a device
        /// catching up, and the same thousand three weeks old is a device that will never get through them.
        let dateOfTheOldest: Date?

    }


    /// How many identifiers may go into one `IN` clause.
    ///
    /// `NSPredicate(_:in:)` asserts below 150, and `FyleMessageJoinWithStatus.filterSha256sOfFylesStillAwaitedByAJoin` slices the same shape at a hundred.
    private static var numberOfIdentifiersPerFetch: Int { 100 }


    /// How many payloads are read in one go. Small enough that a device holding six figures of messages never holds more than a few megabytes of them, large
    /// enough that the number of queries stays in single figures.
    private static var numberOfPayloadsReadAtOnce: Int { 10_000 }


    /// Counts the decrypted messages whose payload is a discussion-shared-settings item, and describes them.
    ///
    /// **The one figure here that reads a column rather than counting rows**, unavoidably: `messagePayload` is a `Binary` attribute, so no `NSPredicate` can
    /// express this question — which is also why it cannot be a ``Population``, a `Population` being a predicate. It is fetch-then-filter.
    ///
    /// It materialises nothing — a dictionary fetch, so `rawEncryptedContent` stays in the store — and it is paged, with an autorelease pool per page. The
    /// pool is the part that bounds memory; paging alone bounds only how many rows are *asked for*.
    ///
    /// **The figure is an estimate on a device that is deleting**, deliberately: paging by offset loses a row whenever one is deleted below it. The comment
    /// on the sort descriptors says what the exact alternative would have cost.
    ///
    /// - Parameter scope: whose messages to count. `.everyProfile` is the question meant here — a deactivated profile's settings messages are still in the
    /// database, and are exactly what accumulates unnoticed.
    static func tallyOfTheDiscussionSharedSettingsMessages(over scope: OwnedIdentityScope, within context: NSManagedObjectContext) throws -> DiscussionSharedSettingsTally {

        let payloadKey = Predicate.Key.messagePayload.rawValue
        let onHoldKey = Predicate.Key.isOnHold.rawValue
        let markedForDeletionKey = Predicate.Key.markedForDeletion.rawValue
        let uploadKey = Predicate.Key.messageUploadTimestampFromServer.rawValue

        var numberOfMessages = 0
        var numberOfPayloadsExamined = 0
        var awaitingTheApp = 0
        var onHold = 0
        var markedForDeletion = 0
        var dateOfTheOldest: Date?

        var offset = 0

        while true {

            let request = NSFetchRequest<NSDictionary>(entityName: Self.entityName)
            request.resultType = .dictionaryResultType
            // Only the decrypted ones: an undecrypted row has no payload to test, and asking about one would put it in the denominator as though it had been
            // examined and found not to match.
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.hasFromIdentityAndMessagePayload,
                scope.predicate,
            ].compactMap { $0 })
            request.propertiesToFetch = [payloadKey, onHoldKey, markedForDeletionKey, uploadKey]
            // **The sort makes the paging stable, and does nothing else.** An offset into an unordered result is an offset into a different result each
            // time, counting some rows twice and missing others.
            //
            // It cannot make the paging stable against the store being *written to*, and this one is: three extensions share it, and the inbox drain deletes
            // messages while this runs. Each row deleted below the offset shifts the remainder up and one live row is never visited, so the tally can
            // under-report — `numberOfMessages` and `numberOfPayloadsExamined` together, which is why they stay consistent with each other while both drift
            // low. **Accepted deliberately.** The exact alternative is a cursor, which on these columns needs `>` on a `Binary` attribute: sound in SQLite,
            // fatal the moment anything evaluates it in memory, `NSData` having no `compare:` — the crash `FetchedResultsControllerSortDescriptorTests`
            // exists to prevent. Not worth putting within reach of every future fetch in this file for an exact figure on a diagnostics panel. Nothing below depends on the order — the oldest is taken as a minimum over the
            // matches rather than as the first of them — so this stays correct however the store chooses to answer.
            //
            // It sorts on the **uniqueness constraint** for two reasons. It is a *total* order, where a timestamp is not — messages sharing one could be
            // ordered differently from page to page, and rows counted twice or missed. And SQLite's unique index behind that constraint is on exactly these
            // two columns in this order, so the rows come back sorted with no sort performed, where a timestamp would sort the whole table once per page.
            //
            // These are `Binary` attributes, which a *fetched results controller* must never be given: it places a merged row in memory by sending
            // `compare:` to the sort values, and `NSData` does not implement it. That is not this. A plain fetch orders in SQLite, which orders blobs happily.
            request.sortDescriptors = [
                NSSortDescriptor(key: Predicate.Key.rawMessageIdOwnedIdentity.rawValue, ascending: true),
                NSSortDescriptor(key: Predicate.Key.rawMessageIdUid.rawValue, ascending: true),
            ]
            request.fetchOffset = offset
            request.fetchLimit = Self.numberOfPayloadsReadAtOnce

            // **The pool is what makes the paging mean anything.** Core Data returns these rows as autoreleased dictionaries holding autoreleased `NSData`,
            // and their pool is the one around the whole diagnostics pass — so without this, every page stays resident and the scan ends up holding the entire
            // `messagePayload` column. Measured over 20'000 rows of 4KB: +10.3MB per page, linear, 105.6MB by the end, against a flat 13.3MB with the pool.
            let numberOfItemsInPage: Int = try autoreleasepool {

                let items = try context.fetch(request)

                for item in items {
                    numberOfPayloadsExamined += 1
                    guard let payload = item[payloadKey] as? Data else { continue }
                    guard ObvDiscussionSharedSettingsPayload.isADiscussionSharedSettingsItem(payload) else { continue }
                    numberOfMessages += 1
                    if let date = item[uploadKey] as? Date, date < (dateOfTheOldest ?? .distantFuture) {
                        dateOfTheOldest = date
                    }
                    if (item[markedForDeletionKey] as? NSNumber)?.boolValue == true {
                        markedForDeletion += 1
                    } else if (item[onHoldKey] as? NSNumber)?.boolValue == true {
                        onHold += 1
                    } else {
                        awaitingTheApp += 1
                    }
                }

                return items.count

            }

            // A short page — an empty one included — is the end of the table.
            guard numberOfItemsInPage == Self.numberOfPayloadsReadAtOnce else { break }
            offset += numberOfItemsInPage

        }

        return DiscussionSharedSettingsTally(numberOfMessages: numberOfMessages,
                                             numberOfPayloadsExamined: numberOfPayloadsExamined,
                                             awaitingTheApp: awaitingTheApp,
                                             onHold: onHold,
                                             markedForDeletion: markedForDeletion,
                                             dateOfTheOldest: dateOfTheOldest)

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
        case couldNotCreateAttachmentsDirectory
        case couldNotDeleteAttachmentsDirectory
        case incoherentFromIdentity
        case incoherentFromContactDevice
        case incoherentMessagePayload
        case couldNotCastFetchedResult
        case aMessageWithTheSameMessageIdAlreadyExists
        case tryingToInsertAMessageThatWasAlreadyDeleted
    }
    
}
