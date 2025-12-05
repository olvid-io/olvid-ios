/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvCrypto
import ObvTypes
import ObvEncoder
import ObvMetaManager

@objc(InboxAttachment)
final class InboxAttachment: NSManagedObject {
    
    private static let logger = Logger(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: "InboxAttachment")

    // MARK: Internal constants
    
    private static let entityName = "InboxAttachment"

    enum Status: Int, CustomDebugStringConvertible {
        case paused = 0
        case resumeRequested = 1
        case downloaded = 2
        case cancelledByServer = 3
        case markedForDeletion = 4
        
        var debugDescription: String {
            switch self {
            case .paused: return "Paused"
            case .resumeRequested: return "Resume Requested"
            case .downloaded: return "Downloaded"
            case .cancelledByServer: return "Cancelled by server"
            case .markedForDeletion: return "Marked for deletion"
            }
        }
        
        var toObvNetworkFetchReceivedAttachmentStatus: ObvNetworkFetchReceivedAttachment.Status {
            switch self {
            case .paused: return .paused
            case .resumeRequested: return .resumed
            case .downloaded: return .downloaded
            case .cancelledByServer: return .cancelledByServer
            case .markedForDeletion: return .markedForDeletion
            }
        }
        
        var toObvAttachmentStatus: ObvAttachment.Status {
            switch self {
            case .paused: return .paused
            case .resumeRequested: return .resumed
            case .downloaded: return .downloaded
            case .cancelledByServer: return .cancelledByServer
            case .markedForDeletion: return .markedForDeletion
            }
        }
    }

    // MARK: Attributes
    
    @NSManaged private(set) var attachmentNumber: Int
    @NSManaged private var encodedAuthenticatedDecryptionKey: Data?
    @NSManaged private(set) var expectedChunkLength: Int
    @NSManaged private(set) var initialByteCountToDownload: Int // The number of (encrypted) bytes we need to receive to eventually obtain the full file
    @NSManaged private(set) var metadata: Data?
    @NSManaged private var rawMessageIdOwnedIdentity: Data? // Expected to be non-nil. Non nil in the model. This is just to make sure we do not crash when accessing this attribute on a deleted instance.
    @NSManaged private var rawMessageIdUid: Data? // Expected to be non-nil. Non nil in the model. This is just to make sure we do not crash when accessing this attribute on a deleted instance.
    @NSManaged private var rawStatus: Int

    // MARK: Relationships
    
