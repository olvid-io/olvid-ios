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

public final class ObvServerRegisterRemotePushNotificationMethod: ObvServerDataMethod {
    
    static let log = OSLog(subsystem: "io.olvid.server.interface.ObvServerRegisterRemotePushNotificationMethod", category: "ObvServerInterface")
    
    public let pathComponent = "/registerPushNotification"
    
    public var serverURL: URL { return toIdentity.serverURL }
    public let toIdentity: ObvCryptoIdentity
    public var ownedIdentity: ObvCryptoIdentity? { ownedCryptoId }
    private let ownedCryptoId: ObvCryptoIdentity
    private let pushNotification: ObvPushNotificationType
    private let sessionToken: Data
    private let remoteNotificationByteIdentifierForServer: Data // One byte
    public let flowId: FlowIdentifier
    public let isActiveOwnedIdentityRequired = false
    let prng: PRNGService

    weak public var identityDelegate: ObvIdentityDelegate? = nil
    

    public init(pushNotification: ObvPushNotificationType, sessionToken: Data, remoteNotificationByteIdentifierForServer: Data, flowId: FlowIdentifier, prng: PRNGService) {
        self.pushNotification = pushNotification
        self.sessionToken = sessionToken
        self.remoteNotificationByteIdentifierForServer = remoteNotificationByteIdentifierForServer
        self.flowId = flowId
        self.toIdentity = pushNotification.ownedCryptoId
        self.ownedCryptoId = pushNotification.ownedCryptoId
        self.prng = prng
    }


    public enum PossibleReturnStatus: UInt8, CustomDebugStringConvertible {
        case ok = 0x00
        case invalidSession = 0x04
        case anotherDeviceIsAlreadyRegistered = 0x0a
        case deviceToReplaceIsNotRegistered = 0x0b
        case generalError = 0xff
        
        public var debugDescription: String {
            switch self {
            case .ok: return "ok"
            case .invalidSession: return "invalidSession"
            case .anotherDeviceIsAlreadyRegistered: return "anotherDeviceIsAlreadyRegistered"
            case .deviceToReplaceIsNotRegistered: return "deviceToReplaceIsNotRegistered"
            case .generalError: return "generalError"
            }
        }
        
    }
    

    lazy public var dataToSend: Data? = {
        let listOfEncodedKeycloakPushTopics = pushNotification.commonParameters.keycloakPushTopics.map({ $0.obvEncode() })
        var listToEncode = [
            toIdentity.getIdentity().obvEncode(), // 0
            sessionToken.obvEncode(), // 1
            pushNotification.currentDeviceUID.obvEncode(), // 2
            pushNotification.remoteNotificationByteIdentifierForServer(from: remoteNotificationByteIdentifierForServer).obvEncode(), // 3
            extraInfo, // 4
            pushNotification.optionalParameter.reactivateCurrentDevice.obvEncode(), // 5
            listOfEncodedKeycloakPushTopics.obvEncode(), // 6
            DeviceNameUtils.encrypt(deviceName: pushNotification.commonParameters.deviceNameForFirstRegistration, for: ownedCryptoId, using: prng).raw.obvEncode(), // 7
        ]
        if pushNotification.optionalParameter.reactivateCurrentDevice, let replacedDeviceUid = pushNotification.optionalParameter.replacedDeviceUid {
            listToEncode.append(replacedDeviceUid.obvEncode()) // 8
        }
        let encodedList: ObvEncoded = listToEncode.obvEncode()
        return encodedList.rawData
    }()

    
    lazy private var extraInfo: ObvEncoded = {
        if let remoteTypeParameters = pushNotification.remoteTypeParameters {
            let pushToken = remoteTypeParameters.pushToken
            let maskingUID = remoteTypeParameters.maskingUID
            if let voipToken = remoteTypeParameters.voipToken {
                return [pushToken.obvEncode(), maskingUID.obvEncode(), voipToken.obvEncode()].obvEncode()
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
