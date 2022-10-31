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
import os.log
import CoreData
import ObvTypes
import ObvCrypto
import ObvEncoder
import ObvMetaManager
import OlvidUtils

@objc(OutboxAttachment)
final class OutboxAttachment: NSManagedObject, ObvManagedObject {
    
    // MARK: Internal constants
    
    static let entityName = "OutboxAttachment"
    private static let attachmentNumberKey = "attachmentNumber"
    private static let cancelExternallyRequestedKey = "cancelExternallyRequested"
    private static let messageKey = "message"
    private static let chunksKey = "chunks"
    private static let sessionKey = "session"
    private static let rawMessageIdOwnedIdentityKey = "rawMessageIdOwnedIdentity"
    private static let rawMessageIdUidKey = "rawMessageIdUid"
    private static let messageUploadedKey = [messageKey, OutboxMessage.uploadedKey].joined(separator: ".")

    private static let errorDomain = "OutboxAttachment"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    // MARK: Attributes
    
    @NSManaged private(set) var attachmentLength: Int
    @NSManaged private(set) var attachmentNumber: Int
    @NSManaged private(set) var cancelExternallyRequested: Bool
    @NSManaged private(set) var deleteAfterSend: Bool
    @NSManaged private var encodedAuthenticatedEncryptionKey: Data
    @NSManaged private(set) var fileURL: URL // URL of the cleartext
    @NSManaged private var rawMessageIdOwnedIdentity: Data
    @NSManaged private var rawMessageIdUid: Data

    // MARK: Relationships
    
