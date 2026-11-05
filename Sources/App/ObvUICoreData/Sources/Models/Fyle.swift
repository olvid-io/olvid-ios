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
import ObvTypes
import OlvidUtils
import ObvCrypto
import ObvSettings
import UniformTypeIdentifiers


@objc(Fyle)
public final class Fyle: NSManagedObject {
    
    private static let entityName = "Fyle"
    private static let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "Fyle")
    private static let logger = Logger(subsystem: ObvUICoreDataConstants.logSubsystem, category: "Fyle")

    // MARK: - Properties

    @NSManaged private var intrinsicFilename: String?
    @NSManaged public private(set) var sha256: Data
    
    // MARK: - Relationship
    
    @NSManaged private(set) var allDraftFyleJoins: Set<PersistedDraftFyleJoin>
    /// The draft photos that hold this file as one of the sizes they may be sent at. See ``PersistedDraftFyleJoinVariant``.
    @NSManaged private(set) var allDraftFyleJoinVariants: Set<PersistedDraftFyleJoinVariant>
    @NSManaged public private(set) var allFyleMessageJoinWithStatus: Set<FyleMessageJoinWithStatus>

    
    // MARK: - Transient URL - url to set if the fyle is not cached at the usual place (used mainly for previews generated on the fly)
    var transientURL: URL?
    
    // MARK: - Initializer

    private convenience init(sha256: Data, within context: NSManagedObjectContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: Fyle.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.sha256 = sha256
        
        self.allDraftFyleJoins = Set<PersistedDraftFyleJoin>()
        self.allDraftFyleJoinVariants = Set<PersistedDraftFyleJoinVariant>()
        self.allFyleMessageJoinWithStatus = Set<FyleMessageJoinWithStatus>()
    }
      
    public static func getOrCreate(sha256: Data, within context: NSManagedObjectContext) throws -> Fyle {
        if let previousFyle = try Fyle.get(sha256: sha256, within: context) {
            return previousFyle
        } else {
            let newFyle = Fyle(sha256: sha256, within: context)
            return newFyle
        }
    }
    
    
    func updateFyle(with obvAttachment: ObvAttachment) throws {
        try updateFyle(obvAttachmentStatus: obvAttachment.status)
    }

    
    func updateFyle(with obvOwnedAttachment: ObvOwnedAttachment) throws {
        try updateFyle(obvAttachmentStatus: obvOwnedAttachment.status)
    }

    
    public func storeHistoryTransferredAttachment(sha256: Data, temporaryURLOfAttachment: URL) throws {
        
        guard self.sha256 == sha256 else {
            assertionFailure()
            throw ObvUICoreDataError.unexpectedSha256
        }
        
        // Nothing to do if we already hold the bytes for this content.
        //
        // `Fyle` is content-addressed: `getOrCreate(sha256:)` returns one row per distinct content, shared by
        // every join that references it. So an existing local file under this hash *is* this file — there is
        // nothing to move and nothing to repair. Expected during a history transfer, where much of the
        // transferred content is already present locally.
        guard self.getFileSize() == nil else {
            Self.logger.debug("We already have a local version of this file, nothing to store")
            return
        }

        // Make sure the file is indeed available at the obvAttachmentURL.
        // If this is not the case, we throw. The exception will eventually be processed by the operation (at the app level) and a new download will be requested to the engine.
        guard FileManager.default.fileExists(atPath: temporaryURLOfAttachment.path) else {
            Self.logger.error("Could not find a file at the indicated URL")
            throw ObvUICoreDataError.couldNotFindSourceFile
        }

        // Compute the sha256 of the (complete) file indicated within the obvAttachment and compare it to what was expected
        let realHash: Data
        do {
            let sha256 = ObvCryptoSuite.sharedInstance.hashFunctionSha256()
            realHash = try sha256.hash(fileAtUrl: temporaryURLOfAttachment)
        } catch {
            throw ObvUICoreDataError.couldNotComputeSHA256
        }

        guard realHash == self.sha256 else {
            Self.logger.error("OMG, the sha256 of the received file does not match the one we expected. Expecting \(self.sha256.hexString(), privacy: .public) but the hash of the received file is \(realHash.hexString(), privacy: .public)")
            Self.logger.error("\(Self.whatIsWrongWithTheFile(at: temporaryURLOfAttachment, expectedByteCount: self.allFyleMessageJoinWithStatus.map(\.totalByteCount).max()), privacy: .public)")
            assertionFailure()
            throw ObvUICoreDataError.sha256OfReceivedFileReferenceByObvAttachmentDoesNotMatchWhatWeExpect
        }

        try self.moveFileToPermanentURL(from: temporaryURLOfAttachment, logTo: Self.log)
        
        Self.logger.debug("We moved a file received during history transfer to a permanent location")
        
        guard let fileSize = self.getFileSize() else {
            assertionFailure()
            Self.logger.fault("Could not get the file size of the copied file")
            throw ObvUICoreDataError.couldNotComputeFileSize
        }
        
        // Update the status of all joins
        
        for join in self.allFyleMessageJoinWithStatus {
            if let receivedJoin = join as? ReceivedFyleMessageJoinWithStatus {
                receivedJoin.setStatusToDownloadedDuringHistoryTransfer(fileSize: fileSize)
            } else if let sentJoin = join as? SentFyleMessageJoinWithStatus {
                sentJoin.setStatusToDownloadedDuringHistoryTransfer(fileSize: fileSize)
            }
        }
        
    }
    
    
    private func updateFyle(obvAttachmentStatus: ObvAttachment.Status) throws {
        
        // Make sure the file was downloaded and that we do not already have a local (app) version of this file
        
        switch obvAttachmentStatus {
        case .downloaded(url: let obvAttachmentURL):
            
            // Nothing to do if we already hold the bytes for this content.
            //
            // `Fyle` is content-addressed: `getOrCreate(sha256:)` returns one row per distinct content,
            // shared by every join that references it. So an existing local file under this hash *is* this
            // file, and skipping the move below is correct rather than exceptional. This is reached whenever
            // the same content arrives more than once — a photo re-sent by a contact, or the deterministic
            // transcode of one to a smaller size, both of which hash identically — and whenever an
            // attachment we have already stored is reported as downloaded again.
            guard self.getFileSize() == nil else {
                Self.logger.debug("We already have a local version of this file, nothing to download")
                return
            }
            
            // Make sure the file is indeed available at the obvAttachmentURL.
            // If this is not the case, we throw. The exception will eventually be processed by the operation (at the app level) and a new download will be requested to the engine.
            guard FileManager.default.fileExists(atPath: obvAttachmentURL.path) else {
                Self.logger.error("Could not find a file at the URL indicated by the engine, although it supposed to be complete")
                throw ObvUICoreDataError.couldNotFindSourceFile
            }

            // Compute the sha256 of the (complete) file indicated within the obvAttachment and compare it to what was expected
            let realHash: Data
            do {
                let sha256 = ObvCryptoSuite.sharedInstance.hashFunctionSha256()
                realHash = try sha256.hash(fileAtUrl: obvAttachmentURL)
            } catch {
                throw ObvUICoreDataError.couldNotComputeSHA256
            }

            guard realHash == self.sha256 else {
                let sha256HexString = self.sha256.hexString()
                Self.logger.error("OMG, the sha256 of the received file does not match the one we expected. Expecting \(sha256HexString, privacy: .public) but the hash of the received file is \(realHash.hexString(), privacy: .public)")
                Self.logger.error("\(Self.whatIsWrongWithTheFile(at: obvAttachmentURL, expectedByteCount: self.allFyleMessageJoinWithStatus.map(\.totalByteCount).max()), privacy: .public)")
                // No assertion. This used to be an unhandled condition and stopping on it was the only way to notice it; it is now the
                // entry to a repair path — `PersistedDiscussionsUpdatesCoordinator.repairAttachmentWhoseFileCannotBeUsed(_:whatWasWrong:)`
                // has the engine discard the file and fetch it again — and a debug build that traps here cannot walk that path at all.
                // The two `Self.logger.error` lines above say everything the assertion said, on every build.
                throw ObvUICoreDataError.sha256OfReceivedFileReferenceByObvAttachmentDoesNotMatchWhatWeExpect
            }

            // If we reach this point, the sha256 is correct. We move the received file to a permanent location

            // **This is the app taking a file out of the engine's inbox**, and the only routine that does so on the ordinary success path. The engine is not
            // told: it goes on believing the attachment is downloaded, with no file, until the app separately marks the attachment for deletion.
            Self.logger.info("📁 Moving the file of a downloaded attachment out of the engine's inbox: \(obvAttachmentURL.path, privacy: .public)")

            try self.moveFileToPermanentURL(from: obvAttachmentURL, logTo: Self.log)

            Self.logger.debug("We moved a downloaded file to a permanent location")

            // The bytes are on disk now, and `Fyle` is content-addressed: every other join pointing at this
            // fyle is by definition already satisfied and must stop presenting itself as downloadable.
            //
            // Joins created *after* this point notice by themselves, since their initializer checks
            // `getFileSize()`. Joins that already existed when the download landed had no such mechanism, so
            // they sat waiting for a download they did not need. Visible whenever the same content arrives
            // twice before either copy is fetched — receive a photo, receive it again, download the first,
            // and the second stayed downloadable while a *third* copy would arrive already complete.
            if let fileSize = self.getFileSize() {
                for join in self.allFyleMessageJoinWithStatus {
                    if let receivedJoin = join as? ReceivedFyleMessageJoinWithStatus {
                        receivedJoin.setStatusToCompleteAsFyleContentIsAvailable(fileSize: fileSize)
                    } else if let sentJoin = join as? SentFyleMessageJoinWithStatus {
                        sentJoin.setStatusToCompleteAsFyleContentIsAvailable(fileSize: fileSize)
                    }
                }
            }
            
        default:
            return
            
        }
        
    }

}


