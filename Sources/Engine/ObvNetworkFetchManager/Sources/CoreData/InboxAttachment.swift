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
import ObvCrypto
import ObvTypes
import ObvEncoder
import ObvMetaManager

@objc(InboxAttachment)
final class InboxAttachment: NSManagedObject {
    
    private static let logger = Logger(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: "InboxAttachment")

    // MARK: Internal constants
    
    private static let entityName = "InboxAttachment"

    enum Status: Int, CustomDebugStringConvertible, CaseIterable {
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
        // Through the transition table, not around it. Its one caller has already established that the status is `resumeRequested`, so this cannot refuse
        // today; assigning directly would mean it never could, whatever the caller came to be.
        try changeStatus(to: .downloaded)
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
    var attachmentId: ObvAttachmentIdentifier {
        get throws {
            guard let messageId else { throw ObvError.couldNotDetermineMessageId }
            return ObvAttachmentIdentifier(messageId: messageId, attachmentNumber: attachmentNumber)
        }
    }

    func getURL(withinInbox inbox: URL) -> URL? {
        let attachmentFileName = "\(attachmentNumber)"
        let url = message?.getAttachmentsDirectory(withinInbox: inbox)?.appendingPathComponent(attachmentFileName)
        return url
    }


    /// What is actually on disk for this attachment, as one line for the log. Reports; changes nothing.
    ///
    /// Asked at the moment a download is handed to a `URLSession`, which captures the URL once and keeps it for the whole transfer. If the file is not there
    /// *then*, no chunk can ever be written, and the reader spends the whole of the attachment's bytes on a download that cannot succeed — twice over, since
    /// the chunks whose flags say they were written are not even fetched again. The one line that says so is worth more than any deleter's line, because a
    /// deleter only speaks when the damage is done and this speaks every time the damage is met.
    func reportOnWhatIsOnDiskForTheChunks(withinInbox inbox: URL) -> String {

        guard let url = getURL(withinInbox: inbox) else {
            return "no URL can be computed for this attachment, its message having been deleted"
        }

        let directory = url.deletingLastPathComponent()
        let fileIsThere = FileManager.default.fileExists(atPath: url.path)
        let directoryIsThere = FileManager.default.fileExists(atPath: directory.path)
        let numberOfChunksMarkedWritten = chunks.filter({ $0.cleartextChunkWasWrittenToAttachmentFile }).count

        var report = "file \(fileIsThere ? "is there" : "IS MISSING"), message directory \(directory.lastPathComponent) \(directoryIsThere ? "is there" : "IS MISSING"), \(numberOfChunksMarkedWritten) of \(chunks.count) chunk(s) already marked written"

        guard !fileIsThere else { return report }

        // Only when something is already wrong. Which name the directory has is what separates *somebody removed it* from *the file was written under the
        // legacy name and is being looked for under the deterministic one* — see `InboxMessage.getAttachmentsDirectory`, whose answer depends on the disk.
        if let messageId {
            report += ", deterministic name \(messageId.directoryNameForMessageAttachments)"
            let legacyNames = messageId.legacyDirectoryNamesForMessageAttachments
            let legacyNamesOnDisk = legacyNames.filter({ FileManager.default.fileExists(atPath: inbox.appendingPathComponent($0, isDirectory: true).path) })
            if legacyNamesOnDisk.isEmpty {
                report += ", none of the \(legacyNames.count) possible legacy director(ies) is on disk"
            } else {
                report += ", LEGACY director(ies) on disk: \(legacyNamesOnDisk.sorted().joined(separator: " "))"
            }
        }

        // **"0 entries" and "could not be read" are different facts and were reported as the same one.** They matter here more than anywhere: making the
        // file again creates the message directory with `withIntermediateDirectories: false`, which throws when the inbox itself is not there — so a repair
        // that would work on an empty inbox cannot work on a missing one, and the log has to say which of the two it is looking at.
        if let namesInInbox = try? FileManager.default.contentsOfDirectory(atPath: inbox.path) {
            report += ", \(namesInInbox.count) entr(ies) in the inbox"
        } else if FileManager.default.fileExists(atPath: inbox.path) {
            report += ", the inbox itself is there but CANNOT BE READ"
        } else {
            report += ", THE INBOX ITSELF IS MISSING"
        }

        return report
    }


