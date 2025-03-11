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

public final class ObvServerCreateGroupBlobServerMethod: ObvServerDataMethod {
    
    static let log = OSLog(subsystem: "io.olvid.server.interface.ObvServerCreateGroupBlobServerMethod", category: "ObvServerInterface")

    public let pathComponent = "/groupBlobCreate"

    public var ownedIdentity: ObvCryptoIdentity? { ownedCryptoId }
    private let ownedCryptoId: ObvCryptoIdentity
    public let token: Data
    public let serverURL: URL
    public let groupUID: UID
    public let newGroupAdminServerAuthenticationPublicKey: PublicKeyForAuthentication
    public let encryptedBlob: EncryptedData
    public let flowId: FlowIdentifier
    public let isActiveOwnedIdentityRequired = true

    weak public var identityDelegate: ObvIdentityDelegate? = nil

    public init(ownedIdentity: ObvCryptoIdentity, token: Data, groupIdentifier: GroupV2.Identifier, newGroupAdminServerAuthenticationPublicKey: PublicKeyForAuthentication, encryptedBlob: EncryptedData, flowId: FlowIdentifier) {
        self.ownedCryptoId = ownedIdentity
        self.token = token
        self.serverURL = groupIdentifier.serverURL
        self.groupUID = groupIdentifier.groupUID
        self.newGroupAdminServerAuthenticationPublicKey = newGroupAdminServerAuthenticationPublicKey
        self.encryptedBlob = encryptedBlob
        self.flowId = flowId
    }

    public enum PossibleReturnStatus: UInt8 {
        case ok = 0x00
        case invalidSession = 0x04
        case groupUIDAlreadyUsed = 0x12
        case generalError = 0xff
        public var debugDescription: String {
            switch self {
            case .ok:
                return "ok"
            case .invalidSession:
                return "invalidSession"
            case .groupUIDAlreadyUsed:
                return "groupUIDAlreadyUsed"
            case .generalError:
                return "generalError"
            }
        }
    }

    lazy public var dataToSend: Data? = {
        return [ownedCryptoId, token, groupUID, newGroupAdminServerAuthenticationPublicKey, encryptedBlob].obvEncode().rawData
    }()

    public static func parseObvServerResponse(responseData: Data, using log: OSLog) -> Result<PossibleReturnStatus, Error> {

        guard let (rawServerReturnedStatus, _) = genericParseObvServerResponse(responseData: responseData, using: log) else {
            os_log("Could not parse the server response", log: log, type: .error)
            let error = Self.makeError(message: "Could not parse the server response")
            return .failure(error)
        }

        guard let serverReturnedStatus = PossibleReturnStatus(rawValue: rawServerReturnedStatus) else {
            os_log("The returned server status is invalid", log: log, type: .error)
            let error = Self.makeError(message: "The returned server status is invalid")
            return .failure(error)
        }

        return .success(serverReturnedStatus)

    }

}
