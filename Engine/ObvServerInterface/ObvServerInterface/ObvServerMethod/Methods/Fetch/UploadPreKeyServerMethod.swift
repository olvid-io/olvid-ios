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
import ObvMetaManager
import OlvidUtils


public final class UploadPreKeyServerMethod: ObvServerDataMethod {
    
    public let pathComponent = "/uploadPreKey"
    private let _ownedIdentity: ObvCryptoIdentity
    public var ownedIdentity: ObvCrypto.ObvCryptoIdentity? { _ownedIdentity }
    public var serverURL: URL { _ownedIdentity.serverURL }
    public let isActiveOwnedIdentityRequired = true
    public let flowId: FlowIdentifier
    private let currentDeviceBlobOnServerToUpload: DeviceBlobOnServer
    private let token: Data
    private var currentDeviceUID: UID { currentDeviceBlobOnServerToUpload.deviceBlob.devicePreKey.deviceUID }

    weak public var identityDelegate: ObvIdentityDelegate? = nil

    
    public init(ownedCryptoIdentity: ObvCryptoIdentity, token: Data, currentDeviceBlobOnServerToUpload: DeviceBlobOnServer, flowId: FlowIdentifier) {
        self._ownedIdentity = ownedCryptoIdentity
        self.flowId = flowId
        self.currentDeviceBlobOnServerToUpload = currentDeviceBlobOnServerToUpload
        self.token = token
    }
    

    public var dataToSend: Data? {
        return [
            _ownedIdentity.getIdentity(),
            token,
            currentDeviceUID,
            currentDeviceBlobOnServerToUpload,
        ].obvEncode().rawData
    }
    
    
    public enum PossibleReturnStatus: UInt8 {
        case ok = 0x00
        case invalidSession = 0x04
        case deviceNotRegistered = 0x0b
        case invalidSignature = 0x14
        case generalError = 0xff
    }


    public static func parseObvServerResponse(responseData: Data, using log: OSLog) -> PossibleReturnStatus? {
        
        guard let (rawServerReturnedStatus, _) = genericParseObvServerResponse(responseData: responseData, using: log) else {
            os_log("Could not parse the server response", log: log, type: .error)
            assertionFailure()
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
