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
import OSLog
import ObvCrypto
import ObvEncoder

public struct Chunk {
    
    public let index: Int
    public let data: Data // Cleartext
    
    private init(index: Int, data: Data) {
        self.index = index
        self.data = data
    }

    private static let logger = Logger(subsystem: "io.olvid.messenger", category: "Chunk")

    enum ObvError: Error {
        /// A chunk was to be written into a file that is not there. The file is created up front and in full, so this can only mean something has removed it —
        /// see ``writeToURL(_:offset:)``, which says what that cost when it was answered by creating a new one.
        case theFileToWriteTheChunkIntoDoesNotExist(chunkIndex: Int, offset: Int)
    }

    private static let errorDomain = "Chunk"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    public static func readFromURL(_ url: URL, offset: Int, length: Int, index: Int) throws -> Chunk {

        let chunk: Chunk
        
        do {
            let fd = open(url.path, O_RDONLY)
            guard fd != -1 else {
                throw Self.makeError(message: "Failed to read from URL (bad fd)")
            }
            guard offset == lseek(fd, Int64(offset), SEEK_SET) else {
                assertionFailure()
                throw Self.makeError(message: "Failed to read from URL (bad lseek)")
            }
            let chunkPointer = UnsafeMutableRawPointer.allocate(byteCount: length, alignment: 1)
            let lengthRead = read(fd, chunkPointer, length)
            guard length == lengthRead else {
                assertionFailure()
                free(chunkPointer)
                close(fd)
                throw Self.makeError(message: "Failed to read from URL (bad length)")
            }
            let chunkData = Data(bytes: chunkPointer, count: length)
            chunk = Chunk(index: index, data: chunkData)
            free(chunkPointer)
            close(fd)
        }
        
        return chunk
        
    }

    /// Writes this chunk at its place in the file, which **must already exist**.
    ///
    /// **It used to create the file and its directory when they were missing, and that silently turned somebody else's deletion into a corrupt download.**
    /// The file is made once, up front, by `InboxAttachment.createEmptyFileForWritingChunks(withinInbox:cleartextLength:)` — the whole length of it, sparse,
    /// as soon as the decryption key and metadata arrive — and a chunk cannot be decrypted before that key exists. So by the time any chunk reaches this
    /// method, the file and its directory are there by construction. There has never been a legitimate case for making them here.
    ///
    /// What the old behaviour cost, on 2026-08-31: the inbox's orphan sweep was deleting live message directories on every return to the foreground (fixed in
    /// `BootstrapWorker`), and this method quietly rebuilt an empty file and wrote chunk *n* into it. Every chunk before *n* became a hole — their
    /// *written* flags live in Core Data and survived the deletion, so nothing ever re-fetched them. A 1GB attachment finished at exactly the right size with
    /// its first 590MB reading as zeros, and failed its sha256 with no way back. Throwing here would have said so the first time it happened, on the first
    /// attachment it happened to, instead of after a gigabyte.
    ///
    /// So: a write to a file that is not there is **not** a file to be created. It is a fault somewhere else, and it is reported rather than papered over.
    public func writeToURL(_ url: URL, offset: Int) throws {

        guard FileManager.default.fileExists(atPath: url.path) else {
            // **Which of the two is missing narrows the search by half.** The file alone gone points at something that took that one file — the app moving it
            // into the `Fyle` store, or the engine remaking it — where the directory gone with it points at the message being deleted from the server or at
            // the inbox's orphan sweep. Reported here because this is the only moment at which either is known to have happened.
            let directory = url.deletingLastPathComponent()
            let directoryIsStillThere = FileManager.default.fileExists(atPath: directory.path)
            Self.logger.fault("📁 Refusing to write chunk \(self.index) at offset \(offset) into \(url.path, privacy: .public): there is no file at the given URL. It is created up front, so something has removed it, and every chunk already written has gone with it. Its message directory \(directoryIsStillThere ? "IS still there, so the file alone was removed" : "is GONE too, so the whole message directory was removed", privacy: .public)")
            assertionFailure()
            throw ObvError.theFileToWriteTheChunkIntoDoesNotExist(chunkIndex: index, offset: offset)
        }

        let fd = open(url.path, O_RDWR)
        guard fd != -1 else {
            assertionFailure()
            throw Self.makeError(message: "Failed to read from URL (bad fd)")
        }
        guard offset == lseek(fd, Int64(offset), SEEK_SET) else {
            assertionFailure()
            throw Self.makeError(message: "Failed to read from URL (bad lseek)")
        }
        let lengthWritten: Int = data.withUnsafeBytes { (rawBufferPtr) in
            guard let rawPtr = rawBufferPtr.baseAddress else { return -1 }
            return write(fd, rawPtr, data.count)
        }
        guard lengthWritten == data.count else {
            assertionFailure()
            throw Self.makeError(message: "Failed to read from URL (bad lengthWritten)")
        }
        close(fd)
        // One line per chunk, so a log holds the last moment at which the file is known to have been there. Without it, a refusal above cannot be told from
        // *the file was never made* — the whole question this probe exists to answer.
        //
        // The directory and the file name rather than the whole path, this being the one line here that repeats: the container prefix in front of it is the
        // same for every line of the log and identifies nothing. The full path stays on the refusal above, which is the line worth pasting into a report.
        let nameWithinTheInbox = "\(url.deletingLastPathComponent().lastPathComponent)/\(url.lastPathComponent)"
        Self.logger.info("📁 Wrote chunk \(self.index) of \(self.data.count) bytes at offset \(offset) into \(nameWithinTheInbox, privacy: .public)")
    }
    
