/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import ObvTypes
import ObvCrypto
import ObvMetaManager
import OlvidUtils


final class EncryptAttachmentChunkOperation: Operation {
    
    enum ReasonForCancel: Hashable {
        case contextCreatorIsNotSet
        case chunkNumberDoesNotExist
        case cannotFindAttachmentInDatabase
        case couldNotReadCleartextChunk
        case couldNotWriteEncryptedChunkToFile
        case attachmentFileCannotBeRead
        case couldNotSaveContext
        case fileDoesNotExistAnymore
    }

    private let uuid = UUID()
    let attachmentId: AttachmentIdentifier
    let chunkNumber: Int
    private let logSubsystem: String
    private let log: OSLog
    private let flowId: FlowIdentifier
    private let logCategory = String(describing: EncryptAttachmentChunkOperation.self)
    private let outbox: URL

    weak var contextCreator: ObvCreateContextDelegate?
    
    private(set) var reasonForCancel: ReasonForCancel?
    
    init(attachmentId: AttachmentIdentifier, chunkNumber: Int, outbox: URL, logSubsystem: String, flowId: FlowIdentifier, contextCreator: ObvCreateContextDelegate) {
        self.attachmentId = attachmentId
        self.chunkNumber = chunkNumber
        self.flowId = flowId
        self.logSubsystem = logSubsystem
        self.log = OSLog(subsystem: logSubsystem, category: logCategory)
        self.contextCreator = contextCreator
        self.outbox = outbox
        super.init()
        os_log("EncryptAttachmentChunkOperation %{public}@ was initialized for chunk %{public}d of attachment %{public}@", log: log, type: .info, uuid.description, chunkNumber, attachmentId.debugDescription)
    }
    
    deinit {
        os_log("EncryptAttachmentChunkOperation %{public}@ is deinitialized", log: log, type: .info, uuid.description)
    }
    
    private func cancel(withReason reason: ReasonForCancel) {
        assert(self.reasonForCancel == nil)
        self.reasonForCancel = reason
        self.cancel()
    }

    
    override func main() {
        
        guard let contextCreator = self.contextCreator else {
            assertionFailure()
            cancel(withReason: .contextCreatorIsNotSet)
            return
        }

        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
            guard let attachment = OutboxAttachment.get(attachmentId: attachmentId, within: obvContext) else {
                return cancel(withReason: .cannotFindAttachmentInDatabase)
            }
            
            guard chunkNumber >= 0 && chunkNumber < attachment.chunks.count else {
                return cancel(withReason: .chunkNumberDoesNotExist)
            }
            
            let outboxAttachmentChunk = attachment.chunks[chunkNumber]
            
            if let url = outboxAttachmentChunk.encryptedChunkURL, let size = try? getFileSize(url: url), size == outboxAttachmentChunk.ciphertextChunkLength {
                os_log("👑 Encrypted chunk file already exists at URL %{public}@. No need to encrypt it again.", log: log, type: .info, url.debugDescription)
                return
            } else if let url = outboxAttachmentChunk.encryptedChunkURL {
                os_log("👑 Removing encrypted chunk file at URL %{public}@ (if it even exists) and removing URL from DB. We will encrypt it again now.", log: log, type: .info, url.debugDescription)
                try? FileManager.default.removeItem(at: url)
                outboxAttachmentChunk.encryptedChunkURL = nil
            }
            
            // If we reach this point, the chunk has not been encrypted yet. We do so now.
            
            guard attachment.fileURL.isFileURL else {
                os_log("File for attachment %{public}@ cannot be read", log: log, type: .fault, attachmentId.debugDescription)
                return cancel(withReason: .attachmentFileCannotBeRead)
            }
            
            guard FileManager.default.fileExists(atPath: attachment.fileURL.path) else {
                os_log("File for attachment %{public}@ cannot be found on disk. It has probably been deleted,", log: log, type: .fault, attachmentId.debugDescription)
                return cancel(withReason: .fileDoesNotExistAnymore)
            }

            let chunk: Chunk
            do {
                let offset: Int = chunkNumber == 0 ? 0 : attachment.chunks[0..<chunkNumber].reduce(0, { $0 + $1.cleartextChunkLength })
                chunk = try Chunk.readFromURL(attachment.fileURL, offset: offset, length: outboxAttachmentChunk.cleartextChunkLength, index: chunkNumber)
            } catch {
                os_log("Could not read attachment chunk from URL %{public}@ corresponding to attachment %{public}@", log: log, type: .fault, attachment.fileURL.debugDescription, attachment.attachmentId.debugDescription)
                return cancel(withReason: .couldNotReadCleartextChunk)
            }
            
            let encryptedChunkData = chunk.encrypt(with: attachment.key)
            assert(encryptedChunkData.count == outboxAttachmentChunk.ciphertextChunkLength)
            
            let encryptedChunkURL: URL
            do {
                encryptedChunkURL = try writeEncryptedChunkToTempFile(encryptedChunk: encryptedChunkData, outbox: outbox)
            } catch {
                os_log("Could not write encrypted chunk %{public}d of attachment %{public}@ to file: %{public}@", log: log, type: .fault, chunkNumber, attachmentId.debugDescription, error.localizedDescription)
                return cancel(withReason: .couldNotWriteEncryptedChunkToFile)
            }

            attachment.chunks[chunkNumber].encryptedChunkURL = encryptedChunkURL

            do {
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Could not save context: %{public}@", log: log, type: .fault, error.localizedDescription)
                try? FileManager.default.removeItem(at: encryptedChunkURL)
                return cancel(withReason: .couldNotSaveContext)
            }
            
        }
        
    }
}


// MARK: - Helpers

extension EncryptAttachmentChunkOperation {

    private func writeEncryptedChunkToTempFile(encryptedChunk: EncryptedData, outbox: URL) throws -> URL {
        // If required, create a directory for all that attachments of the message
        let messageDirectory = outbox.appendingPathComponent(attachmentId.messageId.directoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: messageDirectory.path) {
            try FileManager.default.createDirectory(at: messageDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        // If required, create a directory for this attachment
        let attachmentDirectory = messageDirectory.appendingPathComponent(attachmentId.directoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: attachmentDirectory.path) {
            try FileManager.default.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        // Write the chunk
        let chunkFileName = "\(chunkNumber)"
        let encryptedChunkURL = URL(string: chunkFileName, relativeTo: attachmentDirectory)!
        try encryptedChunk.raw.write(to: encryptedChunkURL)
        return encryptedChunkURL
    }


    private func getFileSize(url: URL) throws -> Int {
        guard FileManager.default.fileExists(atPath: url.path) else { throw NSError() }
        guard let size = try FileManager.default.attributesOfItem(atPath: url.path)[FileAttributeKey.size] as? Int else { assertionFailure(); throw NSError() }
        return size
    }
}


extension MessageIdentifier {
    
    var directoryName: String {
        let sha256 = ObvCryptoSuite.sharedInstance.hashFunctionSha256()
        return sha256.hash(self.rawValue).hexString()
    }
    
}

extension AttachmentIdentifier {
    
    var directoryName: String {
        return "\(self.attachmentNumber)"
    }
}