// MARK: - Saying what is wrong with a file whose hash does not match

extension Fyle {

    /// Describes a downloaded file whose sha256 does not match the one expected, at the one moment its bytes are still on disk.
    ///
    /// **It exists because the failure it reports is otherwise undiagnosable.** A mismatch means the received bytes are wrong, and nothing else says anything about
    /// *how* they are wrong.
    ///
    /// The two families below are the **chunked download**'s, which is where this was first needed: the hash the sender stated is known to be right, an
    /// uninterrupted download of the same file having matched it, and every chunk that *was* downloaded is authenticated, so some region of the file holds bytes
    /// that no successful chunk write ever put there. A history transfer moves whole files over a different transport and its own failures will not divide this
    /// way — but *where the file goes wrong* is worth having whatever brought the bytes in, which is why both callers use this.
    ///
    /// - **A hole.** A chunk was flagged as written but its bytes never landed, or the file was replaced under the download. The file is created at zero length and
    ///   grows sparsely, so an unwritten region reads back as **zeros**.
    /// - **Bytes in the wrong place.** A chunk's data was written at another chunk's offset — the offset is derived from a chunk number carried in the
    ///   `taskDescription` of a background `URLSession` task, which has to survive that session being torn down and rehydrated. Authenticated decryption still
    ///   passes, because it *is* a valid chunk; it is merely the wrong one. There are then **no zeros**, only plausible data in the wrong order.
    ///
    /// So the presence or absence of large zero regions separates the two, and that is the whole purpose of this. Everything else it reports — the size against
    /// what was expected, where the zeros begin and how long they run — is what turns "it happened again" into a lead.
    ///
    /// **Permanent, not temporary instrumentation.** It runs only on the failure path, where the file has *already* been read end to end to hash it, so it costs a
    /// second pass over a file that is by then known to be bad, and nothing at all in the overwhelming case where the hash matches.
    ///
    /// The window is a compromise: a hole shorter than ``theWindowScannedForZeros`` or straddling two windows is not reported, but a chunk is orders of magnitude
    /// larger than this, so any hole big enough to matter is seen. It is not a proof that the file has no zeros — it is a lead.
    fileprivate static func whatIsWrongWithTheFile(at url: URL, expectedByteCount: Int64?) -> String {

        let actualByteCount = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? nil

        var said = "The file that did not hash as expected: "
        switch (actualByteCount, expectedByteCount) {
        case (.some(let actual), .some(let expected)):
            said += "\(actual) bytes on disk against \(expected) expected, \(actual == expected ? "which agree" : "a difference of \(expected - actual)")"
        case (.some(let actual), .none):
            said += "\(actual) bytes on disk, nothing to compare it against"
        default:
            said += "its size could not be read"
        }

        do {
            let zeros = try runsOfZeros(in: url)
            if zeros.runs.isEmpty {
                // The interesting case, and the one that would send the next reader to the chunk-number bookkeeping rather than to the file writing.
                said += " | no run of zeros as long as \(theWindowScannedForZeros) bytes anywhere, so the bytes are wrong rather than missing"
            } else {
                said += " | \(zeros.totalBytes) bytes of zeros in \(zeros.runs.count) run(s)"
                // A handful is enough to see the shape, and a holed file could otherwise put thousands of them in the log.
                for run in zeros.runs.prefix(theMostZeroRunsWorthNaming) {
                    said += ", [\(run.offset)…\(run.offset + run.length)) is \(run.length) long"
                }
                if zeros.runs.count > theMostZeroRunsWorthNaming {
                    said += ", and \(zeros.runs.count - theMostZeroRunsWorthNaming) more"
                }
            }
        } catch {
            said += " | its contents could not be scanned: \(error.localizedDescription)"
        }

        return said
    }


