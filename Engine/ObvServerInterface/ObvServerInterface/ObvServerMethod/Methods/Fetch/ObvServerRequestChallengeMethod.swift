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
import ObvMetaManager
import OlvidUtils

public final class ObvServerRequestChallengeMethod: ObvServerDataMethod {
    
    static let log = OSLog(subsystem: "io.olvid.server.interface.ObvServerRequestChallengeMethod", category: "ObvServerInterface")
    
    public let pathComponent = "/requestChallenge"
    
    public var serverURL: URL { return toIdentity.serverURL }
    
    public let ownedIdentity: ObvCryptoIdentity
    public let toIdentity: ObvCryptoIdentity
    private let nonce: Data
    public let flowId: FlowIdentifier
    public let isActiveOwnedIdentityRequired = false
    
    weak public var identityDelegate: ObvIdentityDelegate? = nil

    public init(ownedIdentity: ObvCryptoIdentity, nonce: Data, toIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        self.flowId = flowId
        self.ownedIdentity = ownedIdentity
        self.toIdentity = toIdentity
        self.nonce = nonce
    }
    
    
    private enum ServerReturnStatus: UInt8 {
        case ok = 0x00
        case generalError = 0xff
    }
    
    
    public enum PossibleReturnStatus {
        case ok(challenge: Data, serverNonce: Data)
        case generalError
    }
    
    lazy public var dataToSend: Data? = {
        return [toIdentity.getIdentity(), nonce].obvEncode().rawData
    }()
    
    
    public static func parseObvServerResponse(responseData: Data, using log: OSLog) -> Result<PossibleReturnStatus, Error> {
        
        guard let (rawServerReturnedStatus, listOfReturnedDatas) = genericParseObvServerResponse(responseData: responseData, using: log) else {
            assertionFailure()
            os_log("Could not parse the server response", log: log, type: .error)
            let error = Self.makeError(message: "Could not parse the server response")
            return .failure(error)
        }
        
        guard let serverReturnedStatus = ServerReturnStatus(rawValue: rawServerReturnedStatus) else {
            assertionFailure()
            os_log("The returned server status is invalid", log: log, type: .error)
            let error = Self.makeError(message: "The returned server status is invalid")
            return .failure(error)
        }
        
        switch serverReturnedStatus {
            
        case .ok:
            guard listOfReturnedDatas.count == 2 else {
                assertionFailure()
                os_log("The server did not return the expected number of elements", log: log, type: .error)
                let error = Self.makeError(message: "The server did not return the expected number of elements")
                return .failure(error)
            }
            guard let challenge = Data(listOfReturnedDatas[0]) else {
                assertionFailure()
                os_log("We could not decode the challenge returned by the server", log: log, type: .error)
                let error = Self.makeError(message: "We could not decode the challenge returned by the server")
                return .failure(error)
            }
            guard let serverNonce = Data(listOfReturnedDatas[1]) else {
                os_log("We could not decode the nonce returned by the server", log: log, type: .error)
                let error = Self.makeError(message: "We could not decode the nonce returned by the server")
                return .failure(error)
            }
            os_log("We received a proper challenge and server nonce", log: log, type: .debug)
            return .success(.ok(challenge: challenge, serverNonce: serverNonce))
            
        case .generalError:
            os_log("The server reported a general error", log: log, type: .error)
            return .success(.generalError)

        }
    }

}
