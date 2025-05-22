/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import OSLog
import ObvCrypto
import OlvidUtils
import ObvMetaManager
import ObvEncoder


public final class ObvServerBackupDeleteMethod: ObvServerDataMethod {
    
    public let pathComponent = "/backupDelete"

    public let serverURL: URL
    private let backupKeyUID: UID
    private let threadUID: UID
    private let backupVersion: Int
    private let signature: Data
    public let flowId: FlowIdentifier

    weak public var identityDelegate: ObvIdentityDelegate? = nil
    public let isActiveOwnedIdentityRequired = false
    public let ownedIdentity: ObvCryptoIdentity? = nil

    
    public init(serverURL: URL, backupKeyUID: UID, threadUID: UID, backupVersion: Int, signature: Data, flowId: FlowIdentifier) {
        self.serverURL = serverURL
        self.backupKeyUID = backupKeyUID
        self.threadUID = threadUID
        self.backupVersion = backupVersion
        self.signature = signature
        self.flowId = flowId
    }
    
    
    public enum PossibleReturnStatus: UInt8 {
        case ok = 0x00
        case invalidSignature = 0x14
        case unknownBackupKeyUID = 0x1b
        case unknownThreadUID = 0x1c
        case unknownBackupVersion = 0x1d
        case parsingError = 0xfe
        case generalError = 0xff
    }


    lazy public var dataToSend: Data? = {
        dataToSendNonNil
    }()
    
    
    public var dataToSendNonNil: Data {
        let encoded = [
            backupKeyUID.obvEncode(),
            threadUID.obvEncode(),
            backupVersion.obvEncode(),
            signature.obvEncode(),
        ].obvEncode()
        return encoded.rawData
    }
    
    public static func parseObvServerResponse(responseData: Data, using log: OSLog) throws(ObvError) -> PossibleReturnStatus {
                
        guard let (rawServerReturnedStatus, _) = genericParseObvServerResponse(responseData: responseData, using: log) else {
            throw .couldNotParseServerResponse
        }

        guard let serverReturnedStatus = PossibleReturnStatus(rawValue: rawServerReturnedStatus) else {
            throw .invalidReturnedServerStatus
        }
        
        return serverReturnedStatus
                
    }
    
    
    public enum ObvError: Error {
        case couldNotParseServerResponse
        case invalidReturnedServerStatus
    }

}