    private(set) var chunks: [InboxAttachmentChunk] {
        get {
            guard let unsortedChunks = kvoSafePrimitiveValue(forKey: Predicate.Key.chunks.rawValue) as? Set<InboxAttachmentChunk> else { return [] }
            let items: [InboxAttachmentChunk] = unsortedChunks.sorted(by: { $0.chunkNumber < $1.chunkNumber })
            return items
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: Predicate.Key.chunks.rawValue)
        }
    }

    // We do not expect the message to be nil, since cascade deleting a message delete its attachments
    var message: InboxMessage? {
        get {
            let value = kvoSafePrimitiveValue(forKey: Predicate.Key.message.rawValue) as? InboxMessage
            return value
        }
        set {
            guard let value = newValue else { assertionFailure(); return }
            self.messageId = value.messageId
            kvoSafeSetPrimitiveValue(value, forKey: Predicate.Key.message.rawValue)
        }
    }
    
    @NSManaged private(set) var session: InboxAttachmentSession?

    
    // MARK: Other variables
    
    private func setAuthenticatedEncryptionKey(to key: AuthenticatedEncryptionKey) {
        let encodedKey = key.obvEncode()
        self.encodedAuthenticatedDecryptionKey = encodedKey.rawData
    }
    
    
    var key: AuthenticatedEncryptionKey? {
        guard let encodedKeyData = self.encodedAuthenticatedDecryptionKey else { return nil }
        guard let encodedKey = ObvEncoded(withRawData: encodedKeyData) else { assertionFailure(); return nil }
        do {
            return try AuthenticatedEncryptionKeyDecoder.decode(encodedKey)
        } catch {
            assertionFailure()
            return nil
        }
    }

    
    var downloadPaused: Bool {
        return self.status == .paused
    }
    
    var markedForDeletion: Bool {
        return self.status == .markedForDeletion
    }
    
    var isDownloaded: Bool {
        return self.status == .downloaded
    }
    
    func tryChangeStatusToDownloaded() throws {
        let allChunksAreDownloaded = chunks.allSatisfy({ $0.cleartextChunkWasWrittenToAttachmentFile })
        guard allChunksAreDownloaded else { throw ObvError.tryingToChangeTheStatusToDownloadedButAtLeastOneChunkIsNotDownloadedYet }
        self.status = .downloaded
    }
    
    private(set) var status: Status {
        get { return Status(rawValue: self.rawStatus)! }
        set { self.rawStatus = newValue.rawValue }
    }
    
    var fromCryptoIdentity: ObvCryptoIdentity? {
        return message?.fromCryptoIdentity
    }
    
    var canBeDownloaded: Bool {
        return key != nil && metadata != nil && fromCryptoIdentity != nil
    }
    
    /// This identifier is expected to be non nil, unless the associated `InboxMessage` was deleted on another thread.
    private(set) var messageId: ObvMessageIdentifier? {
        get {
            guard let rawMessageIdOwnedIdentity else { return nil }
            guard let rawMessageIdUid else { return nil }
            return ObvMessageIdentifier(rawOwnedCryptoIdentity: rawMessageIdOwnedIdentity, rawUid: rawMessageIdUid)
        }
        set {
            guard let newValue else { assertionFailure(); return }
            self.rawMessageIdOwnedIdentity = newValue.ownedCryptoIdentity.getIdentity()
            self.rawMessageIdUid = newValue.uid.raw
        }
    }

    /// This identifier is expected to be non nil, unless the associated `InboxMessage` was deleted on another thread.
    var attachmentId: ObvAttachmentIdentifier? {
        guard let messageId else { return nil }
        return ObvAttachmentIdentifier(messageId: messageId, attachmentNumber: attachmentNumber)
    }

    func getURL(withinInbox inbox: URL) -> URL? {
        let attachmentFileName = "\(attachmentNumber)"
        let url = message?.getAttachmentsDirectory(withinInbox: inbox)?.appendingPathComponent(attachmentFileName)
        return url
    }
    
    override var debugDescription: String {
        return "InboxAttachment(messageId: \(messageId.debugDescription), attachmentNumber: \(attachmentNumber))"
    }
    
    var currentChunkProgresses: [(totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64)] {
        self.chunks.map {
            let completedUnitCount = $0.cleartextChunkWasWrittenToAttachmentFile ? $0.ciphertextChunkLength : 0
            return (Int64(completedUnitCount), Int64($0.ciphertextChunkLength))
        }
    }

    // MARK: - Initializer
    
    convenience init?(message: InboxMessage, attachmentNumber: Int, byteCountToDownload: Int, expectedChunkLength: Int, within context: NSManagedObjectContext) throws {

        guard let inboxMessageId = message.messageId else {
            assertionFailure()
            throw ObvError.couldNotDetermineMessageId
        }
        
        let attachmentId = ObvAttachmentIdentifier(messageId: inboxMessageId, attachmentNumber: attachmentNumber)
        
        guard try InboxAttachment.get(attachmentId: attachmentId, within: context) == nil else { return nil }

        let entityDescription = NSEntityDescription.entity(forEntityName: InboxAttachment.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.attachmentNumber = attachmentNumber
        self.expectedChunkLength = expectedChunkLength
        self.initialByteCountToDownload = byteCountToDownload
        self.rawStatus = Status.paused.rawValue
        
        self.message = message
        
        // Create the chunks
        let chunkValues = InboxAttachment.computeEncryptedChunksValues(initialByteCountToDownload: byteCountToDownload, encryptedChunkTypicalLength: expectedChunkLength)
        for chunkNumber in 0..<chunkValues.requiredNumberOfChunks {
            let ciphertextChunkLength = chunkNumber < chunkValues.requiredNumberOfChunks-1 ? self.expectedChunkLength : chunkValues.lastEncryptedChunkLength
            _ = InboxAttachmentChunk(attachment: self, chunkNumber: chunkNumber, ciphertextChunkLength: ciphertextChunkLength)
        }
        
    }


    private static func computeEncryptedChunksValues(initialByteCountToDownload: Int, encryptedChunkTypicalLength: Int) -> (lastEncryptedChunkLength: Int, requiredNumberOfChunks: Int) {
        let requiredNumberOfChunks = 1 + (initialByteCountToDownload-1) / encryptedChunkTypicalLength
        let lastEncryptedChunkLength = initialByteCountToDownload - (requiredNumberOfChunks-1) * encryptedChunkTypicalLength
        return (lastEncryptedChunkLength, requiredNumberOfChunks)
    }

}


