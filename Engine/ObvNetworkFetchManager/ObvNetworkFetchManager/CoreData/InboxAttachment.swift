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
import ObvCrypto
import ObvTypes
import ObvEncoder
import ObvMetaManager
import OlvidUtils

@objc(InboxAttachment)
final class InboxAttachment: NSManagedObject, ObvManagedObject {
    
    enum InternalError: Error {
        case theDecryptionKeyCanOnlyBeSetOnce
        case theMetadataCanOnlyBeSetOnce
        case chunksInstancesCanBeCreatedOnlyOnce
        case couldNotDeleteAttachmentFile(atUrl: URL, error: Error)
        case couldNotCreateAttachmentFile(error: Error?)
        case couldNotWrite(atUrl: URL, error: Error)
        case unexpectedChunkNumber
    }
    
    private static let errorDomain = "InboxAttachment"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    // MARK: Internal constants
    
    private static let entityName = "InboxAttachment"
    private static let attachmentNumberKey = "attachmentNumber"
    private static let currentByteCountToDownloadKey = "currentByteCountToDownload"
    private static let encodedAuthenticatedEncryptionKeyKey = "encodedAuthenticatedDecryptionKey"
    private static let timestampOfDownloadRequestKey = "timestampOfDownloadRequest"
    private static let timestampOfNextFetchAttemptKey = "timestampOfNextFetchAttempt"
    private static let messageKey = "message"
    private static let metadataKey = "metadata"
    private static let encodedChunkRangesToDownloadKey = "encodedChunkRangesToDownload"
    private static let rawStatusKey = "rawStatus"
    private static let rawMessageIdOwnedIdentityKey = "rawMessageIdOwnedIdentity"
    private static let rawMessageIdUidKey = "rawMessageIdUid"
    private static let chunksKey = "chunks"
    private static let sessionKey = "session"
    private static let messageFromCryptoIdentityKey = [messageKey, InboxMessage.Predicate.Key.fromCryptoIdentityKey.rawValue].joined(separator: ".")

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
    }

    // MARK: Attributes
    
    @NSManaged private(set) var attachmentNumber: Int
    private var key: AuthenticatedEncryptionKey? {
        get {
            guard let encodedKeyData = kvoSafePrimitiveValue(forKey: InboxAttachment.encodedAuthenticatedEncryptionKeyKey) as? Data else { return nil }
            let encodedKey = ObvEncoded(withRawData: encodedKeyData)!
            return try! AuthenticatedEncryptionKeyDecoder.decode(encodedKey)
        }
        set {
            if newValue != nil {
                let encodedKey = newValue!.encode()
                kvoSafeSetPrimitiveValue(encodedKey.rawData, forKey: InboxAttachment.encodedAuthenticatedEncryptionKeyKey)
            }
        }
    }
    @NSManaged private(set) var expectedChunkLength: Int
    @NSManaged private(set) var initialByteCountToDownload: Int // The number of (encrypted) bytes we need to receive to eventually obtain the full file
    @NSManaged private(set) var metadata: Data?
    @NSManaged private var rawMessageIdOwnedIdentity: Data
    @NSManaged private var rawMessageIdUid: Data
    @NSManaged private var rawStatus: Int

    // MARK: Relationships
    
    private(set) var chunks: [InboxAttachmentChunk] {
        get {
            guard let unsortedChunks = kvoSafePrimitiveValue(forKey: InboxAttachment.chunksKey) as? Set<InboxAttachmentChunk> else { return [] }
            let items: [InboxAttachmentChunk] = unsortedChunks.sorted(by: { $0.chunkNumber < $1.chunkNumber })
            for item in items { item.obvContext = self.obvContext }
            return items
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: InboxAttachment.chunksKey)
        }
    }

    // We do not expect the message to be nil, since cascade deleting a message delete its attachments
    var message: InboxMessage? {
        get {
            let value = kvoSafePrimitiveValue(forKey: InboxAttachment.messageKey) as? InboxMessage
            value?.obvContext = self.obvContext
            return value
        }
        set {
            guard let value = newValue else { assertionFailure(); return }
            self.messageId = value.messageId
            kvoSafeSetPrimitiveValue(value, forKey: InboxAttachment.messageKey)
        }
    }
    
    private(set) var session: InboxAttachmentSession? {
        get {
            let item = kvoSafePrimitiveValue(forKey: InboxAttachment.sessionKey) as? InboxAttachmentSession
            item?.obvContext = self.obvContext
            return item
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: InboxAttachment.sessionKey)
        }
    }

    
    // MARK: Other variables
    
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
        guard allChunksAreDownloaded else { throw InboxAttachment.makeError(message: "Tryingin to change status to downloaded but at least one chunk is not downloaded yet") }
        self.status = .downloaded
    }
    
    private(set) var status: Status {
        get { return Status(rawValue: self.rawStatus)! }
        set { self.rawStatus = newValue.rawValue }
    }
    
    var obvContext: ObvContext?
    
    var fromCryptoIdentity: ObvCryptoIdentity? {
        return message?.fromCryptoIdentity
    }
    
    var canBeDownloaded: Bool {
        return key != nil && metadata != nil && fromCryptoIdentity != nil
    }
    
    private(set) var messageId: MessageIdentifier {
        get { return MessageIdentifier(rawOwnedCryptoIdentity: self.rawMessageIdOwnedIdentity, rawUid: self.rawMessageIdUid)! }
        set { self.rawMessageIdOwnedIdentity = newValue.ownedCryptoIdentity.getIdentity(); self.rawMessageIdUid = newValue.uid.raw }
    }

    var attachmentId: AttachmentIdentifier {
        return AttachmentIdentifier(messageId: messageId, attachmentNumber: attachmentNumber)
    }

    func getURL(withinInbox inbox: URL) -> URL? {
        let attachmentFileName = "\(attachmentNumber)"
        let url = message?.getAttachmentDirectory(withinInbox: inbox).appendingPathComponent(attachmentFileName)
        return url
    }
    
    override var debugDescription: String {
        return "InboxAttachment(messageId: \(messageId.debugDescription), attachmentNumber: \(attachmentNumber))"
    }
    
    var currentChunkProgresses: [(completedUnitCount: Int64, totalUnitCount: Int64)] {
        self.chunks.map {
            let completedUnitCount = $0.cleartextChunkWasWrittenToAttachmentFile ? $0.ciphertextChunkLength : 0
            return (Int64(completedUnitCount), Int64($0.ciphertextChunkLength))
        }
    }

    // MARK: - Initializer
    
    convenience init?(message: InboxMessage, attachmentNumber: Int, byteCountToDownload: Int, expectedChunkLength: Int, within obvContext: ObvContext) throws {

        let attachmentId = AttachmentIdentifier(messageId: message.messageId, attachmentNumber: attachmentNumber)
        
        guard try InboxAttachment.get(attachmentId: attachmentId, within: obvContext) == nil else { return nil }

        let entityDescription = NSEntityDescription.entity(forEntityName: InboxAttachment.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        
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


// MARK: - Setters and other methods

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
    
    private func changeStatus(to newStatus: Status) throws {
        guard canTransistionToNewStatus(newStatus) else {
            throw InboxAttachment.makeError(message: "Cannot transition from \(status.debugDescription) to \(newStatus.debugDescription)")
        }
        guard newStatus != self.status else { return }
        self.status = newStatus
    }
    
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
        try self.changeStatus(to: .resumeRequested)
    }
    
    
    func pauseDownload() throws {
        try changeStatus(to: .paused)
    }

    
    func deleteDownload(fromInbox inbox: URL) throws {
        guard let url = getURL(withinInbox: inbox) else { throw InboxAttachment.makeError(message: "Cannot get attachment URL") }
        try changeStatus(to: .markedForDeletion) // This cannot fail
        for chunk in chunks {
            try chunk.resetDownload()
            self.obvContext?.delete(chunk)
        }
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch let error {
                throw InternalError.couldNotDeleteAttachmentFile(atUrl: url, error: error)
            }
        }
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
        guard urls.count == chunks.count else { assertionFailure(); throw InboxAttachment.makeError(message: "Unexpected number of signed URLs wrt the number of chunks") }
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
            throw InternalError.theDecryptionKeyCanOnlyBeSetOnce
        }
        guard self.metadata == nil else {
            assertionFailure()
            throw InternalError.theMetadataCanOnlyBeSetOnce
        }
        
        self.metadata = metadata
        self.key = key
        
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
        
        guard let url = getURL(withinInbox: inbox) else { throw InboxAttachment.makeError(message: "Cannot get attachment URL") }

        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch let error {
                throw InternalError.couldNotDeleteAttachmentFile(atUrl: url, error: error)
            }
        }
        
        guard let message = self.message else {
            assertionFailure()
            throw InternalError.couldNotCreateAttachmentFile(error: nil)
        }
        
        try message.createAttachmentsDirectoryIfRequired(withinInbox: inbox)
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil) else {
            throw InternalError.couldNotCreateAttachmentFile(error: nil)
        }
        
        guard let fh = FileHandle(forWritingAtPath: url.path) else { throw NSError() }
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
    
    func decryptEncryptedChunk(number chunkNumber: Int, atFileHandle fh: FileHandle, andWriteCleartextToAttachmentFileWithinInbox inbox: URL) throws {
        guard chunkNumber < chunks.count else { throw InboxAttachment.makeError(message: "Unexpected chunk number") }
        guard let key = self.key else { throw InboxAttachment.makeError(message: "Decryption key is not set") }
        var offset = 0
        for nbr in 0..<chunkNumber {
            guard let cleartextChunkLength = chunks[nbr].cleartextChunkLength else { throw InboxAttachment.makeError(message: "Cannot determine offset") }
            offset += cleartextChunkLength
        }
        try chunks[chunkNumber].decryptAndWriteToAttachmentFileThenDeleteEncryptedChunk(atFileHandle: fh, withKey: key, offset: offset, withinInbox: inbox)
        // Check whether the attachment is fully downloaded
        let allCleartextChunksWereWrittenToAttachmentFile = chunks.allSatisfy({ $0.cleartextChunkWasWrittenToAttachmentFile })
        if allCleartextChunksWereWrittenToAttachmentFile {
            status = .downloaded
        }
    }
    
}


