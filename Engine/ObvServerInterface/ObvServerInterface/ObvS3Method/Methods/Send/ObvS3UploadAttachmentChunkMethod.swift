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
import ObvCrypto
import ObvEncoder
import ObvTypes
import OlvidUtils
import ObvMetaManager

public final class ObvS3UploadAttachmentChunkMethod: ObvS3UploadMethod {
        
    static let log = OSLog(subsystem: "io.olvid.server.interface.ObvS3UploadAttachmentChunkMethod", category: "ObvServerInterface")
    
    public let signedURL: URL
    public let fileURL: URL
    public let countOfBytesClientExpectsToSend: Int
    public let countOfBytesClientExpectsToReceive = 100
    private let typicalHeaderCountOfBytes = 500
    public let isActiveOwnedIdentityRequired = true
    public let attachmentId: AttachmentIdentifier
    public let flowId: FlowIdentifier
    public var ownedIdentity: ObvCryptoIdentity {
        return attachmentId.messageId.ownedCryptoIdentity
    }

    weak public var identityDelegate: ObvIdentityDelegate?

    public init(attachmentId: AttachmentIdentifier, fileURL: URL, fileSize: Int, chunkNumber: Int, signedURL: URL, flowId: FlowIdentifier) {
        self.flowId = flowId
        self.attachmentId = attachmentId
        self.signedURL = signedURL
        self.countOfBytesClientExpectsToSend = fileSize + typicalHeaderCountOfBytes
        self.fileURL = fileURL
    }

}