    /// Makes the file the chunks are written into again when it is not there, forgetting every chunk with it, and answers whether it had to.
    ///
    /// **A download into a file that is not there cannot write a single chunk.** The session delegate is handed the URL once, at session creation, and keeps
    /// it for the whole transfer, so nothing between here and the last byte will notice: every chunk arrives, every write is refused, and the reader has
    /// spent the whole of the attachment on a download that could not succeed. Met on a production device on an inbox holding **no directories at all** —
    /// the fingerprint of the orphan sweep that emptied it before 2026-08-31 — where the rows, the decryption key and the chunk lengths had all survived in
    /// Core Data and only the bytes had gone. Nothing repaired that: the app-side repair is reached only for an attachment the engine has reported as
    /// *downloaded*, and one that cannot write its first chunk never gets there. Every tap cost the reader the whole attachment and could never have worked.
    ///
    /// **Every chunk is forgotten, not only the missing ones.** A flag saying a chunk was written is a claim about a file that is no longer there; fetching
    /// only what the flags call missing would fill a fresh file with holes, complete, and fail its sha256 — the corruption this manager already learnt not to
    /// paper over.
    ///
    /// **The status is deliberately left alone.** Its caller reaches this while the attachment is `resumeRequested` and a download is being built for it, so
    /// the sibling `resetDownloadFromScratch` — which forces `paused`, the app being expected to ask again — would strand the very download it is repairing.
    func makeTheFileForWritingChunksAgainIfItIsMissing(withinInbox inbox: URL) throws -> Bool {

        guard let url = getURL(withinInbox: inbox) else { throw ObvError.cannotGetAttachmentURL }

        guard !FileManager.default.fileExists(atPath: url.path) else { return false }

        guard let cleartextLength = plaintextLength else {
            assertionFailure()
            throw ObvError.couldNotDeterminePlaintextLength
        }

        let numberOfChunksThatWereMarkedWritten = chunks.filter({ $0.cleartextChunkWasWrittenToAttachmentFile }).count
        chunks.forEach { chunk in
            chunk.resetDownload()
        }

        try createEmptyFileForWritingChunks(withinInbox: inbox, cleartextLength: Int(cleartextLength), reason: .theFileWasNotThereAsADownloadWasAboutToStart)

        Self.logger.error("📁 [\(self.attachmentDescriptionForLog, privacy: .public)] The file the chunks are written into was missing as a download was about to start, so it was made again and all \(self.chunks.count) chunk(s) will be fetched (\(numberOfChunksThatWereMarkedWritten) of them were marked written into the file that has gone)")

        return true
    }
    
    override var debugDescription: String {
        return "InboxAttachment(messageId: \(messageId.debugDescription), attachmentNumber: \(attachmentNumber))"
    }

    /// How this attachment names itself in a log line. `attachmentId` throws when the `InboxMessage` was deleted on another thread, which is exactly the
    /// circumstance the file-lifecycle probes exist to report, so it must not be what stops one being written.
    var attachmentDescriptionForLog: String {
        (try? attachmentId)?.debugDescription ?? "unknown attachment"
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
             (.resumeRequested, .downloaded),
             // **A pause does not stop a chunk already in flight.** Suspending a `URLSession`'s tasks is asynchronous, so a chunk that was on its way when the
             // reader tapped pause can still land — and if it is the last one, every chunk has been written and the file on disk is complete. Refusing then
             // would strand a finished download in `paused`: nothing resumes an attachment in that state by itself, and the operation that would notice on the
             // next resume does not announce it, so the app would not hear of the file until the next cold launch re-offered it.
             //
             // Written down rather than left to the direct assignment that used to bypass this table entirely. That assignment also let a
             // `markedForDeletion` or `cancelledByServer` attachment be resurrected as `downloaded` by a late chunk, which is the case this table refuses and
             // the reason for routing through it.
             (.paused, .downloaded):
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
        Self.logger.info("📁 [\(self.attachmentDescriptionForLog, privacy: .public)] The app reported a downloaded attachment whose file is not on disk, so the download is reset from scratch")
        try resetDownloadFromScratch(withinInbox: inbox, reason: .theFileOfADownloadedAttachmentIsNotThere)
    }


