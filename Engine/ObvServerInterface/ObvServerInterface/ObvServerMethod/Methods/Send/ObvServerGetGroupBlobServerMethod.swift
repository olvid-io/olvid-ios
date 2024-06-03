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
import ObvEncoder

public final class ObvServerGetGroupBlobServerMethod: ObvServerDataMethod {
        
    static let log = OSLog(subsystem: "io.olvid.server.interface.ObvServerGetGroupBlobServerMethod", category: "ObvServerInterface")

    public let pathComponent = "/groupBlobGet"

    public let ownedIdentity: ObvCryptoIdentity?
    public let serverURL: URL
    public let groupUID: UID
    public let flowId: FlowIdentifier
    weak public var identityDelegate: ObvIdentityDelegate? = nil
    public let isActiveOwnedIdentityRequired = false

    public init(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, flowId: FlowIdentifier) {
        self.ownedIdentity = ownedIdentity
        self.serverURL = groupIdentifier.serverURL
        self.groupUID = groupIdentifier.groupUID
        self.flowId = flowId
    }

    private enum ServerReturnStatus: UInt8 {
        case ok = 0x00
        case deletedFromServer = 0x09
        case groupIsLocked = 0x13
        case generalError = 0xff
    }

    public enum PossibleReturnStatus {
        case ok(encryptedBlob: EncryptedData, logItems: Set<Data>, adminPublicKey: PublicKeyForAuthentication)
        case deletedFromServer
        case groupIsLocked
        case generalError
        public var debugDescription: String {
            switch self {
            case .ok:
                return "ok"
            case .deletedFromServer:
                return "deletedFromServer"
            case .groupIsLocked:
                return "groupIsLocked"
            case .generalError:
                return "generalError"
            }
        }
    }

    lazy public var dataToSend: Data? = {
        return [groupUID].obvEncode().rawData
    }()

    public static func parseObvServerResponse(responseData: Data, using log: OSLog) -> Result<PossibleReturnStatus, Error> {

        guard let (rawServerReturnedStatus, listOfReturnedDatas) = genericParseObvServerResponse(responseData: responseData, using: log) else {
            os_log("Could not parse the server response", log: log, type: .error)
            let error = Self.makeError(message: "Could not parse the server response")
            return .failure(error)
        }

        guard let serverReturnedStatus = ServerReturnStatus(rawValue: rawServerReturnedStatus) else {
            os_log("The returned server status is invalid", log: log, type: .error)
            let error = Self.makeError(message: "The returned server status is invalid")
            return .failure(error)
        }

        switch serverReturnedStatus {
        case .deletedFromServer:
            return .success(.deletedFromServer)
        case .groupIsLocked:
            return .success(.groupIsLocked)
        case .generalError:
            return .success(.generalError)
        case .ok:
            
            guard listOfReturnedDatas.count == 3 else {
                os_log("The server did not return the expected number of elements", log: log, type: .error)
                assertionFailure()
                let error = Self.makeError(message: "The server did not return the expected number of elements")
                return .failure(error)
            }

            do {
                let encryptedBlob: EncryptedData = try listOfReturnedDatas[0].obvDecode()
                guard let listOfEncodedLogItems = [ObvEncoded](listOfReturnedDatas[1]) else { throw Self.makeError(message: "Decoding failed") }
                let logItems = Set(listOfEncodedLogItems.compactMap({ Data($0) }))
                guard let adminPublicKey = PublicKeyForAuthenticationDecoder.obvDecode(listOfReturnedDatas[2]) else { throw Self.makeError(message: "Could not devode key") }
                return .success(.ok(encryptedBlob: encryptedBlob, logItems: logItems, adminPublicKey: adminPublicKey))
            } catch {
                os_log("Decoding failed: %{public}@", log: log, type: .error, error.localizedDescription)
                assertionFailure()
                return .failure(error)
            }
            
            
        }

    }

}
