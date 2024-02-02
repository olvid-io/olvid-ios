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


public final class QueryApiKeyStatusServerMethod: ObvServerDataMethod {
    
    static let log = OSLog(subsystem: "io.olvid.server.interface.QueryApiKeyStatusServerMethod", category: "ObvServerInterface")

    public let pathComponent = "/queryApiKeyStatus"

    public var serverURL: URL { return ownedIdentity.serverURL }
    public let ownedIdentity: ObvCryptoIdentity
    public let apiKey: UUID
    public let flowId: FlowIdentifier
    public let isActiveOwnedIdentityRequired = false

    weak public var identityDelegate: ObvIdentityDelegate? = nil

    public init(ownedIdentity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier) {
        self.ownedIdentity = ownedIdentity
        self.apiKey = apiKey
        self.flowId = flowId
    }
 
    private enum ServerReturnStatus: UInt8 {
        case ok = 0x00
        case generalError = 0xff
    }
    
    public enum PossibleReturnStatus {
        case ok(apiKeyElements: APIKeyElements)
        case generalError
    }

    lazy public var dataToSend: Data? = {
        return [ownedIdentity.getIdentity(),
                apiKey].obvEncode().rawData
    }()
    
    public static func parseObvServerResponse(responseData: Data, using log: OSLog) -> Result<PossibleReturnStatus, Error> {
        
        guard let (rawServerReturnedStatus, listOfReturnedDatas) = genericParseObvServerResponse(responseData: responseData, using: log) else {
            let error = ObvServerMethodError.couldNotParseServerResponse
            os_log("%{public}@", log: log, type: .error, error.localizedDescription)
            return .failure(error)
        }
        
        guard let serverReturnedStatus = ServerReturnStatus(rawValue: rawServerReturnedStatus) else {
            let error = ObvServerMethodError.returnedServerStatusIsInvalid
            os_log("%{public}@", log: log, type: .error, error.localizedDescription)
            return .failure(error)
        }
        
        switch serverReturnedStatus {
        case .ok:
            guard listOfReturnedDatas.count == 3 else {
                let error = ObvServerMethodError.serverDidNotReturnTheExpectedNumberOfElements
                os_log("%{public}@", log: log, type: .error, error.localizedDescription)
                return .failure(error)
            }
            guard let rawApiKeyStatus = Int(listOfReturnedDatas[0]), let apiKeyStatus = APIKeyStatus(rawValue: rawApiKeyStatus) else {
                let error = ObvServerMethodError.couldNotDecodeElementReturnByServer(elementName: "rawApiKeyStatus")
                os_log("%{public}@", log: log, type: .error, error.localizedDescription)
                return .failure(error)
            }
            guard let rawApiPermissions = Int(listOfReturnedDatas[1]) else {
                let error = ObvServerMethodError.couldNotDecodeElementReturnByServer(elementName: "rawApiPermissions")
                os_log("%{public}@", log: log, type: .error, error.localizedDescription)
                return .failure(error)
            }
            let apiPermissions = APIPermissions(rawValue: rawApiPermissions)
            guard let apiKeyExpirationInMilliseconds = Int(listOfReturnedDatas[2]) else {
                let error = ObvServerMethodError.couldNotDecodeElementReturnByServer(elementName: "apiKeyExpirationInMilliseconds")
                os_log("%{public}@", log: log, type: .error, error.localizedDescription)
                return .failure(error)
            }
            let apiKeyExpiration = apiKeyExpirationInMilliseconds > 0 ? Date(timeIntervalSince1970: Double(apiKeyExpirationInMilliseconds)/1000.0) : nil
            os_log("We received a proper token, server nonce, API Key Status/Permissions/Expiration", log: log, type: .debug)
            let apiKeyElements = APIKeyElements(status: apiKeyStatus, permissions: apiPermissions, expirationDate: apiKeyExpiration)
            return .success(.ok(apiKeyElements: apiKeyElements))
            
        case .generalError:
            os_log("The server reported a general error", log: log, type: .error)
            return .success(.generalError)

        }
    }
}