// MARK: - Status management

extension InboxAttachment {

    private func canTransistionToNewStatus(_ newStatus: Status) -> Bool {
        guard self.status != newStatus else {
            return true
        }
        guard newStatus != .markedForDeletion && newStatus != .cancelledByServer else {
            // We can always mark the attachment for deletion or cancelled by server
            return true
        }
        switch (self.status, newStatus) {
        case (.paused, .resumeRequested),
             (.resumeRequested, .paused),
            (.resumeRequested, .downloaded):
            return true
        default:
            return false
        }
    }
    
    
    func resetStatusIfCurrentStatusIsDownloadedAndFileIsNotAvailable(withinInbox inbox: URL) throws {
        guard status == .downloaded else { assertionFailure("Why did we call this method?"); return }
        guard let url = getURL(withinInbox: inbox) else { return }
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        // If we reach this point, the attachment status is "downloaded" although the file does not exist on disk.
        // We force the status back to paused
        try changeStatus(to: .paused, forceStatusChange: true)
        chunks.forEach { chunk in
            chunk.resetDownload()
        }
    }
    
    
    private func changeStatus(to newStatus: Status, forceStatusChange: Bool = false) throws {
        guard newStatus != self.status else { return }
        guard canTransistionToNewStatus(newStatus) || forceStatusChange else {
            if self.status == .markedForDeletion && newStatus == .paused {
                // Do not throw, we always pause a download right after deleting an attachment, so this case happens
                return
            } else {
                throw ObvError.cannotTransitionFromCurrentStatusToNewStatus(currentStatus: status, newStatus: newStatus)
            }
        }
        self.status = newStatus
    }
    
    
    /// Shall only be called from ``InboxMessage.markMessageAndAttachmentsForDeletion(attachmentToMarkForDeletion:)``
    func markForDeletion() {
        do {
            try changeStatus(to: .markedForDeletion)
        } catch {
            assert(false)
        }
    }
    

    func markAsCancelledByServer() {
        do {
            try changeStatus(to: .cancelledByServer)
        } catch {
            assert(false)
        }
    }
    
    func resumeDownload() throws {
        try changeStatus(to: .resumeRequested)
    }
    
    
    func pauseDownload() throws {
        try changeStatus(to: .paused)
    }

    
    /// Returns the URL of the file to delete once the context is saved
    func deleteDownload(fromInbox inbox: URL) throws -> URL {
        guard let url = getURL(withinInbox: inbox) else { throw ObvError.cannotGetAttachmentURL }
        try changeStatus(to: .markedForDeletion) // This cannot fail
        for chunk in chunks {
            do {
                try chunk.deleteInboxAttachmentChunk()
            } catch {
                assertionFailure() // In production, continue with the next chunk
            }
        }
        return url
    }

    
    var attachmentFileIsComplete: Bool {
        return chunks.allSatisfy({ $0.cleartextChunkWasWrittenToAttachmentFile })
    }
    
    func createSession() -> InboxAttachmentSession? {
        assert(self.session == nil)
        return InboxAttachmentSession(attachment: self)
    }
    
}


// MARK: - Signed URLS related methods

extension InboxAttachment {
    
    var allChunksHaveSignedURLs: Bool {
        return chunks.allSatisfy { $0.signedURL != nil }
    }
    
    func setChunksSignedURLs(_ urls: [URL]) throws {
        guard urls.count == chunks.count else { assertionFailure(); throw ObvError.unexpectedNumberOfSignedURLsWrtTheNumberOfChunks }
        for (chunk, url) in zip(chunks, urls) {
            chunk.signedURL = url
        }
        assert(allChunksHaveSignedURLs)
    }
    
    func deleteAllChunksSignedURLs() {
        for chunk in chunks {
            chunk.signedURL = nil
        }
    }

}


// MARK: - Setting the decryption key, creating the InboxAttachmentChunks, and creating the sparse file for writing down the decrypted chunks

extension InboxAttachment {
    