    /// Puts a `downloaded` attachment back to `paused` with every chunk to be fetched again, although its file **is** there.
    ///
    /// The sibling above exists for the case where the file has vanished, and it cannot serve this one: its first act is to return when the file exists, which
    /// after a hash mismatch it always does. So the app cannot reach the reset through it, and this says what actually happened rather than pretending the
    /// file was missing.
    ///
    /// Called when the app has hashed a file this manager reported as complete and found bytes that no successful chunk write can have put there — see
    /// `Fyle.whatIsWrongWithTheFile(at:expectedByteCount:)`, which says how such a file is usually wrong. Per-chunk AEAD means each chunk that *was* written
    /// is authentic, so a mismatch is about the parts that were **not**: the file is discarded and fetched again from nothing.
    func resetStatusBecauseTheDownloadedFileIsCorrupt(withinInbox inbox: URL) throws {
        guard status == .downloaded else { assertionFailure("Why did we call this method?"); return }
        Self.logger.info("📁 [\(self.attachmentDescriptionForLog, privacy: .public)] The app hashed a downloaded attachment's file and found it corrupt, so the download is reset from scratch")
        try resetDownloadFromScratch(withinInbox: inbox, reason: .theFileOfADownloadedAttachmentIsCorrupt)
    }


    /// Forces the status back to `paused`, forgets every chunk, and makes the file the chunks will be written into.
    ///
    /// **The file has to be made here.** It is created once, in full and sparse, by ``set(decryptionKey:metadata:inbox:)`` — which throws if called twice, the
    /// key being settable only once — so nothing else can make it again. Until `Chunk.writeToURL(_:offset:)` started throwing it did not have to: a write to a
    /// missing file quietly created one, which is precisely the silent corruption that was removed. Since then a reset that leaves no file is a reset whose
    /// re-download cannot write its first chunk, so both entry points above go through here.
    ///
    /// Making the file afresh rather than writing over what is there is also what the corrupt case wants: a chunk that is never re-fetched cannot leave its
    /// old bytes behind if there are no old bytes.
    private func resetDownloadFromScratch(withinInbox inbox: URL, reason: ReasonForMakingTheFileTheChunksAreWrittenInto) throws {
        guard let cleartextLength = plaintextLength else {
            assertionFailure()
            throw ObvError.couldNotDeterminePlaintextLength
        }
        let numberOfChunksThatWereWritten = chunks.filter({ $0.cleartextChunkWasWrittenToAttachmentFile }).count
        try changeStatus(to: .paused, forceStatusChange: true)
        chunks.forEach { chunk in
            chunk.resetDownload()
        }
        Self.logger.info("📁 [\(self.attachmentDescriptionForLog, privacy: .public)] Resetting the download from scratch (\(reason.description, privacy: .public)): status forced to paused and \(numberOfChunksThatWereWritten) of \(self.chunks.count) written chunk(s) forgotten")
        try createEmptyFileForWritingChunks(withinInbox: inbox, cleartextLength: Int(cleartextLength), reason: reason)
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
        // This method deletes no file — it hands its URL back — and its only caller drops what it returns, the file going with the message directory instead.
        // Said out loud all the same: it is the moment at which an attachment's chunks are forgotten, and a download in flight is not consulted.
        Self.logger.info("📁 [\(self.attachmentDescriptionForLog, privacy: .public)] Marking the attachment for deletion and forgetting its \(self.chunks.count) chunk(s). The file at \(url.path, privacy: .public) is handed to the caller to delete")
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
        try createEmptyFileForWritingChunks(withinInbox: inbox, cleartextLength: totalCleartextLength, reason: .theDecryptionKeyAndMetadataJustArrived)
        
    }

    
    /// Why the file the chunks are written into is being made. Carried for the log alone: a line saying a file was destroyed and made again is only useful if
    /// it says who asked for it.
    enum ReasonForMakingTheFileTheChunksAreWrittenInto: CustomStringConvertible {

        case theDecryptionKeyAndMetadataJustArrived
        case theFileOfADownloadedAttachmentIsNotThere
        case theFileOfADownloadedAttachmentIsCorrupt
        case theFileWasNotThereAsADownloadWasAboutToStart