    /// Where the file reads back as zeros, found in one streaming pass.
    ///
    /// Windows rather than bytes: a whole window is tested at once, and consecutive all-zero windows are joined into one run. The file may be a gigabyte, so it is
    /// never held in memory, and the test is made over `UInt64` words rather than bytes so that a pass costs a read rather than a loop.
    private static func runsOfZeros(in url: URL) throws -> (runs: [(offset: Int64, length: Int64)], totalBytes: Int64) {

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var runs: [(offset: Int64, length: Int64)] = []
        var totalBytes: Int64 = 0
        var offset: Int64 = 0
        var theRunInProgress: Int64?

        while let window = try handle.read(upToCount: theWindowScannedForZeros), !window.isEmpty {
            let length = Int64(window.count)
            if window.isEntirelyZero {
                totalBytes += length
                if theRunInProgress == nil { theRunInProgress = offset }
            } else if let start = theRunInProgress {
                runs.append((offset: start, length: offset - start))
                theRunInProgress = nil
            }
            offset += length
        }
        if let start = theRunInProgress {
            runs.append((offset: start, length: offset - start))
        }

        return (runs, totalBytes)
    }


    /// How much of the file is tested for zeros at a time. Large enough that a pass over a gigabyte is a few thousand reads, small enough to locate a hole usefully.
    private static let theWindowScannedForZeros = 64 * 1024

