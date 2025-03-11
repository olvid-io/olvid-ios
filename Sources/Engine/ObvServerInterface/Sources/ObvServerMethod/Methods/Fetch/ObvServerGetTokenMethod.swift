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
import ObvMetaManager
import OlvidUtils

public final class ObvServerGetTokenMethod: ObvServerDataMethod {
    
    static let log = OSLog(subsystem: "io.olvid.server.interface.ObvServerGetTokenMethod", category: "ObvServerInterface")
    
    public let pathComponent = "/getToken"
    
    public var serverURL: URL { return toIdentity.serverURL }
    
    public let toIdentity: ObvCryptoIdentity
    public let ownedIdentity: ObvCryptoIdentity?
    private let response: Data
    private let nonce: Data    
    public let flowId: FlowIdentifier
    public let isActiveOwnedIdentityRequired = false

    weak public var identityDelegate: ObvIdentityDelegate? = nil

    public init(ownedIdentity: ObvCryptoIdentity, response: Data, nonce: Data, toIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        self.flowId = flowId
        self.ownedIdentity = ownedIdentity
        self.toIdentity = toIdentity
        self.response = response
        self.nonce = nonce
    }
    
    private enum ServerReturnStatus: UInt8 {
        case ok = 0x00
        case serverDidNotFindChallengeCorrespondingToResponse = 0x04
        case generalError = 0xff
    }
    
    public enum PossibleReturnStatus {
        case ok(token: Data, serverNonce: Data, apiKeyStatus: APIKeyStatus, apiPermissions: APIPermissions, apiKeyExpirationDate: Date?)
        case serverDidNotFindChallengeCorrespondingToResponse
        case generalError
        public var debugDescription: String {
            switch self {
            case .ok:
                return "ok"
            case .serverDidNotFindChallengeCorrespondingToResponse:
                return "serverDidNotFindChallengeCorrespondingToResponse"
            case .generalError:
                return "generalError"
            }
        }
    }
    
    lazy public var dataToSend: Data? = {
        return [toIdentity.getIdentity(), response, nonce].obvEncode().rawData
    }()

    public static func parseObvServerResponse(responseData: Data, using log: OSLog) -> Result<PossibleReturnStatus, Error> {
        
        guard let (rawServerReturnedStatus, listOfReturnedDatas) = genericParseObvServerResponse(responseData: responseData, using: log) else {
            assertionFailure()
            let error = ObvServerMethodError.couldNotParseServerResponse
            os_log("%{public}@", log: log, type: .error, error.localizedDescription)
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
            guard listOfReturnedDatas.count == 5 else {
                assertionFailure()
                os_log("The server did not return the expected number of elements", log: log, type: .error)
                let error = Self.makeError(message: "The server did not return the expected number of elements")
                return .failure(error)
            }
            guard let token = Data(listOfReturnedDatas[0]) else {
                assertionFailure()
                os_log("We could not decode the token returned by the server", log: log, type: .error)
                let error = Self.makeError(message: "We could not decode the token returned by the server")
                return .failure(error)
            }
            guard let serverNonce = Data(listOfReturnedDatas[1]) else {
                os_log("We could not decode the nonce returned by the server", log: log, type: .error)
                let error = Self.makeError(message: "We could not decode the nonce returned by the server")
                return .failure(error)
            }
            guard let rawApiKeyStatus = Int(listOfReturnedDatas[2]) else {
                os_log("We could not recover the raw api key status", log: log, type: .error)
                let error = Self.makeError(message: "We could not recover the raw api key status")
                return .failure(error)
            }
            guard let apiKeyStatus = APIKeyStatus(rawValue: rawApiKeyStatus) else {
                os_log("We could not cast the raw api key status", log: log, type: .error)
                let error = Self.makeError(message: "We could not cast the raw api key status")
                return .failure(error)
            }
            guard let rawApiPermissions = Int(listOfReturnedDatas[3]) else {
                os_log("We could not recover the raw api permissions", log: log, type: .error)
                let error = Self.makeError(message: "We could not recover the raw api permissions")
                return .failure(error)
            }
            let apiPermissions = APIPermissions(rawValue: rawApiPermissions)
            guard let apiKeyExpirationInMilliseconds = Int(listOfReturnedDatas[4]) else {
                os_log("We could not recover the API Key expiration", log: log, type: .error)
                let error = Self.makeError(message: "We could not recover the API Key expiration")
                return .failure(error)
            }
            let apiKeyExpiration = apiKeyExpirationInMilliseconds > 0 ? Date(timeIntervalSince1970: Double(apiKeyExpirationInMilliseconds)/1000.0) : nil
            os_log("We received a proper token, server nonce, API Key Status/Permissions/Expiration", log: log, type: .debug)
            return .success(.ok(token: token, serverNonce: serverNonce, apiKeyStatus: apiKeyStatus, apiPermissions: apiPermissions, apiKeyExpirationDate: apiKeyExpiration))
            
        case .serverDidNotFindChallengeCorrespondingToResponse:
            os_log("The server could not find the challenge corresponding to the response we just sent", log: log, type: .error)
            return .success(.serverDidNotFindChallengeCorrespondingToResponse)

        case .generalError:
            os_log("The server reported a general error", log: log, type: .error)
            return .success(.generalError)

        }
    }
    
}