    private(set) var chunks: [OutboxAttachmentChunk] {
        get {
            let items: [OutboxAttachmentChunk] = (kvoSafePrimitiveValue(forKey: OutboxAttachment.chunksKey) as? Set<OutboxAttachmentChunk>)?
                .sorted(by: { $0.chunkNumber < $1.chunkNumber }) ?? []
            for item in items { item.obvContext = self.obvContext }
            return items
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: OutboxAttachment.chunksKey)
        }
    }

    // We do not expect the message to be nil, since this attachment is cascade deleted
    private(set) var message: OutboxMessage? {
        get {
            let item = kvoSafePrimitiveValue(forKey: OutboxAttachment.messageKey) as? OutboxMessage
            item?.obvContext = self.obvContext
            return item
        }
        set {
            guard let value = newValue, let messageId = value.messageId else { assertionFailure(); return }
            self.messageId = messageId
            kvoSafeSetPrimitiveValue(value, forKey: OutboxAttachment.messageKey)
        }
    }
    
    private(set) var session: OutboxAttachmentSession? {
        get {
            let item = kvoSafePrimitiveValue(forKey: OutboxAttachment.sessionKey) as? OutboxAttachmentSession
            item?.obvContext = self.obvContext
            return item
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: OutboxAttachment.sessionKey)
        }
    }

    
    // MARK: Other variables
    
    private(set) var key: AuthenticatedEncryptionKey {
        get { try! AuthenticatedEncryptionKeyDecoder.decode(ObvEncoded(withRawData: encodedAuthenticatedEncryptionKey)!) }
        set { encodedAuthenticatedEncryptionKey = newValue.obvEncode().rawData }
    }

    var canBeSent: Bool {
        // Any change here should be reflected in `getUploadableAttachmentWithHighestPriority`
        guard let message = self.message else { return false }
        return message.uploaded && !self.acknowledged && !self.cancelExternallyRequested
    }
    
    private(set) var messageId: MessageIdentifier {
        get { MessageIdentifier(rawOwnedCryptoIdentity: self.rawMessageIdOwnedIdentity, rawUid: self.rawMessageIdUid)! }
        set { self.rawMessageIdOwnedIdentity = newValue.ownedCryptoIdentity.getIdentity(); self.rawMessageIdUid = newValue.uid.raw }
    }

    var attachmentId: AttachmentIdentifier {
        AttachmentIdentifier(messageId: self.messageId, attachmentNumber: self.attachmentNumber)
    }
    
    var canBeDeleted: Bool { acknowledged || cancelExternallyRequested }
    
    var acknowledged: Bool {
        do {
            let currentByteCountToUpload = try getCurrentByteCountToUpload()
            return currentByteCountToUpload == 0
        } catch {
            assertionFailure()
            return false
        }
    }
    
    lazy var ciphertextLength: Int = { chunks.reduce(0, { $0 + $1.ciphertextChunkLength }) }()
    
    var obvContext: ObvContext?

    var currentChunkProgresses: [(totalBytesSent: Int64, totalBytesExpectedToSend: Int64)] {
        self.chunks.map {
            let completedUnitCount = $0.isAcknowledged ? $0.ciphertextChunkLength : 0
            return (Int64(completedUnitCount), Int64($0.ciphertextChunkLength))
        }
    }
    
    // MARK: - Initializer
    
    convenience init(message: OutboxMessage, attachmentNumber: Int, fileURL: URL, deleteAfterSend: Bool, byteSize: Int, key: AuthenticatedEncryptionKey) throws {
        guard let obvContext = message.obvContext else {
            throw Self.makeError(message: "Cannot find obvContext")
        }
        guard let messageId = message.messageId else {
            throw Self.makeError(message: "Could not determine the message Id")
        }
        guard try OutboxAttachment.get(attachmentId: AttachmentIdentifier(messageId: messageId, attachmentNumber: attachmentNumber), within: obvContext) == nil else {
            throw Self.makeError(message: "An OutboxAttachment with the same primary key already exists")
        }
        let entityDescription = NSEntityDescription.entity(forEntityName: OutboxAttachment.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        let chunksValues = OutboxAttachment.computeChunksValues(fromAttachmentLength: byteSize, whenUsingEncryptionKey: key)
        self.attachmentLength = byteSize
        self.attachmentNumber = attachmentNumber
        self.cancelExternallyRequested = false
        self.deleteAfterSend = deleteAfterSend
        self.key = key
        self.fileURL = fileURL
        self.message = message
        self.session = nil
        for chunkNumber in 0..<chunksValues.requiredNumberOfChunks {
            let ciphertextChunkLength = chunkNumber == chunksValues.requiredNumberOfChunks-1 ? chunksValues.lastEncryptedChunkLength : chunksValues.encryptedChunkTypicalLength
            let clearTextChunkLength = chunkNumber == chunksValues.requiredNumberOfChunks-1 ? chunksValues.lastCleartextChunkLength : chunksValues.cleartextChunkTypicalLength
            _ = OutboxAttachmentChunk(attachment: self, chunkNumber: chunkNumber, ciphertextChunkLength: ciphertextChunkLength, cleartextChunkLength: clearTextChunkLength)
        }
    }
    
    private static func computeChunksValues(fromAttachmentLength attachmentLength: Int, whenUsingEncryptionKey key: AuthenticatedEncryptionKey) -> (encryptedChunkTypicalLength: Int, cleartextChunkTypicalLength: Int, lastEncryptedChunkLength: Int, lastCleartextChunkLength: Int, ciphertextLength: Int, requiredNumberOfChunks: Int) {
        /// We evaluate the length of ciphertext chunks if we split the attachment in `AttachmentCiphertextMaximumNumberOfChunks` chunks.
        /// If this length is large enough, we return it.
        do {
            let chunkInnerDataTypicalLength = 1 + (attachmentLength - 1) / ObvConstants.AttachmentCiphertextMaximumNumberOfChunks
            let encryptedChunkTypicalLength = Chunk.encryptedLengthFromCleartextLength(chunkInnerDataTypicalLength, whenUsingEncryptionKey: key)
            if encryptedChunkTypicalLength >= ObvConstants.AttachmentCiphertextChunkTypicalLength {
                let lastChunkInnerDataLength = attachmentLength - (ObvConstants.AttachmentCiphertextMaximumNumberOfChunks-1) * chunkInnerDataTypicalLength
                let lastEncryptedChunkLength = Chunk.encryptedLengthFromCleartextLength(lastChunkInnerDataLength, whenUsingEncryptionKey: key)
                let ciphertextLength = (ObvConstants.AttachmentCiphertextMaximumNumberOfChunks-1)*encryptedChunkTypicalLength + lastEncryptedChunkLength
                return (encryptedChunkTypicalLength, chunkInnerDataTypicalLength, lastEncryptedChunkLength, lastChunkInnerDataLength, ciphertextLength, ObvConstants.AttachmentCiphertextMaximumNumberOfChunks)
            }
        }
        /// If we reach this point, the attachment is not "very" large. If it is "very" small (smaller than encryptedChunkMinimumLength once encrypted),
        /// we return this "very small" chunk length
        do {
            let encryptedChunkLength = Chunk.encryptedLengthFromCleartextLength(attachmentLength, whenUsingEncryptionKey: key)
            if encryptedChunkLength <= ObvConstants.AttachmentCiphertextChunkTypicalLength {
                return (encryptedChunkLength, attachmentLength, encryptedChunkLength, attachmentLength, encryptedChunkLength, 1)
            }
        }
        /// If we reach this point, the attachment has a normal size. We set the typical length to the default one and compute the
        /// required number of chunks, knowing that is will be less than ObvConstants.AttachmentCiphertextMaximumNumberOfChunks.
        do {
            let encryptedChunkTypicalLength = ObvConstants.AttachmentCiphertextChunkTypicalLength
            let chunkInnerDataTypicalLength = try! Chunk.cleartextLengthFromEncryptedLength(encryptedChunkTypicalLength, whenUsingEncryptionKey: key) // We know this cannot throw
            let requiredNumberOfChunks = 1 + (attachmentLength - 1) / chunkInnerDataTypicalLength
            assert(requiredNumberOfChunks <= ObvConstants.AttachmentCiphertextMaximumNumberOfChunks)
            let lastChunkInnerDataLength = attachmentLength - (requiredNumberOfChunks-1) * chunkInnerDataTypicalLength
            let lastEncryptedChunkLength = Chunk.encryptedLengthFromCleartextLength(lastChunkInnerDataLength, whenUsingEncryptionKey: key)
            let ciphertextLength = (requiredNumberOfChunks-1)*encryptedChunkTypicalLength + lastEncryptedChunkLength
            return (encryptedChunkTypicalLength, chunkInnerDataTypicalLength, lastEncryptedChunkLength, lastChunkInnerDataLength, ciphertextLength, requiredNumberOfChunks)
        }
    }


    func getCurrentByteCountToUpload() throws -> Int {
        let currentUploadedByteCount = try getCurrentUploadedByteCount()
        return ciphertextLength - currentUploadedByteCount
    }
    
    func getCurrentUploadedByteCount() throws -> Int {
        try OutboxAttachmentChunk.getCurrentUploadedByteCountOfAttachment(self)
    }
}