    /// Enough runs to see the shape of the damage. A file full of holes would otherwise write thousands of lines into the log.
    private static let theMostZeroRunsWorthNaming = 8

}


private extension Data {

    /// Whether every byte is zero, tested a word at a time.
    ///
    /// Byte by byte over a gigabyte is a loop the compiler cannot help with; over `UInt64` it is an eighth of the iterations on contiguous memory. The remainder —
    /// only ever the last few bytes of the last window — is tested as bytes.
    ///
    /// **`loadUnaligned` rather than `bindMemory`**, which is not a style choice: a `Data`'s buffer carries no alignment guarantee, so binding it to `UInt64` is
    /// undefined behaviour on any platform that minds, and it would work in testing on every platform that does not.
    var isEntirelyZero: Bool {
        withUnsafeBytes { raw in
            let bytesInAWord = MemoryLayout<UInt64>.size
            var index = 0
            while index + bytesInAWord <= raw.count {
                if raw.loadUnaligned(fromByteOffset: index, as: UInt64.self) != 0 { return false }
                index += bytesInAWord
            }
            while index < raw.count {
                if raw[index] != 0 { return false }
                index += 1
            }
            return true
        }
    }

}


// MARK: - Other methods

extension Fyle {
    
    public func fyleMessageJoinWithStatuses(ownedCryptoId: ObvCryptoId) -> Set<FyleMessageJoinWithStatus> {
        allFyleMessageJoinWithStatus.filter { $0.message?.discussion?.ownedIdentity?.cryptoId == ownedCryptoId }
    }