        var description: String {
            switch self {
            case .theDecryptionKeyAndMetadataJustArrived: return "the decryption key and metadata just arrived"
            case .theFileOfADownloadedAttachmentIsNotThere: return "the app found no file for an attachment this manager reported as downloaded"
            case .theFileOfADownloadedAttachmentIsCorrupt: return "the app found a corrupt file for an attachment this manager reported as downloaded"
            case .theFileWasNotThereAsADownloadWasAboutToStart: return "the file was not there as a download was about to start"
            }
        }

        /// `true` where a file already on disk is expected and destroying it is the point, `false` where finding one means something is wrong.
        var aFileIsExpectedToBeThereAlready: Bool {
            switch self {
            case .theDecryptionKeyAndMetadataJustArrived: return false
            case .theFileOfADownloadedAttachmentIsNotThere, .theFileOfADownloadedAttachmentIsCorrupt: return true
            case .theFileWasNotThereAsADownloadWasAboutToStart: return false // Reached only when there is no file, so the removal branch cannot be taken
            }
        }

    }


    private func createEmptyFileForWritingChunks(withinInbox inbox: URL, cleartextLength: Int, reason: ReasonForMakingTheFileTheChunksAreWrittenInto) throws {
        
        guard let url = getURL(withinInbox: inbox) else { throw ObvError.cannotGetAttachmentURL }

        let attachmentDescription = self.attachmentDescriptionForLog

        if FileManager.default.fileExists(atPath: url.path) {
            // **This removal destroys every chunk already written, and it is not transactional**: it happens before the context is saved, so a save that then
            // fails leaves the bytes gone with the database unchanged. Loud when a file was not expected — that is a second call for one attachment.
            if reason.aFileIsExpectedToBeThereAlready {
                Self.logger.info("📁 [\(attachmentDescription, privacy: .public)] Removing the file at \(url.path, privacy: .public) before making it again (\(reason.description, privacy: .public))")
            } else {
                Self.logger.error("📁 [\(attachmentDescription, privacy: .public)] Removing the file at \(url.path, privacy: .public) before making it again although \(reason.description, privacy: .public), so no file was expected to be there. Anything already written into it is being destroyed")
            }
            do {
                try FileManager.default.removeItem(at: url)
            } catch let error {
                Self.logger.fault("📁 [\(attachmentDescription, privacy: .public)] Could not remove the file at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                throw ObvError.couldNotDeleteAttachmentFile(atUrl: url, error: error)
            }
        }
        
        guard let message = self.message else {
            assertionFailure()
            throw ObvError.couldNotCreateAttachmentFile(error: nil)
        }
        
        try message.createAttachmentsDirectoryIfRequired(withinInbox: inbox)
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil) else {
            Self.logger.fault("📁 [\(attachmentDescription, privacy: .public)] Could not create the file the chunks are written into at \(url.path, privacy: .public)")
            throw ObvError.couldNotCreateAttachmentFile(error: nil)
        }
        
        guard let fh = FileHandle(forWritingAtPath: url.path) else {
            throw ObvError.couldNotGetFileHandle
        }
        fh.seek(toFileOffset: UInt64(cleartextLength))
        fh.closeFile()

        // The one line that says the file the chunks need *does* exist, and when. A refusal to write a chunk is only interpretable against it.
        Self.logger.info("📁 [\(attachmentDescription, privacy: .public)] Made the file the chunks are written into, \(cleartextLength) byte(s), at \(url.path, privacy: .public) (\(reason.description, privacy: .public))")
        
    }

    
    var plaintextLength: Int64? {
        let cleartextChunksLengths = chunks.compactMap({ $0.cleartextChunkLength })
        // The following test fails if the decryption key has not been set yet
        guard cleartextChunksLengths.count == chunks.count else {
            let cleartextChunksLengthsCount = cleartextChunksLengths.count
            let chunksCount = chunks.count
            Self.logger.fault("We have cleartextChunksLengths.count (\(cleartextChunksLengthsCount) != chunks.count (\(chunksCount), which happens wen the decryption key has not yet been set")
            return nil
        }
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
        guard allCleartextChunksWereWrittenToAttachmentFile else { return }

        // **Through the transition table**, which this used to assign straight past. A chunk can land after the attachment has left the states a download runs
        // in — the reader pausing is the ordinary way, and it is allowed for, but so is the app having asked for the attachment to be deleted, or the server
        // having cancelled it. Assigning `downloaded` in those two resurrected an attachment nobody wants: its message then never satisfies
        // `canBeDeletedFromServer`, which needs every attachment marked for deletion, so it is never removed from the server and the bootstrap re-offers it to
        // the app on every launch.
        //
        // **A refusal is not an error to throw here.** The chunk really was written to disk, and the flag recording it is set above; throwing would cancel the
        // operation, discard its context, and lose that record — so the chunk would be fetched a second time for nothing. The status simply does not change,
        // `isDownloaded` stays false, and the caller therefore does not announce a download that must not complete.
        do {
            try changeStatus(to: .downloaded)
        } catch {
            Self.logger.error("A late chunk completed attachment \(self.attachmentNumber) whose status is \(String(describing: self.status), privacy: .public). Keeping the chunk and leaving the status alone.")
        }

    }
    
}


// MARK: - Getting an ObvAttachment

extension InboxAttachment {
    