    /// This method is called as soon as the attachment decryption key and metadata are available. In addition to storing these values, this method creates all the required `InboxAttachmentChunk` instances.
    /// This method also creates an empty sparse file allowing to write down the decrypted chunks as soon as they are made available.
    func set(decryptionKey key: AuthenticatedEncryptionKey, metadata: Data, inbox: URL) throws {

        guard self.key == nil else {
            assertionFailure()
            throw ObvError.theDecryptionKeyCanOnlyBeSetOnce
        }
        guard self.metadata == nil else {
            assertionFailure()
            throw ObvError.theMetadataCanOnlyBeSetOnce
        }
        
        self.metadata = metadata
        self.setAuthenticatedEncryptionKey(to: key)

        // Now that we now about the decryption key, we know about the algorithm that will be used to decrypt the chunks. We can deduce the plaintext chunk size, thus, the final size of the file. We create this empty file now and set the individual chunks cleartext sizes
        var totalCleartextLength = 0
        do {
            for chunk in self.chunks {
                totalCleartextLength += try chunk.setCleartextChunkLengthForDecryptionKey(key)
            }
        } catch {
            self.markAsCancelledByServer()
            return
        }
        try createEmptyFileForWritingChunks(withinInbox: inbox, cleartextLength: totalCleartextLength)
        
    }

    
    private func createEmptyFileForWritingChunks(withinInbox inbox: URL, cleartextLength: Int) throws {
        
        guard let url = getURL(withinInbox: inbox) else { throw ObvError.cannotGetAttachmentURL }

        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch let error {
                throw ObvError.couldNotDeleteAttachmentFile(atUrl: url, error: error)
            }
        }
        
        guard let message = self.message else {
            assertionFailure()
            throw ObvError.couldNotCreateAttachmentFile(error: nil)
        }
        
        try message.createAttachmentsDirectoryIfRequired(withinInbox: inbox)
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil) else {
            throw ObvError.couldNotCreateAttachmentFile(error: nil)
        }
        
        guard let fh = FileHandle(forWritingAtPath: url.path) else {
            throw ObvError.couldNotGetFileHandle
        }
        fh.seek(toFileOffset: UInt64(cleartextLength))
        fh.closeFile()
        
    }

    
    var plaintextLength: Int64? {
        let cleartextChunksLengths = chunks.compactMap({ $0.cleartextChunkLength })
        // The following test fails if the decryption key has not been set yet
        guard cleartextChunksLengths.count == chunks.count else { return nil }
        let length = cleartextChunksLengths.reduce(0, +)
        return Int64(length)
    }
    
}

// MARK: - Decrypting and writing chunks down to a file

extension InboxAttachment {
    
    func setCleartextChunkWasWrittenToAttachmentFile(chunkNumber: Int) throws {
        
        guard chunkNumber < chunks.count else {
            assertionFailure()
            throw ObvError.unexpectedChunkNumber
        }
        
        chunks[chunkNumber].setCleartextChunkWasWrittenToAttachmentFile()

        let allCleartextChunksWereWrittenToAttachmentFile = chunks.allSatisfy({ $0.cleartextChunkWasWrittenToAttachmentFile })
        if allCleartextChunksWereWrittenToAttachmentFile {
            status = .downloaded
        }
        
    }
    
}


// MARK: - Getting an ObvAttachment

extension InboxAttachment {
    