    func remove(_ draftFyleJoin: PersistedDraftFyleJoin) {
        self.allDraftFyleJoins.remove(draftFyleJoin)
    }
    
    public var filenameOnDisk: String {
        sha256.hexString()
    }
    
    private var isAttachedToPreview: Bool {
        !allFyleMessageJoinWithStatus.filter { $0.uti == UTType.olvidPreviewUti }.isEmpty
    }
    
    public var url: URL {
        if let transientURL {
            return transientURL
        } else {
            return Fyle.getFileURL(lastPathComponent: filenameOnDisk)
        }
    }

    public static func getFileURL(lastPathComponent: String) -> URL {
        ObvUICoreDataConstants.ContainerURL.forFyles.appendingPathComponent(lastPathComponent)
    }


    public func getFileSize() -> Int64? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return fileAttributes[FileAttributeKey.size] as? Int64
    }
    
    
    public var fileExistsOnDisk: Bool {
        self.getFileSize() != nil
    }
    
}


// MARK: File management on disk

extension Fyle {
    
    // MARK: - Other methods
    
    public func writeDataToPermanentURL(from data: Data, logTo log: OSLog) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            // Not a big deal since the file a certainly identical
            os_log("The destination file already exists, won't write into the file", log: log, type: .debug)
        } else {
            os_log("writing data to %@", log: log, type: .debug, url.debugDescription)
            try data.write(to: url)
        }
    }
    
    public func moveFileToPermanentURL(from fromUrl: URL, logTo log: OSLog) throws {

        guard FileManager.default.fileExists(atPath: fromUrl.path) else {
            os_log("Could not find the source file", log: log, type: .error)
            Self.logger.info("📁 Not moving \(fromUrl.path, privacy: .public) into the Fyle store: there is no file there")
            throw ObvUICoreDataError.couldNotFindSourceFile
        }
        
        if FileManager.default.fileExists(atPath: url.path) {
            // Not a big deal since the file a certainly identical
            os_log("The destination file already exists, won't move the file", log: log, type: .debug)
            // Said out loud because the source is then **left where it was**, which for an attachment means the engine's copy stays in the inbox.
            Self.logger.info("📁 Not moving \(fromUrl.path, privacy: .public) into the Fyle store: the destination \(self.url.path, privacy: .public) already holds this content, so the source is left where it is")
        } else {
            os_log("Moving a file from %@ to %@", log: log, type: .debug, fromUrl.debugDescription, url.debugDescription)
            Self.logger.info("📁 Moving \(fromUrl.path, privacy: .public) into the Fyle store at \(self.url.path, privacy: .public). Nothing is left at the source")
            try FileManager.default.moveItem(atPath: fromUrl.path, toPath: url.path)
        }
    }
    
    
    func copyFileToPermanentURL(from fromURL: URL, logTo log: OSLog) throws {
        
        guard FileManager.default.fileExists(atPath: fromURL.path) else {
            os_log("Could not find the source file", log: log, type: .error)
            throw ObvUICoreDataError.couldNotFindSourceFile
        }
        
        if FileManager.default.fileExists(atPath: url.path) {
            // Not a big deal since the file a certainly identical
            os_log("The destination file already exists, won't copy file", log: log, type: .debug)
        } else {
            os_log("Copying a file from %@ to %@", log: log, type: .debug, fromURL.debugDescription, url.debugDescription)
            try FileManager.default.copyItem(at: fromURL, to: url)
        }
        
    }
    
    
    public func moveFileToTrash() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let trashURL = ObvUICoreDataConstants.ContainerURL.forTrash.appendingPathComponent(UUID().uuidString)
        try FileManager.default.moveItem(at: url, to: trashURL)
    }

    
}


