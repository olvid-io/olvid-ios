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

public final class ObvServerRequestChallengeMethod: ObvServerDataMethod {
    
    static let log = OSLog(subsystem: "io.olvid.server.interface.ObvServerRequestChallengeMethod", category: "ObvServerInterface")
    
    public let pathComponent = "/requestChallenge"
    
    public var serverURL: URL { return toIdentity.serverURL }
    
    public let ownedIdentity: ObvCryptoIdentity
    public let toIdentity: ObvCryptoIdentity
    private let nonce: Data
    private let apiKey: UUID
    public let flowId: FlowIdentifier
    public let isActiveOwnedIdentityRequired = false
    
    weak public var identityDelegate: ObvIdentityDelegate? = nil

    public init(ownedIdentity: ObvCryptoIdentity, apiKey: UUID, nonce: Data, toIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        self.flowId = flowId
        self.ownedIdentity = ownedIdentity
        self.toIdentity = toIdentity
        self.nonce = nonce
        self.apiKey = apiKey
    }
    
    public enum PossibleReturnStatus: UInt8 {
        case ok = 0x00
        case unkownApiKey = 0x07
        case apiKeyLicensesExhausted = 0x08
        case generalError = 0xff
    }
    
    lazy public var dataToSend: Data? = {
        return [toIdentity.getIdentity(), nonce, apiKey].obvEncode().rawData
    }()
    
    
    public static func parseObvServerResponse(responseData: Data, using log: OSLog) -> (status: PossibleReturnStatus, (challenge: Data, serverNonce: Data)?)? {
        
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
            guard listOfReturnedDatas.count == 2 else {
                os_log("The server did not return the expected number of elements", log: log, type: .error)
                return nil
            }
            guard let challenge = Data(listOfReturnedDatas[0]) else {
                os_log("We could not decode the challenge returned by the server", log: log, type: .error)
                return nil
            }
            guard let serverNonce = Data(listOfReturnedDatas[1]) else {
                os_log("We could not decode the nonce returned by the server", log: log, type: .error)
                return nil
            }
            os_log("We received a proper challenge and server nonce", log: log, type: .debug)
            return (serverReturnedStatus, (challenge, serverNonce))
            
        case .unkownApiKey:
            os_log("The server returned an Unknown API Key error", log: log, type: .error)
            return (serverReturnedStatus, nil)

        case .apiKeyLicensesExhausted:
            os_log("The server returned an API Key Licenses Exhausted error", log: log, type: .error)
            return (serverReturnedStatus, nil)
            
        case .generalError:
            os_log("The server reported a general error", log: log, type: .error)
             return (serverReturnedStatus, nil)

        }
    }

}