// MARK: - Convenience DB getters

extension InboxAttachment {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<InboxAttachment> {
        return NSFetchRequest<InboxAttachment>(entityName: InboxAttachment.entityName)
    }
    
    
    static func get(attachmentId: AttachmentIdentifier, within obvContext: ObvContext) throws -> InboxAttachment? {
        let request: NSFetchRequest<InboxAttachment> = InboxAttachment.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@ AND %K == %d",
                                        rawMessageIdOwnedIdentityKey, attachmentId.messageId.ownedCryptoIdentity.getIdentity() as NSData,
                                        rawMessageIdUidKey, attachmentId.messageId.uid.raw as NSData,
                                        attachmentNumberKey, attachmentId.attachmentNumber)
        request.relationshipKeyPathsForPrefetching = [InboxAttachment.rawStatusKey]
        let item = (try obvContext.fetch(request)).first
        return item
    }
    
    
    static func getAllDownloadableWithoutSession(within obvContext: ObvContext) throws -> [InboxAttachment] {
        let request: NSFetchRequest<InboxAttachment> = InboxAttachment.fetchRequest()
                
        request.predicate = NSPredicate(format: "%K != NIL AND %K == NIL AND %K != NIL AND %K != NIL AND %K != NIL AND %K == %d",
                                        messageKey,
                                        sessionKey,
                                        encodedAuthenticatedEncryptionKeyKey,
                                        metadataKey,
                                        messageFromCryptoIdentityKey,
                                        rawStatusKey, Status.resumeRequested.rawValue)
        let items = try obvContext.fetch(request)
            .filter { (attachment) -> Bool in
                let allChunksHaveSignedURLs = attachment.chunks.allSatisfy({ $0.signedURL != nil })
                return allChunksHaveSignedURLs }
            .filter { (attachment) -> Bool in
                !attachment.isDownloaded }
        return items
    }

    static func getAllNotResumed(within obvContext: ObvContext) throws -> [InboxAttachment] {
        let request: NSFetchRequest<InboxAttachment> = InboxAttachment.fetchRequest()
        request.predicate = NSPredicate(format: "%K != %d", rawStatusKey, Status.resumeRequested.rawValue)
        request.relationshipKeyPathsForPrefetching = [InboxAttachment.rawStatusKey]
        return try obvContext.fetch(request)
    }
    
    
    static func getAllMarkedForDeletion(within obvContext: ObvContext) throws -> [InboxAttachment] {
        let request: NSFetchRequest<InboxAttachment> = InboxAttachment.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %d", rawStatusKey, Status.markedForDeletion.rawValue)
        request.relationshipKeyPathsForPrefetching = [InboxAttachment.rawStatusKey]
        return try obvContext.fetch(request)
    }


    static func deleteAllOrphaned(within obvContext: ObvContext) throws {
        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: InboxAttachment.entityName)
        fetch.predicate = NSPredicate(format: "%K == NIL", messageKey)
        let request = NSBatchDeleteRequest(fetchRequest: fetch)
        _ = try obvContext.execute(request)
    }

}