// MARK: - Convenience DB getters

extension Fyle {
    
    struct Predicate {
        enum Key: String {
            case sha256 = "sha256"
            case allDraftFyleJoins = "allDraftFyleJoins"
            case allDraftFyleJoinVariants = "allDraftFyleJoinVariants"
            case allFyleMessageJoinWithStatus = "allFyleMessageJoinWithStatus"
        }
        fileprivate static func withSha256(_ sha256: Data) -> NSPredicate {
            NSPredicate(Key.sha256, EqualToData: sha256)
        }
        /// A `Fyle` nothing points at, which the app sweeps and whose file it moves to the trash.
        ///
        /// **Every relationship into `Fyle` must be named here, or files in use are deleted.** The smaller sizes of a draft's attachments
        /// are held only by `PersistedDraftFyleJoinVariant`, so without the third clause every one of them would be swept.
        ///
        /// Internal so that `FyleOrphanPredicateTests` can check it against the model.
        static var isOrphaned: NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(withZeroCountForKey: Key.allFyleMessageJoinWithStatus),
                NSPredicate(withZeroCountForKey: Key.allDraftFyleJoins),
                NSPredicate(withZeroCountForKey: Key.allDraftFyleJoinVariants),
            ])
        }
    }

    @nonobjc static func fetchRequest() -> NSFetchRequest<Fyle> {
        return NSFetchRequest<Fyle>(entityName: Fyle.entityName)
    }
    

    static func get(objectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> Fyle? {
        return try context.existingObject(with: objectID) as? Fyle
    }

    
    /// Returns a `Fyle` if one can be found for the given sha256.
    public static func get(sha256: Data, within context: NSManagedObjectContext) throws -> Fyle? {
        let request: NSFetchRequest<Fyle> = Fyle.fetchRequest()
        request.predicate = Predicate.withSha256(sha256)
        request.fetchLimit = 1
        let fyles = try context.fetch(request)
        return fyles.first
    }
        
    public static func getAll(within context: NSManagedObjectContext) throws -> [Fyle] {
        let request: NSFetchRequest<Fyle> = Fyle.fetchRequest()
        request.fetchBatchSize = 500
        return try context.fetch(request)
    }

    /// Returns all orphaned `Fyle` entities, i.e., those that have no associated `PersistedDraftFyleJoin` and no associated `FyleMessageJoinWithStatus`.
    public static func getAllOrphaned(within context: NSManagedObjectContext) throws -> [Fyle] {
        let request: NSFetchRequest<Fyle> = Fyle.fetchRequest()
        request.predicate = Predicate.isOrphaned
        request.fetchBatchSize = 500
        return try context.fetch(request)
    }
    
    
    /// Returns the filename of all the `Fyles`.
    public static func getAllFilenames(within context: NSManagedObjectContext) throws -> [String] {
        let request: NSFetchRequest<Fyle> = Fyle.fetchRequest()
        request.propertiesToFetch = [Predicate.Key.sha256.rawValue]
        request.fetchBatchSize = 500
        let results = try context.fetch(request)
        let filenamesOnDisk = results.map({ $0.filenameOnDisk })
        return filenamesOnDisk
    }
    
    
    public static func noFyleReferencesTheURL(_ url: URL, within context: NSManagedObjectContext) throws -> Bool {
        let request = NSFetchRequest<NSManagedObjectID>(entityName: Fyle.entityName)
        let filename = url.lastPathComponent
        guard let sha256 = Data(hexString: filename) else { return true }
        assert(sha256.count == 32)
        request.predicate = Predicate.withSha256(sha256)
        request.resultType = .managedObjectIDResultType
        request.fetchLimit = 1
        let objects: [NSManagedObjectID] = try context.fetch(request)
        return objects.isEmpty
    }
    
}
