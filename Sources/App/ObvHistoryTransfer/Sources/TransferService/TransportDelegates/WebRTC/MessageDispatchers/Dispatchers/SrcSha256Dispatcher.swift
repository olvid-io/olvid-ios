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
import ObvAppCoreConstants

/// Dispatcher used by the destination when requesting an attachment to the source.
///
/// The URL returned by
/// ```
/// func urlOfReceivedFile(sha256: Data, expectedFileSize: UInt64) async throws -> URL
///
/// ```
/// is temporary. We expect the app to move the file found at this URL to an appropriate location. For this reason, we do not delete the temporary files ourselves.
actor SrcSha256Dispatcher {
    
    private let temporaryDirectory: URL
    
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "SrcSha256Dispatcher")
    
    //private var continuationForSha256 = [Data : CheckedContinuation<URL, any Error>]()
    private var continuationForSha256 = [Data : AsyncThrowingStream<FileReceptionProgress, Error>.Continuation]()
    private var urlForSha256 = [Data : URL]() // Only contains URL of fully received files
    
    private var expectedFileSizes = [Data : UInt64]()
    
    private var failedSha256 = Set<Data>()
    
    private static let sha256length = 32
    private static let fileOffsetLength = 8
    
    let Sha256 = ObvCryptoSuite.sharedInstance.hashFunctionSha256()

    //private var progressUpdater: (any FyleProgressUpdater)?
    
    init(temporaryDirectory: URL) {
        self.temporaryDirectory = temporaryDirectory.appending(path: "ObvReceivedAttachmentsForHistoryTransfer", directoryHint: .isDirectory)
        // Note that this init is called each time we start a transfer
        if FileManager.default.fileExists(atPath: self.temporaryDirectory.path) {
            do { try FileManager.default.removeItem(at: self.temporaryDirectory) } catch { assertionFailure() }
        }
    }
    
    enum FileReceptionProgress: Sendable {
        case inProgress(sha256: Data, currentFileSize: UInt64)
        case fileReceived(sha256: Data, url: URL)
    }
    
    func getStreamOfReceivedFileProgress(sha256: Data, expectedFileSize: UInt64) -> AsyncThrowingStream<FileReceptionProgress, Error> {
        expectedFileSizes[sha256] = expectedFileSize
        let stream = AsyncThrowingStream<FileReceptionProgress, Error> { (continuation: AsyncThrowingStream<FileReceptionProgress, Error>.Continuation) in
            guard continuationForSha256[sha256] == nil else {
                assertionFailure()
                return continuation.finish(throwing: ObvError.urlRequestedTwice)
            }
            self.continuationForSha256[sha256] = continuation
            yieldURLIfPossible(sha256: sha256)
        }
        return stream
    }
    
