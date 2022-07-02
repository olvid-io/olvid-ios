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

public final class ObvServerRegisterRemotePushNotificationMethod: ObvServerDataMethod {
    
    static let log = OSLog(subsystem: "io.olvid.server.interface.ObvServerRegisterRemotePushNotificationMethod", category: "ObvServerInterface")
    
    public let pathComponent = "/registerPushNotification"

    public var serverURL: URL { return toIdentity.serverURL }

    public let toIdentity: ObvCryptoIdentity

    public let ownedIdentity: ObvCryptoIdentity
    private let token: Data
    private let deviceUid: UID
    private let remoteNotificationByteIdentifierForServer: Data // One byte
    private let deviceTokensAndmaskingUID: (pushToken: Data, voipToken: Data?, maskingUID: UID)?
    private let parameters: ObvPushNotificationParameters    
    public let isActiveOwnedIdentityRequired = false
    public let flowId: FlowIdentifier
    private let keycloakPushTopics: [Data]

    weak public var identityDelegate: ObvIdentityDelegate? = nil

    public init(ownedIdentity: ObvCryptoIdentity, token: Data, deviceUid: UID, remoteNotificationByteIdentifierForServer: Data, toIdentity: ObvCryptoIdentity, deviceTokensAndmaskingUID: (pushToken: Data, voipToken: Data?, maskingUID: UID)?, parameters: ObvPushNotificationParameters, keycloakPushTopics: Set<String>, flowId: FlowIdentifier) {
        self.flowId = flowId
        self.ownedIdentity = ownedIdentity
        self.toIdentity = toIdentity
        self.token = token
        self.deviceUid = deviceUid
        self.remoteNotificationByteIdentifierForServer = remoteNotificationByteIdentifierForServer
        self.deviceTokensAndmaskingUID = deviceTokensAndmaskingUID
        self.parameters = parameters
        self.keycloakPushTopics = keycloakPushTopics.compactMap({ $0.data(using: .utf8) })
    }
    
    public enum PossibleReturnStatus: UInt8 {
        case ok = 0x00
        case invalidSession = 0x04
        case anotherDeviceIsAlreadyRegistered = 0x0a
        case generalError = 0xff
    }
    
    lazy public var dataToSend: Data? = {
        let listOfEncodedKeycloakPushTopics = keycloakPushTopics.map({ $0.obvEncode() })
        let encodedList: ObvEncoded
        encodedList = [toIdentity.getIdentity().obvEncode(),
                       token.obvEncode(),
                       deviceUid.obvEncode(),
                       remoteNotificationByteIdentifierForServer.obvEncode(),
                       extraInfo,
                       parameters.kickOtherDevices.obvEncode(),
                       parameters.useMultiDevice.obvEncode(),
                       listOfEncodedKeycloakPushTopics.obvEncode()].obvEncode()
        return encodedList.rawData
    }()

    lazy private var extraInfo: ObvEncoded = {
        if let (pushToken, voipToken, maskingUID) = self.deviceTokensAndmaskingUID {
            if let _voipToken = voipToken {
                return [pushToken.obvEncode(), maskingUID.obvEncode(), _voipToken.obvEncode()].obvEncode()
            } else {
                return [pushToken.obvEncode(), maskingUID.obvEncode()].obvEncode()
            }
        } else {
            return Data(repeating: 0x00, count: 0).obvEncode()
        }
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
        
        // At this point, we simply forward the return status
        return serverReturnedStatus
        
    }
            
}
