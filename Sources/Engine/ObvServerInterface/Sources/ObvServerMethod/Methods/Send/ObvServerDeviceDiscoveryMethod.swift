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

public final class ObvServerDeviceDiscoveryMethod: ObvServerDataMethod {
    
    static let log = OSLog(subsystem: "io.olvid.server.interface.ObvServerDeviceDiscoveryMethod", category: "ObvServerInterface")
    
    public let pathComponent = "/deviceDiscovery"

    public let ownedIdentity: ObvCryptoIdentity?
    public let isActiveOwnedIdentityRequired = true
    public var serverURL: URL { return toIdentity.serverURL }
    public let toIdentity: ObvCryptoIdentity // We will discover the devices of this identity
    public let flowId: FlowIdentifier

    weak public var identityDelegate: ObvIdentityDelegate? = nil

    public init(ownedIdentity: ObvCryptoIdentity, toIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        self.flowId = flowId
        self.ownedIdentity = ownedIdentity
        self.toIdentity = toIdentity
    }
    
    public enum PossibleReturnRawStatus: UInt8 {
        case ok = 0x00
        case generalError = 0xff
    }

    public enum PossibleReturnStatus {
        case ok(result: ContactDeviceDiscoveryResult)
        case generalError
    }

    lazy public var dataToSend: Data? = {
        return [self.toIdentity].obvEncode().rawData
    }()
    
    public static func parseObvServerResponse(responseData: Data, using log: OSLog) -> PossibleReturnStatus? {
        
        guard let (rawServerReturnedStatus, listOfReturnedDatas) = genericParseObvServerResponse(responseData: responseData, using: log) else {
            os_log("Could not parse the server response", log: log, type: .error)
            return nil
        }
        
        guard let serverReturnedStatus = PossibleReturnRawStatus(rawValue: rawServerReturnedStatus) else {
            os_log("The returned server status is invalid", log: log, type: .error)
            return nil
        }
        
        switch serverReturnedStatus {
            
        case .ok:
            
            guard listOfReturnedDatas.count == 1 else {
                os_log("The server did not return the expected number of elements", log: log, type: .error)
                return nil
            }
            guard let result = ContactDeviceDiscoveryResult(listOfReturnedDatas[0]) else {
                assertionFailure()
                os_log("We could not decode the contact device discovery result returned by the server", log: log, type: .error)
                return nil
            }
            os_log("We received a list of %d device uids from the server", log: log, type: .debug, result.devices.count)
            return .ok(result: result)
            
        case .generalError:
            os_log("The server reported a general error", log: log, type: .error)
            return .generalError
            
        }
        
    }

}