//    func urlOfReceivedFile(sha256: Data, expectedFileSize: UInt64, progressUpdater: any FyleProgressUpdater) async throws -> URL {
//        self.progressUpdater = progressUpdater
//        expectedFileSizes[sha256] = expectedFileSize
//        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, any Error>) in
//            guard continuationForSha256[sha256] == nil else {
//                assertionFailure()
//                return continuation.resume(throwing: ObvError.urlRequestedTwice)
//            }
//            self.continuationForSha256[sha256] = continuation
//            yieldURLIfPossible(sha256: sha256)
//        }
//    }
    
    
    /// Processes the data received  in a `.sourceSha256` message by this destination device.
    ///
    /// The received data is made of
    /// - the sha256 of the full file
    /// - the file offset where the received chunk should be written
    /// - followed by a chunk of the attachment
    ///
    /// After parsing the data, we save received chunk into a file
    func saveAttachmentChunkReceivedInSourceSha256Message(_ data: Data) {
        
        // Parse the received data
        
        let sha256 = data.prefix(Self.sha256length)
        guard sha256.count == Self.sha256length else { assertionFailure(); return }
        
        guard !failedSha256.contains(sha256) else { yieldURLIfPossible(sha256: sha256); return }
        
        do {
            
            let offetAndChunk = Data(data.suffix(from: data.startIndex.advanced(by: Self.sha256length)))
            guard offetAndChunk.count > Self.fileOffsetLength else { assertionFailure(); return }
            
            let fileOffset = try UInt64.from8Bytes(offetAndChunk.prefix(Self.fileOffsetLength))
            
            let chunk = data.suffix(from: data.startIndex.advanced(by: Self.sha256length + Self.fileOffsetLength))
            guard chunk.count > 0 else { assertionFailure(); return }

            // Write the file chunk to the attachment file
            
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            
            let url: URL
            if let _url = urlForSha256[sha256] {
                url = _url
            } else {
                url = temporaryDirectory.appending(path: UUID().uuidString)
                urlForSha256[sha256] = url
            }
            
            if let fh = try? FileHandle(forWritingTo: url) {
                defer { try? fh.close() }
                Self.logger.debug("📰 [\(sha256.hexString().prefix(8))] Seek to \(fileOffset)")
                try fh.seek(toOffset: fileOffset)
                try fh.write(contentsOf: chunk)
            } else {
                FileManager.default.createFile(atPath: url.path, contents: chunk)
            }
            
            // If the file has the expected final size, compute its sha256, check
            // that it matches the expected sha256 and move the url from `uncompleted`
            // to `urlForSha256`.
            
            yieldURLIfPossible(sha256: sha256)
            
        } catch {
            if !failedSha256.contains(sha256) {
                failedSha256.insert(sha256)
                yieldURLIfPossible(sha256: sha256)
            }
        }
        
    }
    
    
    private func yieldURLIfPossible(sha256: Data) {
        
        guard let continuation = self.continuationForSha256[sha256] else { return }
        
        if failedSha256.contains(sha256) {
            
            self.continuationForSha256.removeValue(forKey: sha256)
            return continuation.finish(throwing: ObvError.failure)
            
        } else {
            
            guard let url = self.urlForSha256[sha256] else { return }
            guard let expectedFileSize = expectedFileSizes[sha256] else { return }
            guard let currentFileSize = FileManager.default.getFileSize(at: url) else { return }
            
            if currentFileSize < expectedFileSize {
                Self.logger.debug("📰 [\(sha256.hexString().prefix(8))] current file size (\(currentFileSize)) < expected file size (\(expectedFileSize))")
                
                continuation.yield(.inProgress(sha256: sha256, currentFileSize: currentFileSize))
                
            } else {
                
                Self.logger.debug("📰 [\(sha256.hexString().prefix(8))] File size ok")

                defer {
                    self.continuationForSha256.removeValue(forKey: sha256)
                    self.urlForSha256.removeValue(forKey: sha256)
                }
                
                do {
                    
                    let computedSha256 = try Sha256.hash(fileAtUrl: url)
                    guard sha256 == computedSha256 else {
                        Self.logger.fault("📰 [\(sha256.hexString().prefix(8))] Sha256 mismatch!!!!!!")
                        throw ObvError.sha256DoNotMatch
                    }
                    Self.logger.debug("📰 [\(sha256.hexString().prefix(8))] Sha256 match")
                    continuation.yield(.fileReceived(sha256: sha256, url: url))
                    continuation.finish()
                    
                } catch {
                    
                    assertionFailure()
                    try? FileManager.default.removeItem(at: url)
                    continuation.finish(throwing: ObvError.sha256DoNotMatch)
                    
                }
                    
            }

        }
        
        
    }
    
    enum ObvError: Error {
        case urlRequestedTwice
        case failure
        case sha256DoNotMatch
    }
    
}


// Private helpers

private extension FileManager {
    
    func getFileSize(at url: URL) -> UInt64? {
        guard self.fileExists(atPath: url.path) else { return nil }
        do {
            let attributes = try self.attributesOfItem(atPath: url.path)
            return attributes[.size] as? UInt64
        } catch {
            assertionFailure()
            return nil
        }
    }
    
}


extension SrcSha256Dispatcher {
    
    func finishAllDispatchesByThrowing(_ error: any Error) {
        while let continuation = continuationForSha256.popFirst() {
            continuation.value.finish(throwing: error)
        }
    }
    
}
