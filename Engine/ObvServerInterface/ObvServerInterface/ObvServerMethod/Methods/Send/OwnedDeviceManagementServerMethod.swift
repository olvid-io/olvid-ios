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

public final class OwnedDeviceManagementServerMethod: ObvServerDataMethod {
    
    static let log = OSLog(subsystem: "io.olvid.server.interface.OwnedDeviceManagementServerMethod", category: "ObvServerInterface")
    
    public let pathComponent = "/deviceManagement"

    public var ownedIdentity: ObvCryptoIdentity? { ownedCryptoId }
    private let ownedCryptoId: ObvCryptoIdentity
    public let isActiveOwnedIdentityRequired = true
    public var serverURL: URL { return ownedCryptoId.serverURL }
    public let flowId: FlowIdentifier
    let queryType: QueryType
    let token: Data
    
    public enum QueryType {
        case setOwnedDeviceName(ownedDeviceUID: UID, encryptedOwnedDeviceName: EncryptedData)
        case deactivateOwnedDevice(ownedDeviceUID: UID)
        case setUnexpiringOwnedDevice(ownedDeviceUID: UID)
        
        fileprivate var byteIdentifier: UInt8 {
            switch self {
            case .setOwnedDeviceName:
                return 0x00
            case .deactivateOwnedDevice:
                return 0x01
            case .setUnexpiringOwnedDevice:
                return 0x02
            }
        }
    }

    weak public var identityDelegate: ObvIdentityDelegate? = nil

    public init(ownedIdentity: ObvCryptoIdentity, token: Data, queryType: QueryType, flowId: FlowIdentifier) {
        self.flowId = flowId
        self.ownedCryptoId = ownedIdentity
        self.queryType = queryType
        self.token = token
    }
    
    public enum PossibleReturnStatus: UInt8 {
        case ok = 0x00
        case invalidSession = 0x04
        case deviceNotRegistered = 0x0b
        case generalError = 0xff
        public var debugDescription: String {
            switch self {
            case .ok:
                return "ok"
            case .invalidSession:
                return "invalidSession"
            case .deviceNotRegistered:
                return "deviceNotRegistered"
            case .generalError:
                return "generalError"
            }
        }
    }
    
    lazy public var dataToSend: Data? = {
        switch queryType {
        case .setOwnedDeviceName(let ownedDeviceUID, let encryptedDeviceName):
            return [self.ownedCryptoId, token, queryType.byteIdentifier, ownedDeviceUID, encryptedDeviceName.raw].obvEncode().rawData
        case .deactivateOwnedDevice(ownedDeviceUID: let ownedDeviceUID):
            return [self.ownedCryptoId, token, queryType.byteIdentifier, ownedDeviceUID].obvEncode().rawData
        case .setUnexpiringOwnedDevice(ownedDeviceUID: let ownedDeviceUID):
            return [self.ownedCryptoId, token, queryType.byteIdentifier, ownedDeviceUID].obvEncode().rawData
        }
    }()
    
    
    public static func parseObvServerResponse(responseData: Data, using log: OSLog) -> Result<PossibleReturnStatus, Error> {
        
        guard let (rawServerReturnedStatus, _) = genericParseObvServerResponse(responseData: responseData, using: log) else {
            assertionFailure()
            os_log("Could not parse the server response", log: log, type: .error)
            let error = Self.makeError(message: "Could not parse the server response")
            return .failure(error)
        }
        
        guard let serverReturnedStatus = PossibleReturnStatus(rawValue: rawServerReturnedStatus) else {
            assertionFailure()
            os_log("The returned server status is invalid", log: log, type: .error)
            let error = Self.makeError(message: "The returned server status is invalid")
            return .failure(error)
        }
        
        return .success(serverReturnedStatus)
                
    }

}