    func getObvAttachment(fromCryptoIdentity: ObvContactIdentifier, messageUploadTimestampFromServer: Date, inbox: URL) throws -> ObvAttachment {
        
        let attachmentId = try self.attachmentId
        guard let metadata = self.metadata else { assertionFailure(); throw ObvError.metadataIsNil }

        let status: ObvAttachment.Status
        switch self.status {
        case .paused:
            guard let plaintextLength else { assertionFailure(); throw ObvError.couldNotDeterminePlaintextLength }
            status = .paused(expectedTotalUnitCount: plaintextLength)
        case .resumeRequested:
            guard let plaintextLength else { assertionFailure(); throw ObvError.couldNotDeterminePlaintextLength }
            status = .resumed(expectedTotalUnitCount: plaintextLength)
        case .downloaded:
            //guard let plaintextLength else { assertionFailure(); throw ObvError.couldNotDeterminePlaintextLength }
            guard let url = self.getURL(withinInbox: inbox) else { assertionFailure(); throw ObvError.cannotGetAttachmentURL }
            status = .downloaded(url: url)
        case .cancelledByServer:
            status = .cancelledByServer
        case .markedForDeletion:
            status = .markedForDeletion
        }
        
        return ObvAttachment(fromContactIdentity: fromCryptoIdentity,
                             metadata: metadata,
                             status: status,
                             attachmentId: attachmentId,
                             messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        
    }
    
    
    func getObvOwnedAttachment(messageUploadTimestampFromServer: Date, inbox: URL) throws -> ObvOwnedAttachment {
        
        let attachmentId = try self.attachmentId
        guard let metadata = self.metadata else { assertionFailure(); throw ObvError.metadataIsNil }

        let status: ObvAttachment.Status
        switch self.status {
        case .paused:
            guard let plaintextLength else { assertionFailure(); throw ObvError.couldNotDeterminePlaintextLength }
            status = .paused(expectedTotalUnitCount: plaintextLength)
        case .resumeRequested:
            guard let plaintextLength else { assertionFailure(); throw ObvError.couldNotDeterminePlaintextLength }
            status = .resumed(expectedTotalUnitCount: plaintextLength)
        case .downloaded:
            //guard let plaintextLength else { assertionFailure(); throw ObvError.couldNotDeterminePlaintextLength }
            guard let url = self.getURL(withinInbox: inbox) else { assertionFailure(); throw ObvError.cannotGetAttachmentURL }
            status = .downloaded(url: url)
        case .cancelledByServer:
            status = .cancelledByServer
        case .markedForDeletion:
            status = .markedForDeletion
        }

        return ObvOwnedAttachment(metadata: metadata,
                                  status: status,
                                  attachmentId: attachmentId,
                                  messageUploadTimestampFromServer: messageUploadTimestampFromServer)

    }
}


// MARK: - Getting an ObvNetworkFetchReceivedAttachment

extension InboxAttachment {
    
