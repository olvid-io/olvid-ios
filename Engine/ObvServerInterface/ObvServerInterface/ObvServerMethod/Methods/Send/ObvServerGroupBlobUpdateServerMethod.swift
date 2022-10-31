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
import ObvEncoder

public final class ObvServerGroupBlobUpdateServerMethod: ObvServerDataMethod {
        
    static let log = OSLog(subsystem: "io.olvid.server.interface.ObvServerGroupBlobUpdateServerMethod", category: "ObvServerInterface")

    public let pathComponent = "/groupBlobUpdate"

    public let ownedIdentity: ObvCryptoIdentity
    public let serverURL: URL
    public let groupUID: UID
    public let signature: Data
    public let lockNonce: Data
    public let encodedServerAdminPublicKey: ObvEncoded
    public let encryptedBlob: EncryptedData
    public let flowId: FlowIdentifier
    weak public var identityDelegate: ObvIdentityDelegate? = nil
    public let isActiveOwnedIdentityRequired = false

    public init(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, lockNonce: Data, signature: Data, encodedServerAdminPublicKey: ObvEncoded, encryptedBlob: EncryptedData, flowId: FlowIdentifier) {
        self.ownedIdentity = ownedIdentity
        self.serverURL = groupIdentifier.serverURL
        self.groupUID = groupIdentifier.groupUID
        self.signature = signature
        self.lockNonce = lockNonce
        self.encodedServerAdminPublicKey = encodedServerAdminPublicKey
        self.encryptedBlob = encryptedBlob
        self.flowId = flowId
    }

    
    public enum PossibleReturnStatus: UInt8 {
        case ok = 0x00
        case deletedFromServer = 0x09
        case groupIsLocked = 0x13
        case invalidSignature = 0x14
        case groupNotLocked = 0x15
        case generalError = 0xff
        public var debugDescription: String {
            switch self {
            case .ok:
                return "ok"
            case .invalidSignature:
                return "invalidSignature"
            case .groupIsLocked:
                return "groupIsLocked"
            case .generalError:
                return "generalError"
            case .deletedFromServer:
                return "deletedFromServer"
            case .groupNotLocked:
                return "groupNotLocked"
            }
        }
    }

    lazy public var dataToSend: Data? = {
        return [groupUID.obvEncode(), lockNonce.obvEncode(), encryptedBlob.obvEncode(), encodedServerAdminPublicKey, signature.obvEncode()].obvEncode().rawData
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
