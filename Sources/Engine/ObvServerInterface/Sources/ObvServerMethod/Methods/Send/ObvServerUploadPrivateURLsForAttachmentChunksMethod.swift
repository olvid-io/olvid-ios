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

public final class ObvServerUploadPrivateURLsForAttachmentChunksMethod: ObvServerDataMethod {
    
    static let log = OSLog(subsystem: "io.olvid.server.interface.ObvServerUploadPrivateURLsForAttachmentChunksMethod", category: "ObvServerInterface")
    private static func makeError(message: String) -> Error {
        NSError(domain: "ObvServerUploadPrivateURLsForAttachmentChunksMethod", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message])
    }

    public let pathComponent = "/uploadAttachment"
    public let ownedIdentity: ObvCryptoIdentity?
    public let serverURL: URL
    public let messageUidFromServer: UID
    public let attachmentNumber: Int
    public let nonceFromServer: Data
    public let expectedChunkCount: Int    
    public let flowId: FlowIdentifier
    public let isActiveOwnedIdentityRequired = true

    weak public var identityDelegate: ObvIdentityDelegate? = nil

    public init(ownedIdentity: ObvCryptoIdentity, serverURL: URL, messageUidFromServer: UID, attachmentNumber: Int, nonceFromServer: Data, expectedChunkCount: Int, flowId: FlowIdentifier) {
        self.flowId = flowId
        self.ownedIdentity = ownedIdentity
        self.serverURL = serverURL
        self.messageUidFromServer = messageUidFromServer
        self.attachmentNumber = attachmentNumber
        self.nonceFromServer = nonceFromServer
        self.expectedChunkCount = expectedChunkCount
    }
    
    public enum PossibleReturnStatus: UInt8 {
        case ok = 0x00
        case deletedFromServer = 0x09
        case generalError = 0xff
    }
    
    lazy public var dataToSend: Data? = {
        return [self.messageUidFromServer,
                self.attachmentNumber,
                self.nonceFromServer].obvEncode().rawData
    }()
    
    public static func parseObvServerResponse(responseData: Data, using log: OSLog) -> (status: PossibleReturnStatus, chunkUploadPrivateUrls: [URL]?)? {
        
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
            let chunkUploadPrivateUrls: [URL]
            do {
                chunkUploadPrivateUrls = try encodedURLs.compactMap {
                    guard let urlAsString = String($0) else {
                        assertionFailure()
                        throw Self.makeError(message: "Could not turn encoded URL into a string")
                    }
                    guard !urlAsString.isEmpty else {
                        assertionFailure()
                        throw Self.makeError(message: "The string obtained from the URL is empty")
                    }
                    return URL(string: urlAsString)
                }
            } catch {
                return nil
            }
            
            return (serverReturnedStatus, chunkUploadPrivateUrls)
            
        case .deletedFromServer:
            os_log("The server reported that the attachment was deleted from server", log: log, type: .error)
            return (serverReturnedStatus, nil)
            
        case .generalError:
            os_log("The server reported a general error", log: log, type: .error)
            return (serverReturnedStatus, nil)
            
        }
        
        
    }
}
