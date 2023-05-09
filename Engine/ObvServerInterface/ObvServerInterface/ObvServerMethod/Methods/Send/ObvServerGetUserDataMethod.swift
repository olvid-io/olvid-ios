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

public final class ObvServerGetUserDataMethod: ObvServerDataMethod {

    static let log = OSLog(subsystem: "io.olvid.server.interface.ObvServerPutUserDataMethod", category: "ObvServerInterface")

    public let pathComponent = "/getUserData"

    public var ownedIdentity: ObvCryptoIdentity
    public var isActiveOwnedIdentityRequired = true
    public var serverURL: URL { toIdentity.serverURL }
    public let toIdentity: ObvCryptoIdentity
    public let serverLabel: UID
    public let flowId: FlowIdentifier

    weak public var identityDelegate: ObvIdentityDelegate? = nil

    public init(ownedIdentity: ObvCryptoIdentity, toIdentity: ObvCryptoIdentity, serverLabel: UID, flowId: FlowIdentifier) {
        self.ownedIdentity = ownedIdentity
        self.toIdentity = toIdentity
        self.serverLabel = serverLabel
        self.flowId = flowId
    }

    lazy public var dataToSend: Data? = {
        return [self.toIdentity, self.serverLabel].obvEncode().rawData
    }()

    public enum PossibleReturnStatus: UInt8 {
        case ok = 0x00
        case deletedFromServer = 0x09
        case generalError = 0xff
    }

    public static func parseObvServerResponse(responseData: Data, using log: OSLog, downloadedUserData: URL, serverLabel: UID) -> (status: PossibleReturnStatus, userDataPath: String?)? {

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
            guard listOfReturnedDatas.count == 1 else {
                os_log("The server did not return the expected number of elements", log: log, type: .error)
                return nil
            }
            guard let data = Data(listOfReturnedDatas[0]) else {
                os_log("We could not decode the user data returned by the server", log: log, type: .error)
                return nil
            }
            let encryptedData = EncryptedData(data: data)
            // Ugly hack: the filename contains a timestamp after which the file is considered "orphan" and can be deleted
            let expiration = Int(Date().addingTimeInterval(ObvConstants.getUserDataLocalFileLifespan).timeIntervalSince1970)
            // Remark: This file name is parsed in ServerUserDataCoordinator#initialQueueing
            // 2023-01-10: we added a random UUID at the end of the filename to make sure that when two owned identity dowload the same user data at the same time
            // (e.g., the same group photo), each downloaded data has its own URL (otherwise, deleting one actually deletes the other, which is unexpected).
            let filename = String(expiration) + "." + serverLabel.hexString() + "-" + UUID().uuidString
            let userDataPath = downloadedUserData.appendingPathComponent(filename)

            do {
                try encryptedData.raw.write(to: userDataPath)
            } catch {
                return (.generalError, nil)
            }

            return (serverReturnedStatus, filename)
        case .deletedFromServer:
            return (serverReturnedStatus, "")

        case .generalError:
            os_log("The server reported a general error", log: log, type: .error)
            return (serverReturnedStatus, nil)
        }
    }
}
