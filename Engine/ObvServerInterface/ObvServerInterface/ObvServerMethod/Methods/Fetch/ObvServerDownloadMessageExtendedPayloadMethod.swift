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
import ObvEncoder
import ObvMetaManager
import OlvidUtils


public final class ObvServerDownloadMessageExtendedPayloadMethod: ObvServerDataMethod {
    
    static let log = OSLog(subsystem: "io.olvid.server.interface.ObvServerDownloadMessageExtendedPayloadMethod", category: "ObvServerInterface")
    
    public let pathComponent = "/downloadMessageExtendedContent"
    
    public var serverURL: URL { ownedIdentity.serverURL }
    
    public var ownedIdentity: ObvCryptoIdentity { messageId.ownedCryptoIdentity }

    private let messageId: ObvMessageIdentifier
    private let token: Data
    public let flowId: FlowIdentifier
    public let isActiveOwnedIdentityRequired = true

    weak public var identityDelegate: ObvIdentityDelegate? = nil

    public init(messageId: ObvMessageIdentifier, token: Data, flowId: FlowIdentifier) {
        self.messageId = messageId
        self.flowId = flowId
        self.token = token
    }
    
    public enum PossibleReturnStatus: UInt8 {
        case ok = 0x00
        case invalidSession = 0x04
        case extendedContentUnavailable = 0x11
        case generalError = 0xff
    }
    
    lazy public var dataToSend: Data? = {
        return [messageId.ownedCryptoIdentity.getIdentity(), token, messageId.uid].obvEncode().rawData
    }()
    
    public static func parseObvServerResponse(responseData: Data, using log: OSLog) -> (status: PossibleReturnStatus, encryptedExtendedMessagePayload: EncryptedData?)? {
        
        guard let (rawServerReturnedStatus, listOfReturnedDatas) = genericParseObvServerResponse(responseData: responseData, using: log) else {
            os_log("Could not parse the server response", log: log, type: .error)
            assertionFailure()
            return nil
        }
        
        guard let serverReturnedStatus = PossibleReturnStatus(rawValue: rawServerReturnedStatus) else {
            os_log("The returned server status is invalid", log: log, type: .error)
            return nil
        }
        
        switch serverReturnedStatus {
            
        case .ok:
            guard listOfReturnedDatas.count == 1 else {
                os_log("We could not decode the data returned by the server: unexpected number of values", log: log, type: .error)
                return nil
            }
            let encodedEncryptedExtendedMessagePayload = listOfReturnedDatas[0]
            guard let encryptedExtendedMessagePayload = EncryptedData(encodedEncryptedExtendedMessagePayload) else {
                os_log("We could decode the encrypted extended payload returned by the server", log: log, type: .error)
                return nil
            }
            os_log("We succesfully parsed the encrypted extended payload returned by the server", log: log, type: .debug)
            return (serverReturnedStatus, encryptedExtendedMessagePayload)
            
        case .extendedContentUnavailable:
            os_log("The server reported that the requested extended message payload is unavailable", log: log, type: .error)
            return (serverReturnedStatus, nil)

        case .invalidSession:
            os_log("The server reported that the session is invalid", log: log, type: .error)
            return (serverReturnedStatus, nil)
            
        case .generalError:
            os_log("The server reported a general error", log: log, type: .error)
            return (serverReturnedStatus, nil)
            
        }
    }
    
}
