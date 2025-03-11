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

public final class ObvRegisterAPIKeyServerMethod: ObvServerDataMethod {
    
    static let log = OSLog(subsystem: "io.olvid.server.interface.ObvRegisterAPIKeyServerMethod", category: "ObvServerInterface")
    
    public let pathComponent = "/registerApiKey"

    public var ownedIdentity: ObvCryptoIdentity? { ownedCryptoId }
    private let ownedCryptoId: ObvCryptoIdentity
    public let isActiveOwnedIdentityRequired = true
    public var serverURL: URL { return ownedCryptoId.serverURL }
    public let flowId: FlowIdentifier
    private let apiKey: UUID
    private let serverSessionToken: Data

    weak public var identityDelegate: ObvIdentityDelegate? = nil

    public init(ownedIdentity: ObvCryptoIdentity, serverSessionToken: Data, apiKey: UUID, identityDelegate: ObvIdentityDelegate, flowId: FlowIdentifier) {
        self.flowId = flowId
        self.ownedCryptoId = ownedIdentity
        self.identityDelegate = identityDelegate
        self.serverSessionToken = serverSessionToken
        self.apiKey = apiKey
    }
    
    public enum ServerReturnStatus: UInt8 {
        case ok = 0x00
        case invalidSession = 0x04
        case invalidAPIKey = 0x16
        case generalError = 0xff
    }
    
    lazy public var dataToSend: Data? = {
        return [self.ownedCryptoId, self.serverSessionToken, self.apiKey].obvEncode().rawData
    }()
    
    public static func parseObvServerResponse(responseData: Data, using log: OSLog) -> Result<ServerReturnStatus, Error> {
        
        guard let (rawServerReturnedStatus, _) = genericParseObvServerResponse(responseData: responseData, using: log) else {
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
        
        return .success(serverReturnedStatus)

    }

}