    func getObvAttachment(fromCryptoIdentity: ObvContactIdentifier, messageUploadTimestampFromServer: Date, inbox: URL) -> ObvAttachment? {
        
        guard let attachmentId = self.attachmentId else { assertionFailure(); return nil }
        guard let metadata = self.metadata else { assertionFailure(); return nil }

        let totalUnitCount: Int64
        if self.status == .cancelledByServer {
            totalUnitCount = 0
        } else {
            guard let _totalUnitCount = self.plaintextLength else {
                Self.logger.fault("Could not find cleartext attachment size. The file might not exist yet (which is the case if the decryption key has not been set).")
                assertionFailure()
                return nil
            }
            totalUnitCount = _totalUnitCount
        }

        guard let inboxAttachmentUrl = self.getURL(withinInbox: inbox) else {
            Self.logger.fault("Cannot determine the inbox attachment URL")
            return nil
        }

        return ObvAttachment(fromContactIdentity: fromCryptoIdentity,
                             metadata: metadata,
                             totalUnitCount: totalUnitCount,
                             url: inboxAttachmentUrl,
                             status: self.status.toObvAttachmentStatus,
                             attachmentId: attachmentId,
                             messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        
    }
    
    
    func getObvOwnedAttachment(messageUploadTimestampFromServer: Date, inbox: URL) -> ObvOwnedAttachment? {
        
        guard let attachmentId = self.attachmentId else { assertionFailure(); return nil }
        guard let metadata = self.metadata else { assertionFailure(); return nil }

        let totalUnitCount: Int64
        if self.status == .cancelledByServer {
            totalUnitCount = 0
        } else {
            guard let _totalUnitCount = self.plaintextLength else {
                Self.logger.fault("Could not find cleartext attachment size. The file might not exist yet (which is the case if the decryption key has not been set).")
                assertionFailure()
                return nil
            }
            totalUnitCount = _totalUnitCount
        }

        guard let inboxAttachmentUrl = self.getURL(withinInbox: inbox) else {
            Self.logger.fault("Cannot determine the inbox attachment URL")
            return nil
        }

        return ObvOwnedAttachment(metadata: metadata,
                                  totalUnitCount: totalUnitCount,
                                  url: inboxAttachmentUrl,
                                  status: self.status.toObvAttachmentStatus,
                                  attachmentId: attachmentId,
                                  messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        
    }
}


// MARK: - Errors

extension InboxAttachment {
    
    enum ObvError: Error {
        case unexpectedChunkNumber
        case noContext
        case theDecryptionKeyCanOnlyBeSetOnce
        case theMetadataCanOnlyBeSetOnce
        case chunksInstancesCanBeCreatedOnlyOnce
        case couldNotDeleteAttachmentFile(atUrl: URL, error: Error)
        case couldNotCreateAttachmentFile(error: Error?)
        case couldNotWrite(atUrl: URL, error: Error)
        case couldNotDetermineMessageId
        case cannotTransitionFromCurrentStatusToNewStatus(currentStatus: Status, newStatus: Status)
        case cannotGetAttachmentURL
        case unexpectedNumberOfSignedURLsWrtTheNumberOfChunks
        case couldNotGetFileHandle
        case tryingToChangeTheStatusToDownloadedButAtLeastOneChunkIsNotDownloadedYet
    }

}


// MARK: - Convenience DB getters

extension InboxAttachment {
    
    struct Predicate {
        enum Key: String {
            // Attributes
            case attachmentNumber = "attachmentNumber"
            case encodedAuthenticatedDecryptionKey = "encodedAuthenticatedDecryptionKey"
            case expectedChunkLength = "expectedChunkLength"
            case initialByteCountToDownload = "initialByteCountToDownload"
            case metadata = "metadata"
            case rawMessageIdOwnedIdentity = "rawMessageIdOwnedIdentity"
            case rawMessageIdUid = "rawMessageIdUid"
            case rawStatus = "rawStatus"
            // Relationships
            case chunks = "chunks"
            case message = "message"
            case session = "session"
        }
        private static func withMessageIdOwnedIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(Key.rawMessageIdOwnedIdentity, EqualToData: ownedCryptoIdentity.getIdentity())
        }
        private static func withMessageIdUID(_ messageUID: UID) -> NSPredicate {
            NSPredicate(Key.rawMessageIdUid, EqualToData: messageUID.raw)
        }
        fileprivate static func withAttachmentNumber(_ attachmentNumber: Int) -> NSPredicate {
            NSPredicate(Key.attachmentNumber, EqualToInt: attachmentNumber)
        }
        fileprivate static func withMessageIdentifier(_ messageId: ObvMessageIdentifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withMessageIdUID(messageId.uid),
                withMessageIdOwnedIdentity(messageId.ownedCryptoIdentity),
            ])
        }
        fileprivate static func withAttachmentIdentifier(_ attachmentId: ObvAttachmentIdentifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withMessageIdentifier(attachmentId.messageId),
                withAttachmentNumber(attachmentId.attachmentNumber),
            ])
        }
        fileprivate static var withNonNilMessage: NSPredicate {
            NSPredicate(withNonNilValueForKey: Key.message)
        }
        fileprivate static var withNilMessage: NSPredicate {
            NSPredicate(withNilValueForKey: Key.message)
        }
        fileprivate static var withNilSession: NSPredicate {
            NSPredicate(withNilValueForKey: Key.session)
        }
        fileprivate static var withNonNilEncodedAuthenticatedDecryptionKey: NSPredicate {
            NSPredicate(withNonNilValueForKey: Key.encodedAuthenticatedDecryptionKey)
        }
        fileprivate static var withNonNilMetadata: NSPredicate {
            NSPredicate(withNonNilValueForKey: Key.metadata)
        }
        fileprivate static var withNonNilMessageFromCryptoIdentity: NSPredicate {
            let messageFromCryptoIdentityKey = [Key.message.rawValue, InboxMessage.Predicate.Key.rawFromIdentity.rawValue].joined(separator: ".")
            return NSPredicate(withNonNilValueForRawKey: messageFromCryptoIdentityKey)

        }
        fileprivate static func withStatus(_ status: Status) -> NSPredicate {
            NSPredicate(Key.rawStatus, EqualToInt: status.rawValue)
        }
    }

    
    @nonobjc class func fetchRequest() -> NSFetchRequest<InboxAttachment> {
        return NSFetchRequest<InboxAttachment>(entityName: InboxAttachment.entityName)
    }
    
    
    static func get(attachmentId: ObvAttachmentIdentifier, within context: NSManagedObjectContext) throws -> InboxAttachment? {
        let request: NSFetchRequest<InboxAttachment> = InboxAttachment.fetchRequest()
        request.predicate = Predicate.withAttachmentIdentifier(attachmentId)
        request.relationshipKeyPathsForPrefetching = [Predicate.Key.rawStatus.rawValue]
        let item = (try context.fetch(request)).first
        return item
    }
    
    
    static func getAllDownloadableWithoutSession(within context: NSManagedObjectContext) throws -> [InboxAttachment] {
        let request: NSFetchRequest<InboxAttachment> = InboxAttachment.fetchRequest()

        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withNilSession,
            Predicate.withNonNilMessage,
            Predicate.withNonNilEncodedAuthenticatedDecryptionKey,
            Predicate.withNonNilMetadata,
            Predicate.withNonNilMessageFromCryptoIdentity,
            Predicate.withStatus(.resumeRequested),
        ])
        let items = try context.fetch(request)
            .filter { (attachment) -> Bool in
                let allChunksHaveSignedURLs = attachment.chunks.allSatisfy({ $0.signedURL != nil })
                return allChunksHaveSignedURLs }
            .filter { (attachment) -> Bool in
                !attachment.isDownloaded }
        return items
    }
    
    
    /// Returns all the ``InboxAttachment`` that have no session, that can be downloaded technically and for which a resume was requested,
    /// and for which at least one chunk has no signed URL.
    static func getAllDownloadableWithMissingSignedURL(within context: NSManagedObjectContext) throws -> [(attachmentId: ObvAttachmentIdentifier, expectedChunkCount: Int)] {

        let request: NSFetchRequest<InboxAttachment> = InboxAttachment.fetchRequest()

        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withNilSession,
            Predicate.withNonNilMessage,
            Predicate.withNonNilEncodedAuthenticatedDecryptionKey,
            Predicate.withNonNilMetadata,
            Predicate.withNonNilMessageFromCryptoIdentity,
            Predicate.withStatus(.resumeRequested),
        ])

        request.propertiesToFetch = [
            Predicate.Key.attachmentNumber.rawValue,
            Predicate.Key.rawMessageIdOwnedIdentity.rawValue,
            Predicate.Key.rawMessageIdUid.rawValue,
        ]
        
        let items = try context.fetch(request)
            .filter { attachment in
                let noSignedURLForOneOrMoreChunks = attachment.chunks.first(where: { $0.signedURL == nil }) != nil
                return noSignedURLForOneOrMoreChunks
            }

        return items.compactMap { attachment in
            guard let attachmentId = attachment.attachmentId else { return nil }
            let expectedChunkCount = attachment.chunks.count
            return (attachmentId, expectedChunkCount)
        }

    }

    
    static func deleteAllOrphaned(within context: NSManagedObjectContext) throws {
        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: InboxAttachment.entityName)
        fetch.predicate = Predicate.withNilMessage
        let request = NSBatchDeleteRequest(fetchRequest: fetch)
        request.resultType = .resultTypeObjectIDs
        let result = try context.execute(request) as? NSBatchDeleteResult
        // The previous call **immediately** updates the SQLite database
        // We merge the changes back to the current context
        if let objectIDArray = result?.result as? [NSManagedObjectID] {
            let changes = [NSUpdatedObjectsKey : objectIDArray]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
        } else {
            assertionFailure()
        }
    }
    
}
