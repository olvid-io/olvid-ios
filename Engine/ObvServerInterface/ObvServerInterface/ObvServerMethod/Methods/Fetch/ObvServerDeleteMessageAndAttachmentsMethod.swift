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
import ObvMetaManager
import OlvidUtils

public final class ObvServerDeleteMessageAndAttachmentsMethod: ObvServerDataMethod {
    
    static let log = OSLog(subsystem: "io.olvid.server.interface.ObvServerDeleteMessageAndAttachmentsMethod", category: "ObvServerInterface")
    
    public let pathComponent = "/deleteMessageAndAttachments"
    
    public var serverURL: URL { return messageId.ownedCryptoIdentity.serverURL }

    private let token: Data
    private let messageId: MessageIdentifier
    private let deviceUid: UID
    public let flowId: FlowIdentifier
    public let isActiveOwnedIdentityRequired = false
    
    public var ownedIdentity: ObvCryptoIdentity {
        return messageId.ownedCryptoIdentity
    }
    
    weak public var identityDelegate: ObvIdentityDelegate? = nil

    public init(token: Data, messageId: MessageIdentifier, deviceUid: UID, flowId: FlowIdentifier) {
        self.flowId = flowId
        self.token = token
        self.messageId = messageId
        self.deviceUid = deviceUid
    }
    
    public enum PossibleReturnStatus: UInt8 {
        case ok = 0x00
        case invalidSession = 0x04
        case generalError = 0xff
    }

    lazy public var dataToSend: Data? = {
        return [messageId.ownedCryptoIdentity.getIdentity(),
                token,
                messageId.uid.raw,
                deviceUid].encode().rawData
    }()

    public static func parseObvServerResponse(responseData: Data, using log: OSLog) -> PossibleReturnStatus? {
        
        guard let (rawServerReturnedStatus, _) = genericParseObvServerResponse(responseData: responseData, using: log) else {
            os_log("Could not parse the server response", log: log, type: .error)
            return nil
        }
        
        guard let serverReturnedStatus = PossibleReturnStatus(rawValue: rawServerReturnedStatus) else {
            os_log("The returned server status is invalid", log: log, type: .error)
            return nil
        }
        
        // At this point, we simply forward the return status
        return serverReturnedStatus
    }

}
