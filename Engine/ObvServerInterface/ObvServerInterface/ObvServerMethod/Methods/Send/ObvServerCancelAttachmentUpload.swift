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

public final class ObvServerCancelAttachmentUpload: ObvServerDataMethod {
    
    static let log = OSLog(subsystem: "io.olvid.server.interface.ObvServerCancelAttachmentUpload", category: "ObvServerInterface")
    
    public let pathComponent = "/cancelAttachmentUpload"
    
    public let ownedIdentity: ObvCryptoIdentity?
    public let serverURL: URL
    public let messageUidFromServer: UID
    public let attachmentNumber: Int
    public let nonceFromServer: Data
    public let flowId: FlowIdentifier
    public let isActiveOwnedIdentityRequired = true
    
    weak public var identityDelegate: ObvIdentityDelegate? = nil

    public init(ownedIdentity: ObvCryptoIdentity, serverURL: URL, messageUidFromServer: UID, attachmentNumber: Int, nonceFromServer: Data, flowId: FlowIdentifier) {
        self.flowId = flowId
        self.ownedIdentity = ownedIdentity
        self.serverURL = serverURL
        self.messageUidFromServer = messageUidFromServer
        self.attachmentNumber = attachmentNumber
        self.nonceFromServer = nonceFromServer
    }
    
    public enum PossibleReturnStatus: UInt8 {
        case ok = 0x00
        case generalError = 0xff
    }
    
    lazy public var dataToSend: Data? = {
        return [self.messageUidFromServer,
                self.attachmentNumber,
                self.nonceFromServer].obvEncode().rawData
    }()
    
    public static func parseObvServerResponse(responseData: Data, using log: OSLog) -> PossibleReturnStatus? {
        
        guard let (rawServerReturnedStatus, _) = genericParseObvServerResponse(responseData: responseData, using: log) else {
            os_log("Could not parse the server response", log: log, type: .error)
            return nil
        }
        
        guard let serverReturnedStatus = PossibleReturnStatus(rawValue: rawServerReturnedStatus) else {
            os_log("The returned server status is invalid", log: log, type: .error)
            assertionFailure()
            return nil
        }
        
        return serverReturnedStatus

    }
    
}
