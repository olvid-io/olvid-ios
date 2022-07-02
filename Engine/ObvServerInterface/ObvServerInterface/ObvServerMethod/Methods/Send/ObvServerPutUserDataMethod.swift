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

public final class ObvServerPutUserDataMethod: ObvServerDataMethod {

    static let log = OSLog(subsystem: "io.olvid.server.interface.ObvServerPutUserDataMethod", category: "ObvServerInterface")

    public let pathComponent = "/putUserData"

    public let ownedIdentity: ObvCryptoIdentity
    public let isActiveOwnedIdentityRequired = true
    public var serverURL: URL { ownedIdentity.serverURL }
    public let token: Data
    public let serverLabel: String
    public let data: EncryptedData
    public let flowId: FlowIdentifier

    weak public var identityDelegate: ObvIdentityDelegate? = nil

    public init(ownedIdentity: ObvCryptoIdentity, token: Data, serverLabel: String, data: EncryptedData, flowId: FlowIdentifier) {
        self.ownedIdentity = ownedIdentity
        self.token = token
        self.serverLabel = serverLabel
        self.data = data
        self.flowId = flowId
    }

    public enum PossibleReturnStatus: UInt8 {
        case ok = 0x00
        case generalError = 0xff
    }

    lazy public var dataToSend: Data? = {
        // The given serverLabel is a base64 of the binary label (created in StartPhotoUploadStep), but the server expects a binary, so we decode the base64 here.
        guard let binaryServerLabel = Data(base64Encoded: self.serverLabel) else { return nil }
        return [self.ownedIdentity, self.token, binaryServerLabel, self.data].obvEncode().rawData
    }()

    public static func parseObvServerResponse(responseData: Data, using log: OSLog) -> PossibleReturnStatus? {

        guard let (rawServerReturnedStatus, _) = genericParseObvServerResponse(responseData: responseData, using: log) else {
            os_log("Could not parse the server response", log: log, type: .error)
            return nil
        }

        guard let serverReturnedStatus = PossibleReturnStatus(rawValue: rawServerReturnedStatus) else {
            os_log("The returned server status is invalid", log: log, type: .error)
            return nil
        }

        return serverReturnedStatus
    }



}
    
