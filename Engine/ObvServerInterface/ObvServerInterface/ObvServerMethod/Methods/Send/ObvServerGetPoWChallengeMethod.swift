/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

public final class ObvServerGetPoWChallengeMethod: ObvServerDownloadMethod {
    
    static let log = OSLog(subsystem: "io.olvid.server.interface.ObvServerGetPoWChallengeMethod", category: "ObvServerInterface")
    
    public let pathComponent = "/getPoWChallenge"

    public let ownedIdentity: ObvCryptoIdentity
    public let isActiveOwnedIdentityRequired = true
    public let serverURL: URL
    public let flowId: FlowIdentifier

    weak public var identityDelegate: ObvIdentityDelegate? = nil

    public init(ownedIdentity: ObvCryptoIdentity, serverURL: URL, flowId: FlowIdentifier) {
        self.flowId = flowId
        self.ownedIdentity = ownedIdentity
        self.serverURL = serverURL
    }

    public enum PossibleReturnStatus: UInt8 {
        case ok = 0x00
        case generalError = 0xff
    }

    public let dataToSend: Data? = nil

    public static func parseObvServerResponse(responseData: Data, using log: OSLog) -> (status: PossibleReturnStatus, (proofOfWorkUid: UID, proofOfWorkEncodedChallenge: ObvEncoded)?)? {

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
            
            guard listOfReturnedDatas.count == 2 else {
                os_log("The server did not return the expected number of elements", log: log, type: .error)
                return nil
            }
            let proofOfWorkEncodedUid = listOfReturnedDatas[0]
            let proofOfWorkEncodedChallenge = listOfReturnedDatas[1]
            guard let proofOfWorkUid = UID(proofOfWorkEncodedUid) else {
                os_log("We could decode the proof of work UID returned by the server", log: log, type: .error)
                return nil
            }
            os_log("The message received a new proof of work from the server", log: log, type: .debug)
            return (serverReturnedStatus, (proofOfWorkUid, proofOfWorkEncodedChallenge))

        case .generalError:
            os_log("The server reported a general error", log: log, type: .error)
            return (serverReturnedStatus, nil)

        }
        
    }

}
