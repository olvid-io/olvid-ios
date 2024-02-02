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


public enum ObvPushNotificationType: Hashable, Equatable, CustomDebugStringConvertible {
    
    case remote(ownedCryptoId: ObvCryptoIdentity, currentDeviceUID: UID, commonParameters: CommonParameters, optionalParameter: OptionalParameter, remoteTypeParameters: RemoteTypeParameters)
    case registerDeviceUid(ownedCryptoId: ObvCryptoIdentity, currentDeviceUID: UID, commonParameters: CommonParameters, optionalParameter: OptionalParameter = .none) // Used by the simulator
    
    public var debugDescription: String {
        switch self {
        case .remote(let ownedCryptoId, let currentDeviceUID, let commonParameters, let optionalParameter, let remoteTypeParameters):
            let values = [
                ownedCryptoId.debugDescription,
                currentDeviceUID.debugDescription,
                commonParameters.debugDescription,
                optionalParameter.debugDescription,
                remoteTypeParameters.debugDescription,
            ]
            return "ObvPushNotificationType-remote<\(values.joined(separator: ","))>"
        case .registerDeviceUid(let ownedCryptoId, let currentDeviceUID, let commonParameters, let optionalParameter):
            let values = [
                ownedCryptoId.debugDescription,
                currentDeviceUID.debugDescription,
                commonParameters.debugDescription,
                optionalParameter.debugDescription,
            ]
            return "ObvPushNotificationType-registerDeviceUid<\(values.joined(separator: ","))>"
        }
    }
    
    
    public struct CommonParameters: Hashable, Equatable, CustomDebugStringConvertible {
        
        public let keycloakPushTopics: Set<String>
        public let deviceNameForFirstRegistration: String
        
        public init(keycloakPushTopics: Set<String>, deviceNameForFirstRegistration: String) {
            self.keycloakPushTopics = keycloakPushTopics
            self.deviceNameForFirstRegistration = deviceNameForFirstRegistration
        }
        
        public var debugDescription: String {
            let values = [
                keycloakPushTopics.debugDescription,
                deviceNameForFirstRegistration,
            ]
            return "CommonParameters<\(values.joined(separator: ","))>"
        }
        
    }
    
    
    public func remoteNotificationByteIdentifierForServer(from originalRemoteNotificationByteIdentifierForServer: Data) -> Data {
        switch self {
        case .remote:
            return originalRemoteNotificationByteIdentifierForServer
        case .registerDeviceUid:
            return Data([0xff])
        }
    }
    
    
    public struct RemoteTypeParameters: Hashable, Equatable, CustomDebugStringConvertible {

        public let pushToken: Data
        public let voipToken: Data?
        public let maskingUID: UID
        
        public var debugDescription: String {
            let values = [
                String(pushToken.hexString().prefix(8)),
                String(voipToken?.hexString().prefix(8) ?? "nil"),
                maskingUID.debugDescription,
            ]
            return "RemoteTypeParameters<\(values.joined(separator: ","))>"
        }
        
        public init(pushToken: Data, voipToken: Data?, maskingUID: UID) {
            self.pushToken = pushToken
            self.voipToken = voipToken
            self.maskingUID = maskingUID
        }
        
    }
    
    public enum OptionalParameter: Hashable, Equatable, CustomDebugStringConvertible {
        case none
        case reactivateCurrentDevice(replacedDeviceUid: UID?)
        case forceRegister
        
        public var debugDescription: String {
            let value: String
            switch self {
            case .none:
                value = "none"
            case .reactivateCurrentDevice(let replacedDeviceUid):
                value = "reactivateCurrentDevice(\(replacedDeviceUid?.debugDescription ?? "nil")"
            case .forceRegister:
                value = "forceRegister"
            }
            return "OptionalParameter<\(value)>"
        }
        
        public var reactivateCurrentDevice: Bool {
            switch self {
            case .none, .forceRegister:
                return false
            case .reactivateCurrentDevice:
                return true
            }
        }
        
        public var replacedDeviceUid: UID? {
            switch self {
            case .none, .forceRegister:
                return nil
            case .reactivateCurrentDevice(let replacedDeviceUid):
                return replacedDeviceUid
            }
        }

    }
    
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
    
    
    public var currentDeviceUID: UID {
        switch self {
        case .registerDeviceUid(ownedCryptoId: _, currentDeviceUID: let currentDeviceUID, commonParameters: _, optionalParameter: _):
            return currentDeviceUID
        case .remote(ownedCryptoId: _, currentDeviceUID: let currentDeviceUID, commonParameters: _, optionalParameter: _, remoteTypeParameters: _):
            return currentDeviceUID
        }
    }

    
    public var optionalParameter: OptionalParameter {
        switch self {
        case .registerDeviceUid(ownedCryptoId: _, currentDeviceUID: _, commonParameters: _, optionalParameter: let optionalParameter):
            return optionalParameter
        case .remote(ownedCryptoId: _, currentDeviceUID: _, commonParameters: _, optionalParameter: let optionalParameter, remoteTypeParameters: _):
            return optionalParameter
        }
    }
    

