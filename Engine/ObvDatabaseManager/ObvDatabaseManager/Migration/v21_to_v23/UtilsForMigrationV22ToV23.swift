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
import ObvMetaManager
import ObvCrypto

fileprivate let errorDomain = "ObvEngineMigrationV21ToV23"
fileprivate let debugPrintPrefix = "[\(errorDomain)][UtilsForMigrationV21ToV23]"

final class UtilsForMigrationV21ToV23 {
    
    static let shared = UtilsForMigrationV21ToV23()

    private init() {}

    private func makeError(message: String) -> Error {
        let message = [debugPrintPrefix, message].joined(separator: " ")
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    
    /// This code is a patch allowing to remove old chunks that were created by older versions of Olvid. This has nothing to do with database migration.
    /// Putting this code here allows to make sure it is executed only once.
    func deleteOldOrphanedChunksFromDisk() {
        let resourceKeys: [URLResourceKey] = [.nameKey]
        let tmpDir = FileManager.default.temporaryDirectory
        guard let allFilesInTmpDir = try? FileManager.default.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: resourceKeys, options: .skipsHiddenFiles) else { return }
        let urlsOfOldChunks = allFilesInTmpDir.filter() { (url) in
            let filename = url.lastPathComponent
            let parts = filename.split(separator: "_")
            guard parts.count == 3 else { return false }
            guard parts[0].count == 64 else { return false }
            return true
        }
        guard !urlsOfOldChunks.isEmpty else { return }
        // We have old chunks to delete, we do so in the background
        DispatchQueue(label: "Queue for removing old orphaned chunks").async {
            for url in urlsOfOldChunks {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
    
    // This code was borrowed from the 2020-06-14 version of OutboxAttachment.
    static func computeChunksValues(fromAttachmentLength attachmentLength: Int, whenUsingEncryptionKey key: AuthenticatedEncryptionKey) -> (encryptedChunkTypicalLength: Int, cleartextChunkTypicalLength: Int, lastEncryptedChunkLength: Int, lastCleartextChunkLength: Int, ciphertextLength: Int, requiredNumberOfChunks: Int) {
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

}
