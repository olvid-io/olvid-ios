/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import OlvidUtils
import ObvCrypto
import ObvMetaManager


/// Decrypts an encrypted chunk and writes the result at the appropriate offset of the attachment file in the inbox.
final class DecryptChunkAndWriteToFileOperation: OperationWithSpecificReasonForCancel<DecryptChunkAndWriteToFileOperation.ReasonForCancel>, @unchecked Sendable {
    
    private let chunkNumber: Int
    private let encryptedChunkURL: URL
    private let cleartextAttachmentURL: URL
    private let cleartextChunkLengths: [Int]
    private let decryptionKey: AuthenticatedEncryptionKey

    init(chunkNumber: Int, encryptedChunkURL: URL, cleartextChunkLengths: [Int], cleartextAttachmentURL: URL, decryptionKey: AuthenticatedEncryptionKey) {
        self.chunkNumber = chunkNumber
        self.encryptedChunkURL = encryptedChunkURL
        self.cleartextChunkLengths = cleartextChunkLengths
        self.cleartextAttachmentURL = cleartextAttachmentURL
        self.decryptionKey = decryptionKey
        super.init()
    }
    
    override func main() {
        
        do {

            guard chunkNumber < cleartextChunkLengths.count else {
                assertionFailure()
                return cancel(withReason: .unexpectedChunkNumber)
            }

            let fh = try FileHandle(forReadingFrom: encryptedChunkURL)
            let chunk = try Chunk.decrypt(encryptedChunkAtFileHandle: fh, with: decryptionKey)
            try fh.close()
            
            guard chunk.data.count == cleartextChunkLengths[chunkNumber] else { 
                assertionFailure()
                return cancel(withReason: .unexpectedClearTextChunkLength)
            }

            let offset = cleartextChunkLengths[0..<chunkNumber].reduce(0, { $0 + $1 })

            try chunk.writeToURL(cleartextAttachmentURL, offset: offset)
            
        } catch {
            assertionFailure()
            return cancel(withReason: .error(error: error))
        }
        
    }
    
    
    public enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case unexpectedChunkNumber
        case unexpectedClearTextChunkLength
        case error(error: Error)

        public var logType: OSLogType {
            return .fault
        }

        public var errorDescription: String? {
            switch self {
            case .unexpectedChunkNumber:
                return "Unexpected chunk number"
            case .unexpectedClearTextChunkLength:
                return "Unexpected cleartext chunk length"
            case .error(error: let error):
                return "DecryptChunkAndWriteToFileOperation error: \(error.localizedDescription)"
            }
        }

    }

}