    public var commonParameters: CommonParameters {
        switch self {
        case .registerDeviceUid(ownedCryptoId: _, currentDeviceUID: _, commonParameters: let commonParameters, optionalParameter: _):
            return commonParameters
        case .remote(ownedCryptoId: _, currentDeviceUID: _, commonParameters: let commonParameters, optionalParameter: _, remoteTypeParameters: _):
            return commonParameters
        }
    }
    
    
    public var remoteTypeParameters: RemoteTypeParameters? {
        switch self {
        case .registerDeviceUid:
            return nil
        case .remote(ownedCryptoId: _, currentDeviceUID: _, commonParameters: _, optionalParameter: _, remoteTypeParameters: let remoteTypeParameters):
            return remoteTypeParameters
        }
    }
    
    
    public var ownedCryptoId: ObvCryptoIdentity {
        switch self {
        case .registerDeviceUid(ownedCryptoId: let ownedCryptoId, currentDeviceUID: _, commonParameters: _, optionalParameter: _):
            return ownedCryptoId
        case .remote(ownedCryptoId: let ownedCryptoId, currentDeviceUID: _, commonParameters: _, optionalParameter: _, remoteTypeParameters: _):
            return ownedCryptoId
        }
    }
    
//    public var ownedCryptoId: ObvCryptoIdentity {
//        switch self {
//        case .remote(let ownedCryptoId, _, _, _, _, _):
//            return ownedCryptoId
//        case .registerDeviceUid(let ownedCryptoId, _, _):
//            return ownedCryptoId
//        }
//    }
//
//    public var currentDeviceUID: UID {
//        switch self {
//        case .remote(_, let currentDeviceUID, _, _, _, _):
//            return currentDeviceUID
//        case .registerDeviceUid(_, let currentDeviceUID, _):
//            return currentDeviceUID
//        }
//    }
//
//
//    public var parameters: ObvPushNotificationParameters {
//        switch self {
//        case .remote(_, _, _, _, _, let parameters):
//            return parameters
//        case .registerDeviceUid(_, _, let parameters):
//            return parameters
//        }
//    }
    

//    public func hasSameType(than other: ObvPushNotificationType) -> Bool {
//        return self.byteId == other.byteId
//    }
//
//
//    public static func == (lhs: ObvPushNotificationType, rhs: ObvPushNotificationType) -> Bool {
//        switch lhs {
//        case .remote(ownedCryptoId: let ownedCryptoId, currentDeviceUID: let currentDeviceUID, pushToken: let deviceToken, voipToken: let voipToken, maskingUID: let maskingUID, parameters: let parameters):
//            switch rhs {
//            case .remote(ownedCryptoId: let otherOwnedCryptoId, currentDeviceUID: let otherCurrentDeviceUID, pushToken: let otherDeviceToken, voipToken: let otherVoipToken, maskingUID: let otherMaskingUID, parameters: let otherParameters):
//                return ownedCryptoId == otherOwnedCryptoId && currentDeviceUID == otherCurrentDeviceUID && deviceToken == otherDeviceToken && voipToken == otherVoipToken && maskingUID == otherMaskingUID && parameters == otherParameters
//            default:
//                return false
//            }
//        case .registerDeviceUid(ownedCryptoId: let ownedCryptoId, currentDeviceUID: let currentDeviceUID, parameters: let parameters):
//            switch rhs {
//            case .registerDeviceUid(ownedCryptoId: let otherOwnedCryptoId, currentDeviceUID: let otherCurrentDeviceUID, parameters: let otherParameters):
//                return ownedCryptoId == otherOwnedCryptoId && currentDeviceUID == otherCurrentDeviceUID && parameters == otherParameters
//            default:
//                return false
//            }
//        }
//    }

    
//    public func withUpdatedKeycloakPushTopics(_ newKeycloakPushTopics: Set<String>) -> ObvPushNotificationType {
//        switch self {
//        case .remote(let ownedCryptoId, let currentDeviceUID, let pushToken, let voipToken, let maskingUID, let parameters):
//            return .remote(
//                ownedCryptoId: ownedCryptoId,
//                currentDeviceUID: currentDeviceUID,
//                pushToken: pushToken,
//                voipToken: voipToken,
//                maskingUID: maskingUID,
//                parameters: parameters.withUpdatedKeycloakPushTopics(newKeycloakPushTopics))
//        case .registerDeviceUid(let ownedCryptoId, let currentDeviceUID, let parameters):
//            return .registerDeviceUid(
//                ownedCryptoId: ownedCryptoId,
//                currentDeviceUID: currentDeviceUID,
//                parameters: parameters.withUpdatedKeycloakPushTopics(newKeycloakPushTopics))
//        }
//    }
//
//    public func withForcedRegister() -> ObvPushNotificationType {
//        switch self {
//        case .remote(let ownedCryptoId, let currentDeviceUID, let pushToken, let voipToken, let maskingUID, let parameters):
//            return .remote(
//                ownedCryptoId: ownedCryptoId,
//                currentDeviceUID: currentDeviceUID,
//                pushToken: pushToken,
//                voipToken: voipToken,
//                maskingUID: maskingUID,
//                parameters: parameters.withForcedRegister())
//        case .registerDeviceUid(let ownedCryptoId, let currentDeviceUID, let parameters):
//            return .registerDeviceUid(
//                ownedCryptoId: ownedCryptoId,
//                currentDeviceUID: currentDeviceUID,
//                parameters: parameters.withForcedRegister())
//        }
//    }
    
}


