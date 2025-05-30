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

public final class GetKeycloakDataServerMethod: ObvServerDataMethod {
    
    static let log = OSLog(subsystem: "io.olvid.server.interface.GetKeycloakDataServerMethod", category: "ObvServerInterface")
    
    public let pathComponent = "olvid-rest/getData" // No slash at the beginning of this string
    
    public let ownedIdentity: ObvCryptoIdentity?
    public let isActiveOwnedIdentityRequired = false
    public let serverURL: URL
    public let serverLabel: UID
    public let flowId: FlowIdentifier
    
    weak public var identityDelegate: ObvIdentityDelegate? = nil
    
    public init(ownedIdentity: ObvCryptoIdentity, serverURL: URL, serverLabel: UID, flowId: FlowIdentifier) {
        self.flowId = flowId
        self.ownedIdentity = ownedIdentity
        self.serverURL = serverURL
        self.serverLabel = serverLabel
    }
    
    private enum PossibleReturnRawStatus: UInt8 {
        case ok = 0x00
        case deletedFromServer = 0x09
        case generalError = 0xff
    }

    public enum PossibleReturnStatus {
        case ok(userDataFilename: String)
        case deletedFromServer
        case generalError
    }

    lazy public var dataToSend: Data? = {
        return serverLabel.raw
    }()
    
    public static func parseObvServerResponse(responseData: Data, using log: OSLog, downloadedUserData: URL, serverLabel: UID) -> PossibleReturnStatus? {
        
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
                assertionFailure()
                return nil
            }
            
            return .ok(userDataFilename: filename)

        case .deletedFromServer:
            return .deletedFromServer
            
        case .generalError:
            os_log("The server reported a general error", log: log, type: .error)
            return .generalError
        }
    }
}