    func getObvNetworkFetchReceivedAttachment(inbox: URL) throws -> ObvNetworkFetchReceivedAttachment {
        
        let attachmentId = try self.attachmentId
        guard let metadata = self.metadata else { assertionFailure(); throw ObvError.metadataIsNil }
        guard let fromCryptoIdentity else { assertionFailure(); throw ObvError.fromCryptoIdentityIsNil }
        guard let message = self.message else { assertionFailure(); throw ObvError.messageIsNil }
        let messageUploadTimestampFromServer = message.messageUploadTimestampFromServer
        let downloadTimestampFromServer = message.downloadTimestampFromServer

        let status: ObvNetworkFetchReceivedAttachment.Status
        switch self.status {
        case .paused:
            guard let plaintextLength else { assertionFailure(); throw ObvError.couldNotDeterminePlaintextLength }
            status = .paused(expectedTotalUnitCount: plaintextLength)
        case .resumeRequested:
            guard let plaintextLength else { assertionFailure(); throw ObvError.couldNotDeterminePlaintextLength }
            status = .resumed(expectedTotalUnitCount: plaintextLength)
        case .downloaded:
            guard let plaintextLength else { assertionFailure(); throw ObvError.couldNotDeterminePlaintextLength }
            guard let url = self.getURL(withinInbox: inbox) else { assertionFailure(); throw ObvError.cannotGetAttachmentURL }
            status = .downloaded(url: url, totalUnitCount: plaintextLength)
        case .cancelledByServer:
            status = .cancelledByServer
        case .markedForDeletion:
            status = .markedForDeletion
        }

        return ObvNetworkFetchReceivedAttachment(
            fromCryptoIdentity: fromCryptoIdentity,
            attachmentId: attachmentId,
            messageUploadTimestampFromServer: messageUploadTimestampFromServer,
            downloadTimestampFromServer: downloadTimestampFromServer,
            metadata: metadata,
            status: status)
        
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
        case metadataIsNil
        case couldNotDeterminePlaintextLength
        case fromCryptoIdentityIsNil
        case messageIsNil
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
        fileprivate static func onAMessageMarkedForDeletion(_ bool: Bool) -> NSPredicate {
            let messageMarkedForDeletionKey = [Key.message.rawValue, InboxMessage.Predicate.Key.markedForDeletion.rawValue].joined(separator: ".")
            return NSPredicate(messageMarkedForDeletionKey, is: bool)
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
            guard let attachmentId = try? attachment.attachmentId else { return nil }
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


// MARK: - Counting attachments, for the diagnostics the app can show

extension InboxAttachment {

    /// How many attachments are in the given status, counted without materialising any of them.
    static func count(withStatus status: Status, within context: NSManagedObjectContext) throws -> Int {
        let request = NSFetchRequest<InboxAttachment>(entityName: Self.entityName)
        request.predicate = Predicate.withStatus(status)
        return try context.count(for: request)
    }


    /// How many attachments are in the given status on a message the app has already finished with.
    ///
    /// This is the breakdown that separates the ordinary from the wrong. An attachment left `paused` here is a reader who has not tapped it yet, which is
    /// the common case and no fault at all. One left `downloaded` is bytes on the disk that the app never took, and one left `cancelledByServer` should
    /// have been released — those two are worth knowing about.
    static func count(withStatus status: Status, onAMessageMarkedForDeletion: Bool, within context: NSManagedObjectContext) throws -> Int {
        let request = NSFetchRequest<InboxAttachment>(entityName: Self.entityName)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withStatus(status),
            Predicate.onAMessageMarkedForDeletion(onAMessageMarkedForDeletion),
        ])
        return try context.count(for: request)
    }


    /// How many bytes the attachments in the given status, on a message the app has finished with, are still waiting to download.
    ///
    /// One large file and a thousand small ones are the same count and very different situations, which is the whole reason for asking.
    static func sumOfInitialByteCountToDownload(withStatus status: Status, onAMessageMarkedForDeletion: Bool, within context: NSManagedObjectContext) throws -> Int64 {
        let sumOfInitialByteCount = "sumOfInitialByteCount"
        let expressionDescription = NSExpressionDescription()
        expressionDescription.name = sumOfInitialByteCount
        expressionDescription.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: Predicate.Key.initialByteCountToDownload.rawValue)])
        expressionDescription.expressionResultType = .integer64AttributeType
        let request = NSFetchRequest<NSDictionary>(entityName: Self.entityName)
        request.resultType = .dictionaryResultType
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withStatus(status),
            Predicate.onAMessageMarkedForDeletion(onAMessageMarkedForDeletion),
        ])
        request.propertiesToFetch = [expressionDescription]
        guard let item = try context.fetch(request).first else { return 0 }
        return (item[sumOfInitialByteCount] as? Int64) ?? 0
    }

}