// MARK: - CustomDebugStringConvertible

//public extension ObvPushNotificationType {
//
//    var debugDescription: String {
//        switch self {
//        case .remote(ownedCryptoId: let ownedCryptoId, currentDeviceUID: let currentDeviceUID, pushToken: let pushToken, voipToken: let voipToken, maskingUID: let maskingUID, parameters: let parameters):
//            return "ObvPushNotificationType<Remote, ownedCryptoId: \(ownedCryptoId.debugDescription), currentDeviceUID: \(currentDeviceUID.debugDescription), token: \(pushToken.hexString()), voipToken: \(String(describing: voipToken?.hexString())) maskingUID: \(maskingUID.hexString()), parameters: (\(parameters.debugDescription))>"
//        case .registerDeviceUid(ownedCryptoId: let ownedCryptoId, currentDeviceUID: let currentDeviceUID, parameters: let parameters):
//            return "ObvPushNotificationType<RegisterDeviceUid, ownedCryptoId: \(ownedCryptoId.debugDescription), currentDeviceUID: \(currentDeviceUID.debugDescription), parameters: (\(parameters.debugDescription))>"
//        }
//    }
//
//}


//public struct ObvPushNotificationParameters: Hashable, Equatable, CustomDebugStringConvertible {
//
//    public let reactivateCurrentDevice: Bool
//    public let replacedDeviceUid: UID?
//    public let keycloakPushTopics: Set<String>
//    public let encryptedDeviceNameForFirstRegistration: EncryptedData
//    public let forceRegister: Bool
//
//    public init(reactivateCurrentDevice: Bool, replacedDeviceUid: UID?, keycloakPushTopics: Set<String>, encryptedDeviceNameForFirstRegistration: EncryptedData, forceRegister: Bool) {
//        self.reactivateCurrentDevice = reactivateCurrentDevice
//        self.replacedDeviceUid = replacedDeviceUid
//        self.keycloakPushTopics = keycloakPushTopics
//        self.encryptedDeviceNameForFirstRegistration = encryptedDeviceNameForFirstRegistration
//        self.forceRegister = forceRegister
//    }
//
//
//    public var debugDescription: String {
//        return "reactivateCurrentDevice: \(reactivateCurrentDevice), keycloakPushTopics: \(keycloakPushTopics.joined(separator: ", "))"
//    }
//
//    func withUpdatedKeycloakPushTopics(_ newKeycloakPushTopics: Set<String>) -> ObvPushNotificationParameters {
//        return ObvPushNotificationParameters(reactivateCurrentDevice: reactivateCurrentDevice, replacedDeviceUid: replacedDeviceUid, keycloakPushTopics: newKeycloakPushTopics, encryptedDeviceNameForFirstRegistration: encryptedDeviceNameForFirstRegistration, forceRegister: forceRegister)
//    }
//
//    func withForcedRegister() -> ObvPushNotificationParameters {
//        return ObvPushNotificationParameters(reactivateCurrentDevice: reactivateCurrentDevice, replacedDeviceUid: replacedDeviceUid, keycloakPushTopics: keycloakPushTopics, encryptedDeviceNameForFirstRegistration: encryptedDeviceNameForFirstRegistration, forceRegister: true)
//    }
//
//}
