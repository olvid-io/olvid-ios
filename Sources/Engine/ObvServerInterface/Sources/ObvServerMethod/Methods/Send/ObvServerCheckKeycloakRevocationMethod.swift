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

public final class ObvServerCheckKeycloakRevocationMethod: ObvServerDataMethod {


    static let log = OSLog(subsystem: "io.olvid.server.interface.CheckKeycloakRevocationServerMethod", category: "ObvServerInterface")

    private static let _pathComponent = "olvid-rest/verify"

    public let ownedIdentity: ObvCryptoIdentity?
    public let isActiveOwnedIdentityRequired = true

    public let serverURL: URL
    public let pathComponent: String
    public let signedContactDetails: String

    public var flowId: FlowIdentifier

    weak public var identityDelegate: ObvIdentityDelegate? = nil

    /*
     * Split an url and path like "https://keycloak.olvid.io/auth/realms/olvid/olvid-rest/verify"
     * into "https://keycloak.olvid.io" and "/auth/realms/olvid/olvid-rest/verify"
     */
    public static func splitServerAndPath(from serverURL: URL) -> (serverURL: URL, path: String)? {
        let urlAndPath = serverURL.appendingPathComponent(_pathComponent).absoluteString
        let prefix = urlAndPath[urlAndPath.index(urlAndPath.startIndex, offsetBy: 8)..<urlAndPath.endIndex]
        guard let slashAfterUrl = prefix.firstIndex(of: "/") else { return nil }
        guard let url = URL(string: String(urlAndPath[urlAndPath.startIndex..<slashAfterUrl])) else { return nil }
        let path = String(urlAndPath[slashAfterUrl...])
        return (url, path)
    }

    public init(ownedIdentity: ObvCryptoIdentity, serverURL: URL, path: String, signedContactDetails: String, flowId: FlowIdentifier) {
        self.ownedIdentity = ownedIdentity
        self.serverURL = serverURL
        self.pathComponent = path
        self.signedContactDetails = signedContactDetails
        self.flowId = flowId
    }

    private struct CheckKeycloakRevocationJSON: Encodable {
        let signature: String
    }

    lazy public var dataToSend: Data? = {
        let checkKeycloakRevocationJSON = CheckKeycloakRevocationJSON(signature: signedContactDetails)
        let encoder = JSONEncoder()
        return try? encoder.encode(checkKeycloakRevocationJSON)
    }()

    private enum PossibleReturnRawStatus: UInt8 {
        case ok = 0x00
        case generalError = 0xff
    }

    public enum PossibleReturnStatus {
        case ok(verificationSuccessful: Bool)
        case generalError
    }

    public static func parseObvServerResponse(responseData: Data, using log: OSLog) -> PossibleReturnStatus? {

        guard let (rawServerReturnedStatus, listOfReturnedDatas) = genericParseObvServerResponse(responseData: responseData, using: log) else {
            os_log("Could not parse the server response", log: log, type: .error)
            return nil
        }

        guard let serverReturnedStatus = PossibleReturnRawStatus(rawValue: rawServerReturnedStatus) else {
            os_log("The returned server status is invalid", log: log, type: .error)
            return nil
        }

        switch serverReturnedStatus {
        case .ok:
            guard listOfReturnedDatas.count == 1 else {
                os_log("The server did not return the expected number of elements", log: log, type: .error)
                return nil
            }
            guard let verificationSuccessful = Bool(listOfReturnedDatas[0]) else {
                os_log("We could not decode the data returned by the server", log: log, type: .error)
                return nil
            }
            return .ok(verificationSuccessful: verificationSuccessful)
        case .generalError:
            os_log("The server reported a general error", log: log, type: .error)
            return .generalError
        }
    }

}
