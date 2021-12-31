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
import ObvMetaManager
import ObvCrypto
import OlvidUtils


public final class ObvS3DownloadAttachmentChunkMethod: ObvS3DownloadMethod {
    
    static let log = OSLog(subsystem: "io.olvid.server.interface.ObvS3DownloadAttachmentChunkMethod", category: "ObvServerInterface")

    public var signedURL: URL
    private let attachmentId: AttachmentIdentifier
    private let chunkNumber: Int
    public let isActiveOwnedIdentityRequired = true
    public let flowId: FlowIdentifier
    public var ownedIdentity: ObvCryptoIdentity {
        return attachmentId.messageId.ownedCryptoIdentity
    }

    weak public var identityDelegate: ObvIdentityDelegate?

    public init(attachmentId: AttachmentIdentifier, chunkNumber: Int, signedURL: URL, flowId: FlowIdentifier) {
        self.flowId = flowId
        self.signedURL = signedURL
        self.attachmentId = attachmentId
        self.chunkNumber = chunkNumber
    }

}