// MARK: - Other stuff

extension OutboxAttachment {
    
    func createSession(appType: AppType) -> OutboxAttachmentSession? {
        assert(self.session == nil)
        return OutboxAttachmentSession(attachment: self, appType: appType)
    }
    
    func deleteSession() throws {
        guard let session = self.session else { return }
        guard let obvContext = self.obvContext else { throw OutboxAttachment.makeError(message: "ObvContex is nil") }
        obvContext.delete(session)
    }
    
    func cancelUpload() {
        guard !self.cancelExternallyRequested else { return }
        self.cancelExternallyRequested = true
    }
    
    func resetForResend() throws {
        chunks.forEach({ $0.unacknowledge() })
    }
    
    func chunkWasAchknowledged(chunkNumber: Int, by appType: AppType) {
        guard chunkNumber < chunks.count else { assertionFailure(); return }
        chunks[chunkNumber].setAcknowledged(by: appType)
    }
 
    func setAllChunksAsAcknowledged(by appType: AppType) {
        chunks.forEach { $0.setAcknowledged(by: appType) }
    }
    
    /// We expect one URL per chunk
    func setChunkUploadSignedUrls(_ urls: [URL]) throws {
        assert(urls.count == chunks.count)
        guard urls.count == chunks.count else {
            throw OutboxAttachment.makeError(message: "The count of private URLs is different from the number of chunks to upload")
        }
        for (chunk, url) in zip(chunks, urls) {
            chunk.signedURL = url
        }
    }
    
