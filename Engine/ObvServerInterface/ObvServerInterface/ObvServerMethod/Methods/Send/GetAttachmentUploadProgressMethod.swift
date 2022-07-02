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
import ObvTypes
import ObvEncoder
import ObvMetaManager
import OlvidUtils

public final class GetAttachmentUploadProgressMethod: ObvServerDataMethod {

    static let log = OSLog(subsystem: "io.olvid.server.interface.GetAttachmentUploadProgressMethod", category: "ObvServerInterface")

    public let pathComponent = "/getAttachmentUploadProgress"

    public var ownedIdentity: ObvCryptoIdentity { return attachmentId.messageId.ownedCryptoIdentity }

    public let attachmentId: AttachmentIdentifier
    public let isActiveOwnedIdentityRequired = true
    public let serverURL: URL
    public let flowId: FlowIdentifier

    weak public var identityDelegate: ObvIdentityDelegate? = nil

    public init(attachmentId: AttachmentIdentifier, serverURL: URL, flowId: FlowIdentifier) {
        self.attachmentId = attachmentId
        self.serverURL = serverURL
        self.flowId = flowId
    }

    public enum PossibleReturnStatus: UInt8 {
        case ok = 0x00
        case generalError = 0xff
        case deletedFromServer = 0x0d
    }

    lazy public var dataToSend: Data? = {
        return [
            attachmentId.messageId.uid,
            attachmentId.attachmentNumber,
            ].obvEncode().rawData
    }()
    
    public static func parseObvServerResponse(responseData: Data, using log: OSLog) -> (status: PossibleReturnStatus, acknowledgedChunksNumbers: [Int]?)? {
        
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
            guard let listOfEncodedChunksNumbers = [ObvEncoded](listOfReturnedDatas[0]) else {
                os_log("Decoding failed (1)", log: log, type: .error)
                return nil
            }
            let acknowledgedChunksNumbers = listOfEncodedChunksNumbers.compactMap({ Int($0) })
            guard acknowledgedChunksNumbers.count == listOfReturnedDatas.count else {
                os_log("Decoding failed (2)", log: log, type: .error)
                return nil
            }
            return (serverReturnedStatus, acknowledgedChunksNumbers)

        case .deletedFromServer:
            os_log("The server reported that the message's attachments were deleted from server", log: log, type: .error)
            return (serverReturnedStatus, nil)

        case .generalError:
                os_log("The server reported a general error", log: log, type: .error)
                return (serverReturnedStatus, nil)

        }
    }
}
