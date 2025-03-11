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
import ObvEncoder
import OlvidUtils

public final class GetTurnCredentialsServerMethod: ObvServerDataMethod {
    
    static let log = OSLog(subsystem: "io.olvid.server.interface.GetTurnCredentialsServerMethod", category: "ObvServerInterface")

    public let pathComponent = "/getTurnCredentials"

    public let ownedIdentity: ObvCryptoIdentity?
    private let ownedIdentityIdentity: Data
    private let token: Data
    private let username1: String
    private let username2: String
    public let isActiveOwnedIdentityRequired = true
    public let flowId: FlowIdentifier

    public let serverURL: URL

    weak public var identityDelegate: ObvIdentityDelegate? = nil

    public init(ownedIdentity: ObvCryptoIdentity, token: Data, username1: String, username2: String, flowId: FlowIdentifier, identityDelegate: ObvIdentityDelegate) {
        self.ownedIdentity = ownedIdentity
        self.token = token
        self.username1 = username1
        self.username2 = username2
        self.identityDelegate = identityDelegate
        self.flowId = flowId
        self.serverURL = ownedIdentity.serverURL
        self.ownedIdentityIdentity = ownedIdentity.getIdentity()
    }
    
    public enum PossibleReturnStatus: UInt8 {
        case ok = 0x00
        case invalidSession = 0x04
        case permissionDenied = 0x0e
        case generalError = 0xff
    }

    lazy public var dataToSend: Data? = {
        return [ownedIdentityIdentity, token, username1, username2].obvEncode().rawData
    }()

    public static func parseObvServerResponse(responseData: Data, using log: OSLog) -> (status: PossibleReturnStatus, output: TurnCredentials?)? {

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
            
            guard listOfReturnedDatas.count == 4 else {
                os_log("The server did not return the expected number of elements", log: log, type: .error)
                return nil
            }
            
            guard let turnCredentials = TurnCredentials(listOfReturnedDatas: listOfReturnedDatas) else {
                os_log("We could not parse the server answer", log: log, type: .error)
                return nil
            }

            return (serverReturnedStatus, turnCredentials)
            
        case .invalidSession:
            os_log("The server reported that the session is invalid", log: log, type: .error)
            return (serverReturnedStatus, nil)
            
        case .permissionDenied:
            os_log("The server denied access to Turn Credentials", log: log, type: .error)
            return (serverReturnedStatus, nil)

        case .generalError:
            os_log("The server reported a general error", log: log, type: .error)
            return (serverReturnedStatus, nil)
            
        }
        
    }

}


fileprivate extension TurnCredentials {
    
    init?(listOfReturnedDatas: [ObvEncoded]) {
        guard listOfReturnedDatas.count == 4 else { return nil }
        guard let expiringUsername1: String = try? listOfReturnedDatas[0].obvDecode() else { return nil }
        guard let password1: String = try? listOfReturnedDatas[1].obvDecode() else { return nil }
        guard let expiringUsername2: String = try? listOfReturnedDatas[2].obvDecode() else { return nil }
        guard let password2: String = try? listOfReturnedDatas[3].obvDecode() else { return nil }
        self.init(expiringUsername1: expiringUsername1, password1: password1, expiringUsername2: expiringUsername2, password2: password2)
    }
    
}
