/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvTypes
import ObvEncoder
import ObvMetaManager
import OlvidUtils

public final class RefreshInboxAttachmentSignedUrlServerMethod: ObvServerDataMethod {
    
    static let log = OSLog(subsystem: "io.olvid.server.interface.DownloadPrivateURLsForAttachmentChunksMethod", category: "ObvServerInterface")
    
    public let pathComponent = "/downloadAttachmentChunk"
    
    public var serverURL: URL { return identity.serverURL }
    
    public let identity: ObvCryptoIdentity
    public let attachmentId: ObvAttachmentIdentifier
    public let expectedChunkCount: Int
    public let flowId: FlowIdentifier
    public let isActiveOwnedIdentityRequired = true

    public var ownedIdentity: ObvCryptoIdentity? {
        return attachmentId.messageId.ownedCryptoIdentity
    }
    
    weak public var identityDelegate: ObvIdentityDelegate? = nil

    public init(identity: ObvCryptoIdentity, attachmentId: ObvAttachmentIdentifier, expectedChunkCount: Int, flowId: FlowIdentifier) {
        self.flowId = flowId
        self.identity = identity
        self.attachmentId = attachmentId
        self.expectedChunkCount = expectedChunkCount
    }
    
    public enum PossibleReturnStatus: UInt8 {
        case ok = 0x00
        case deletedFromServer = 0x09
        case generalError = 0xff
    }
    
    lazy public var dataToSend: Data? = {
        return [attachmentId.messageId.uid.raw,
                attachmentId.attachmentNumber].obvEncode().rawData
    }()
    
    public static func parseObvServerResponse(responseData: Data, using log: OSLog) -> (status: PossibleReturnStatus, chunkDownloadPrivateUrls: [URL?]?)? {
        
        guard let (rawServerReturnedStatus, listOfReturnedDatas) = genericParseObvServerResponse(responseData: responseData, using: log) else {
            os_log("Could not parse the server response", log: log, type: .error)
            return nil
        }
        
        guard let serverReturnedStatus = PossibleReturnStatus(rawValue: rawServerReturnedStatus) else {
            os_log("The returned server status is invalid", log: log, type: .error)
            return nil
        }
        
        switch serverReturnedStatus {
        case .ok:
            guard listOfReturnedDatas.count == 1 else {
                os_log("The server did not return the expected number of elements", log: log, type: .error)
                return nil
            }
            
            guard let encodedURLs = [ObvEncoded](listOfReturnedDatas[0]) else { return nil }
            let chunkDownloadPrivateUrls: [URL?] = encodedURLs.map {
                guard let urlAsString = String($0) else { return nil }
                guard !urlAsString.isEmpty else { return nil }
                return URL(string: urlAsString)
            }
            
            return (serverReturnedStatus, chunkDownloadPrivateUrls)

        case .deletedFromServer:
            os_log("The server reported that the attachment was deleted from server", log: log, type: .error)
            return (serverReturnedStatus, nil)

        case .generalError:
            os_log("The server reported a general error", log: log, type: .error)
            return (serverReturnedStatus, nil)
            
        }

        
    }
}