    func removeChunkUploadSignedUrls() {
        chunks.forEach { $0.signedURL = nil }
    }
    
    var allChunksHaveSignedUrls: Bool {
        return chunks.allSatisfy { $0.signedURL != nil }
    }
    
    func getAppropriateOperationQueuePriority() -> Operation.QueuePriority {
        // We map the interval [1, AttachmentCiphertextMaximumNumberOfChunks] to [veryLow.raw, veryHigh.raw] such that 1 is veryHigh and AttachmentCiphertextMaximumNumberOfChunks is veryLow
        let a = Double(Operation.QueuePriority.veryLow.rawValue - Operation.QueuePriority.veryHigh.rawValue) / Double(ObvConstants.AttachmentCiphertextMaximumNumberOfChunks - 1)
        let b = Double(Operation.QueuePriority.veryHigh.rawValue) - a
        let rawPriority = Int((a * Double(chunks.count) + b).rounded(.toNearestOrEven))
        guard let priority = Operation.QueuePriority(rawValue: rawPriority) else { assertionFailure(); return Operation.QueuePriority.normal }
        return priority
    }
}

// MARK: - Convenience DB getters
extension OutboxAttachment {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<OutboxAttachment> {
        return NSFetchRequest<OutboxAttachment>(entityName: OutboxAttachment.entityName)
    }

    
    static func get(attachmentId: AttachmentIdentifier, within obvContext: ObvContext) throws -> OutboxAttachment? {
        let request: NSFetchRequest<OutboxAttachment> = OutboxAttachment.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@ AND %K == %d",
                                        rawMessageIdOwnedIdentityKey, attachmentId.messageId.ownedCryptoIdentity.getIdentity() as NSData,
                                        rawMessageIdUidKey, attachmentId.messageId.uid.raw as NSData,
                                        attachmentNumberKey, attachmentId.attachmentNumber)
        request.propertiesToFetch = [cancelExternallyRequestedKey]
        let item = try obvContext.fetch(request).first
        return item
    }
    
    
    static func getAll(within obvContext: ObvContext) throws -> [OutboxAttachment] {
        let request: NSFetchRequest<OutboxAttachment> = OutboxAttachment.fetchRequest()
        let items = try obvContext.fetch(request)
        return items
    }

    
    static func getAllUploadableWithoutSession(within obvContext: ObvContext) throws -> [OutboxAttachment] {
        let request: NSFetchRequest<OutboxAttachment> = OutboxAttachment.fetchRequest()
        request.predicate = NSPredicate(format: "%K != NIL AND %K == NIL AND %K == true AND %K == false",
                                        messageKey,
                                        sessionKey,
                                        messageUploadedKey,
                                        cancelExternallyRequestedKey)
        let items = try obvContext.fetch(request)
            .filter { (attachment) -> Bool in
                let allChunksHaveSignedURLs = attachment.chunks.allSatisfy({ $0.signedURL != nil })
                return allChunksHaveSignedURLs }
            .filter { (attachment) -> Bool in
                !attachment.acknowledged }
        return items
    }
    
    
    static func deleteAllOrphanedAttachments(within obvContext: ObvContext) throws {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: OutboxAttachment.entityName)
        fetchRequest.predicate = NSPredicate(format: "%K == NIL", messageKey)
        let request = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        _ = try obvContext.execute(request)
    }
    
}


// MARK: Providing a debugDescription
extension OutboxAttachment {
    
    override var debugDescription: String {
        return "OutboxAttachment<\(attachmentId.debugDescription)>"
    }
    
}
