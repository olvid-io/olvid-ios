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
import ObvCrypto
import os.log
import ObvTypes
import ObvEncoder
import ObvMetaManager
import OlvidUtils

public final class ObvServerUploadReturnReceipt: ObvServerDataMethod {
    
    static let log = OSLog(subsystem: "io.olvid.server.interface.ObvServerUploadReturnReceipt", category: "ObvServerInterface")

    public let pathComponent = "/uploadReturnReceipt"

    public let serverURL: URL
    private let returnReceipts: [ReturnReceipt]
    public let flowId: FlowIdentifier
    
    public let isActiveOwnedIdentityRequired = false
    public let ownedIdentity: ObvCryptoIdentity? = nil
    weak public var identityDelegate: ObvIdentityDelegate? = nil
    
    
    public struct ReturnReceipt: ObvEncodable {
                
        let toIdentity: ObvCryptoIdentity
        let deviceUids: [UID]
        let nonce: Data
        let encryptedPayload: EncryptedData
        
        public init(toIdentity: ObvCryptoIdentity, deviceUids: [UID], nonce: Data, encryptedPayload: EncryptedData) {
            self.toIdentity = toIdentity
            self.deviceUids = deviceUids
            self.nonce = nonce
            self.encryptedPayload = encryptedPayload
        }
        
        public func obvEncode() -> ObvEncoded {
            [
                toIdentity.obvEncode(),
                deviceUids.map({ $0.obvEncode() }).obvEncode(),
                nonce.obvEncode(),
                encryptedPayload.obvEncode()
            ].obvEncode()
        }

    }

    
    public init(serverURL: URL, returnReceipts: [ReturnReceipt], flowId: FlowIdentifier) {
        self.serverURL = serverURL
        self.returnReceipts = returnReceipts
        self.flowId = flowId
    }
    
    
    public enum PossibleReturnStatus: UInt8 {
        case ok = 0x00
        case generalError = 0xff
    }

    
    lazy public var dataToSend: Data? = {
        returnReceipts.map({ $0.obvEncode() }).obvEncode().rawData
    }()
    
    
    public static func parseObvServerResponse(responseData: Data, using log: OSLog) -> PossibleReturnStatus? {
        
        guard let (rawServerReturnedStatus, _) = genericParseObvServerResponse(responseData: responseData, using: log) else {
            os_log("Could not parse the server response", log: log, type: .error)
            return nil
        }
        
        guard let serverReturnedStatus = PossibleReturnStatus(rawValue: rawServerReturnedStatus) else {
            os_log("The returned server status is invalid", log: log, type: .error)
            assert(false)
            return nil
        }
        
        return serverReturnedStatus

    }

}
