/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

public final class FreeTrialServerMethod: ObvServerDataMethod {
    
    static let log = OSLog(subsystem: "io.olvid.server.interface.FreeTrialServerMethod", category: "ObvServerInterface")

    public let pathComponent = "/freeTrial"

    public var serverURL: URL { return ownedIdentity.serverURL }
    
    public let ownedIdentity: ObvCryptoIdentity
    private let token: Data
    private let retrieveAPIKey: Bool
    public let flowId: FlowIdentifier
    public let isActiveOwnedIdentityRequired = true
    
    weak public var identityDelegate: ObvIdentityDelegate? = nil
    
    public init(ownedIdentity: ObvCryptoIdentity, token: Data, retrieveAPIKey: Bool, flowId: FlowIdentifier) {
        self.flowId = flowId
        self.ownedIdentity = ownedIdentity
        self.retrieveAPIKey = retrieveAPIKey
        self.token = token
    }

    public enum PossibleReturnStatus: UInt8 {
        case ok = 0x00
        case invalidSession = 0x04
        case freeTrialAlreadyUsed = 0x0f
        case generalError = 0xff
    }

    lazy public var dataToSend: Data? = {
        return [ownedIdentity.getIdentity(), token, retrieveAPIKey].encode().rawData
    }()
    
    public static func parseObvServerResponseWhenRetrievingFreeTrialAPIKey(responseData: Data, using log: OSLog) -> (status: PossibleReturnStatus, apiKey: UUID?)? {
        
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
            guard let rawApiKey = String(listOfReturnedDatas[0]) else {
                os_log("We could not recover the raw api key", log: log, type: .error)
                return nil
            }
            guard let apiKey = UUID(uuidString: rawApiKey) else {
                os_log("We could not cast the raw api key", log: log, type: .error)
                return nil
            }
            return (serverReturnedStatus, apiKey)
            
        case .invalidSession:
            os_log("The server reported that the session is invalid", log: log, type: .error)
            return (serverReturnedStatus, nil)
            
        case .freeTrialAlreadyUsed:
            os_log("The server reported that the free trial has already been used", log: log, type: .error)
            return (serverReturnedStatus, nil)
            
        case .generalError:
            os_log("The server reported a general error", log: log, type: .error)
            return (serverReturnedStatus, nil)

        }
    }


    public static func parseObvServerResponseWhenTestingWhetherFreeTrialIsStillAvailable(responseData: Data, using log: OSLog) -> PossibleReturnStatus? {
        
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
            guard listOfReturnedDatas.count == 0 else {
                os_log("The server did not return the expected number of elements", log: log, type: .error)
                return nil
            }
            return serverReturnedStatus
            
        case .invalidSession:
            os_log("The server reported that the session is invalid", log: log, type: .error)
            return serverReturnedStatus
            
        case .freeTrialAlreadyUsed:
            os_log("The server reported that the free trial has already been used", log: log, type: .error)
            return (serverReturnedStatus)
            
        case .generalError:
            os_log("The server reported a general error", log: log, type: .error)
            return (serverReturnedStatus)

        }
    }

}
