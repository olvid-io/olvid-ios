/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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

public final class ObvServerOwnedDeviceDiscoveryMethod: ObvServerDataMethod {
    
    static let log = OSLog(subsystem: "io.olvid.server.interface.ObvServerOwnedDeviceDiscoveryMethod", category: "ObvServerInterface")
    
    public let pathComponent = "/ownedDeviceDiscovery"

    public let ownedIdentity: ObvCryptoIdentity
    public let isActiveOwnedIdentityRequired = false
    public var serverURL: URL { return ownedIdentity.serverURL }
    public let flowId: FlowIdentifier

    weak public var identityDelegate: ObvIdentityDelegate? = nil

    public init(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        self.flowId = flowId
        self.ownedIdentity = ownedIdentity
    }
    
    private enum ServerReturnStatus: UInt8 {
        case ok = 0x00
        case generalError = 0xff
    }
    
    public enum PossibleReturnStatus {
        case ok(encryptedOwnedDeviceDiscoveryResult: EncryptedData)
        case generalError
    }
    
    lazy public var dataToSend: Data? = {
        return [self.ownedIdentity].obvEncode().rawData
    }()
    
    public static func parseObvServerResponse(responseData: Data, using log: OSLog) -> Result<PossibleReturnStatus, Error> {
        
        guard let (rawServerReturnedStatus, listOfReturnedDatas) = genericParseObvServerResponse(responseData: responseData, using: log) else {
            os_log("Could not parse the server response", log: log, type: .error)
            let error = Self.makeError(message: "Could not parse the server response")
            assertionFailure()
            return .failure(error)
        }
        
        guard let serverReturnedStatus = ServerReturnStatus(rawValue: rawServerReturnedStatus) else {
            os_log("The returned server status is invalid", log: log, type: .error)
            let error = Self.makeError(message: "The returned server status is invalid")
            assertionFailure()
            return .failure(error)
        }
        
        switch serverReturnedStatus {
            
        case .ok:
            
            guard listOfReturnedDatas.count == 1 else {
                os_log("The server did not return the expected number of elements", log: log, type: .error)
                let error = Self.makeError(message: "The server did not return the expected number of elements")
                assertionFailure()
                return .failure(error)
            }
            let encodedEncryptedOwnedDeviceDiscoveryResult = listOfReturnedDatas[0]
            guard let encryptedOwnedDeviceDiscoveryResult = EncryptedData(encodedEncryptedOwnedDeviceDiscoveryResult) else {
                os_log("We could not recover the encrypted owned device discovery result", log: log, type: .error)
                let error = Self.makeError(message: "We could not recover the encrypted owned device discovery result")
                assertionFailure()
                return .failure(error)
            }
            os_log("We received the encrypted result of the device discovery", log: log, type: .debug)
            return .success(.ok(encryptedOwnedDeviceDiscoveryResult: encryptedOwnedDeviceDiscoveryResult))
            
        case .generalError:
            os_log("The server reported a general error", log: log, type: .error)
            return .success(.generalError)
            
        }
        
    }

}
