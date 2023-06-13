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
import ObvEncoder
import ObvCrypto


public enum ObvPushNotificationType: Equatable, CustomDebugStringConvertible {
    
    case remote(ownedCryptoId: ObvCryptoIdentity, currentDeviceUID: UID, pushToken: Data, voipToken: Data?, maskingUID: UID, parameters: ObvPushNotificationParameters)
    case registerDeviceUid(ownedCryptoId: ObvCryptoIdentity, currentDeviceUID: UID, parameters: ObvPushNotificationParameters) // Used by the simulator
    
    public enum ByteId: UInt8, CaseIterable {
        case remote = 0x00 // For iOS (the code is 0x01 for Android)
        case registerDeviceUid = 0xff // Was 0x01 in earlier versions. This byte is changed to 0xff before being transmitted to the server
    }
    
    // Server side: three types,
    // - push notification Android 0x01
    // - push notification iOS with extension 0x05
    // - push notification iOS sandbox with extension 0x04
    // - push notification none 0xff
    // The bytes on the server side have nothing to do with the following bytes, which are only used internally.
    public var byteId: ByteId {
        switch self {
        case .remote:
            return ByteId.remote
        case .registerDeviceUid:
            return ByteId.registerDeviceUid
        }
    }
    
    public var ownedCryptoId: ObvCryptoIdentity {
        switch self {
        case .remote(let ownedCryptoId, _, _, _, _, _):
            return ownedCryptoId
        case .registerDeviceUid(let ownedCryptoId, _, _):
            return ownedCryptoId
        }
    }
    
    public var currentDeviceUID: UID {
        switch self {
        case .remote(_, let currentDeviceUID, _, _, _, _):
            return currentDeviceUID
        case .registerDeviceUid(_, let currentDeviceUID, _):
            return currentDeviceUID
        }
    }
    
    public var kickOtherDevices: Bool {
        switch self {
        case .remote(_, _, _, _, _, let parameters):
            return parameters.kickOtherDevices
        case .registerDeviceUid(_, _, let parameters):
            return parameters.kickOtherDevices
        }
    }

    public func hasSameType(than other: ObvPushNotificationType) -> Bool {
        return self.byteId == other.byteId
    }
    
    
    public static func == (lhs: ObvPushNotificationType, rhs: ObvPushNotificationType) -> Bool {
        switch lhs {
        case .remote(ownedCryptoId: let ownedCryptoId, currentDeviceUID: let currentDeviceUID, pushToken: let deviceToken, voipToken: let voipToken, maskingUID: let maskingUID, parameters: let parameters):
            switch rhs {
            case .remote(ownedCryptoId: let otherOwnedCryptoId, currentDeviceUID: let otherCurrentDeviceUID, pushToken: let otherDeviceToken, voipToken: let otherVoipToken, maskingUID: let otherMaskingUID, parameters: let otherParameters):
                return ownedCryptoId == otherOwnedCryptoId && currentDeviceUID == otherCurrentDeviceUID && deviceToken == otherDeviceToken && voipToken == otherVoipToken && maskingUID == otherMaskingUID && parameters == otherParameters
            default:
                return false
            }
        case .registerDeviceUid(ownedCryptoId: let ownedCryptoId, currentDeviceUID: let currentDeviceUID, parameters: let parameters):
            switch rhs {
            case .registerDeviceUid(ownedCryptoId: let otherOwnedCryptoId, currentDeviceUID: let otherCurrentDeviceUID, parameters: let otherParameters):
                return ownedCryptoId == otherOwnedCryptoId && currentDeviceUID == otherCurrentDeviceUID && parameters == otherParameters
            default:
                return false
            }
        }
    }

    
    public func withUpdatedKeycloakPushTopics(_ newKeycloakPushTopics: Set<String>) -> ObvPushNotificationType {
        switch self {
        case .remote(let ownedCryptoId, let currentDeviceUID, let pushToken, let voipToken, let maskingUID, let parameters):
            return .remote(
                ownedCryptoId: ownedCryptoId,
                currentDeviceUID: currentDeviceUID,
                pushToken: pushToken,
                voipToken: voipToken,
                maskingUID: maskingUID,
                parameters: parameters.withUpdatedKeycloakPushTopics(newKeycloakPushTopics))
        case .registerDeviceUid(let ownedCryptoId, let currentDeviceUID, let parameters):
            return .registerDeviceUid(
                ownedCryptoId: ownedCryptoId,
                currentDeviceUID: currentDeviceUID,
                parameters: parameters.withUpdatedKeycloakPushTopics(newKeycloakPushTopics))
        }
    }

}


// MARK: - CustomDebugStringConvertible

public extension ObvPushNotificationType {

    var debugDescription: String {
        switch self {
        case .remote(ownedCryptoId: let ownedCryptoId, currentDeviceUID: let currentDeviceUID, pushToken: let pushToken, voipToken: let voipToken, maskingUID: let maskingUID, parameters: let parameters):
            return "ObvPushNotificationType<Remote, ownedCryptoId: \(ownedCryptoId.debugDescription), currentDeviceUID: \(currentDeviceUID.debugDescription), token: \(pushToken.hexString()), voipToken: \(String(describing: voipToken?.hexString())) maskingUID: \(maskingUID.hexString()), parameters: (\(parameters.debugDescription))>"
        case .registerDeviceUid(ownedCryptoId: let ownedCryptoId, currentDeviceUID: let currentDeviceUID, parameters: let parameters):
            return "ObvPushNotificationType<RegisterDeviceUid, ownedCryptoId: \(ownedCryptoId.debugDescription), currentDeviceUID: \(currentDeviceUID.debugDescription), parameters: (\(parameters.debugDescription))>"
        }
    }

}


public struct ObvPushNotificationParameters: Equatable, CustomDebugStringConvertible {

    public let kickOtherDevices: Bool
    public let useMultiDevice: Bool
    public let keycloakPushTopics: Set<String>

    public init(kickOtherDevices: Bool, useMultiDevice: Bool, keycloakPushTopics: Set<String>) {
        self.kickOtherDevices = kickOtherDevices
        self.useMultiDevice = useMultiDevice
        self.keycloakPushTopics = keycloakPushTopics
    }


    public var debugDescription: String {
        return "kickOtherDevices: \(kickOtherDevices), useMultiDevice: \(useMultiDevice), keycloakPushTopics: \(keycloakPushTopics.joined(separator: ", "))"
    }
    
    func withUpdatedKeycloakPushTopics(_ newKeycloakPushTopics: Set<String>) -> ObvPushNotificationParameters {
        return ObvPushNotificationParameters(kickOtherDevices: kickOtherDevices, useMultiDevice: useMultiDevice, keycloakPushTopics: newKeycloakPushTopics)
    }

}