    public func encrypt(with key: AuthenticatedEncryptionKey) -> EncryptedData {
        let prngService = ObvCryptoSuite.sharedInstance.prngService()
        let authEnc = key.algorithmImplementationByteId.algorithmImplementation
        let encodedChunk = self.obvEncode()
        return try! authEnc.encrypt(encodedChunk.rawData, with: key, and: prngService) // Cannot throw in this case
    }

    
    public static func decrypt(encryptedChunk: EncryptedData, with key: AuthenticatedEncryptionKey) throws -> Chunk {
        let authEnc = key.algorithmImplementationByteId.algorithmImplementation
        let rawEncodedChunk = try authEnc.decrypt(encryptedChunk, with: key)
        guard let encodedChunk = ObvEncoded(withRawData: rawEncodedChunk) else {
            throw Self.makeError(message: "ObvEncoded init failed")
        }
        guard let chunk = Chunk(encodedChunk) else {
            throw Self.makeError(message: "Chunk init failed")
        }
        return chunk
    }
        
    public static func decrypt(encryptedChunkAtFileHandle fh: FileHandle, with key: AuthenticatedEncryptionKey) throws -> Chunk {
        fh.seek(toFileOffset: 0)
        let encryptedChunkRaw = try fh.readToEnd()
        guard let data = encryptedChunkRaw else { throw Chunk.makeError(message: "No chunk data found at file handle") }
        let encryptedChunk = EncryptedData(data: data)
        return try decrypt(encryptedChunk: encryptedChunk, with: key)
    }
    
    public static func cleartextLengthFromEncryptedLength(_ encryptedLength: Int, whenUsingEncryptionKey key: AuthenticatedEncryptionKey) throws -> Int {
        let encodedChunkLength = try AuthenticatedEncryption.plaintexLength(forCiphertextLength: encryptedLength, whenDecryptedUnder: key)
        guard let length = Chunk.lengthOfInnerData(forLengthOfObvEncodedChunk: encodedChunkLength) else {
            throw makeError(message: "Could not parse the cleartext length from the encrypted length")
        }
        return length
    }
    
    
    public static func encryptedLengthFromCleartextLength(_ cleartextLength: Int, whenUsingEncryptionKey key: AuthenticatedEncryptionKey) -> Int {
        let encodedChunkLength = Chunk.lengthWhenObvEncoded(forLengthOfInnerData: cleartextLength)
        return AuthenticatedEncryption.ciphertextLength(forPlaintextLength: encodedChunkLength, whenEncryptedUnder: key)
    }

    
}


extension Chunk: ObvCodable {
    
    public func obvEncode() -> ObvEncoded {
        let encodedIndex = self.index.obvEncode()
        let encodedData = self.data.obvEncode()
        return [encodedIndex, encodedData].obvEncode()
    }
    
    public init?(_ obvEncoded: ObvEncoded) {
        guard let decodedList = [ObvEncoded](obvEncoded) else { return nil }
        guard decodedList.count == 2 else { return nil }
        let encodedIndex = decodedList[0]
        let encodedData = decodedList[1]
        guard let index = Int(encodedIndex) else { return nil }
        guard let data = Data(encodedData) else { return nil }
        self.init(index: index, data: data)
    }
    
    public static func lengthOfInnerData(forLengthOfObvEncodedChunk lengthOfEncoded: Int) -> Int? {
        let length = lengthOfEncoded - 2*ObvEncoded.lengthOverhead - Int.lengthWhenObvEncoded
        guard length >= 0 else { return nil }
        return length
    }
    
    public static func lengthWhenObvEncoded(forLengthOfInnerData length: Int) -> Int {
        return length + 2*ObvEncoded.lengthOverhead + Int.lengthWhenObvEncoded
    }
    
    public static func innerDataLength(fromLengthWhenEncoded encodedLength: Int) -> Int? {
        let res = encodedLength - (2*ObvEncoded.lengthOverhead + Int.lengthWhenObvEncoded)
        guard res >= 0 else { return nil }
        return res
    }
}
