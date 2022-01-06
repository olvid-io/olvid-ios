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
import ObvCrypto
import os.log
import ObvTypes
import ObvEncoder
import ObvMetaManager
import OlvidUtils

public final class ObvServerUploadReturnReceipt: ObvServerDataMethod {
    
    static let log = OSLog(subsystem: "io.olvid.server.interface.ObvServerUploadReturnReceipt", category: "ObvServerInterface")

    public let pathComponent = "/uploadReturnReceipt"

    public var serverURL: URL { return toIdentity.serverURL }
    
    public let ownedIdentity: ObvCryptoIdentity
    public let isActiveOwnedIdentityRequired = true
    let toIdentity: ObvCryptoIdentity
    let deviceUids: [UID]
    let nonce: Data
    let encryptedPayload: EncryptedData
    public let flowId: FlowIdentifier

    weak public var identityDelegate: ObvIdentityDelegate? = nil

    public init(ownedIdentity: ObvCryptoIdentity, nonce: Data, encryptedPayload: EncryptedData, toIdentity: ObvCryptoIdentity, deviceUids: [UID], flowId: FlowIdentifier) {
        self.flowId = flowId
        self.ownedIdentity = ownedIdentity
        self.nonce = nonce
        self.encryptedPayload = encryptedPayload
        self.toIdentity = toIdentity
        self.deviceUids = deviceUids
    }
    
    
    public enum PossibleReturnStatus: UInt8 {
        case ok = 0x00
        case generalError = 0xff
    }

    
    lazy public var dataToSend: Data? = {
        let encodedDeviceUids = self.deviceUids.map({ $0.encode() })
        return [toIdentity.encode(),
                encodedDeviceUids.encode(),
                nonce.encode(),
                encryptedPayload.encode()].encode().rawData
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
