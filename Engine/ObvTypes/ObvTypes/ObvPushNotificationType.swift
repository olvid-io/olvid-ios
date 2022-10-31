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

public enum ObvPushNotificationType: CustomDebugStringConvertible, ObvEncodable {
    
    case remote(pushToken: Data, voipToken: Data?, maskingUID: UID, parameters: ObvPushNotificationParameters)
    case polling(pollingInterval: TimeInterval)
    case registerDeviceUid(parameters: ObvPushNotificationParameters) // Used by the simulator
    
    // Server side: three types,
    // - push notification Android 0x01
    // - push notification iOS with extension 0x05
    // - push notification iOS sandbox with extension 0x04
    // - push notification none 0xff
    // The bytes on the server side have nothing to do with the following bytes, which are only used internally.
    public var byteId: UInt8 {
        switch self {
        case .remote:
            return 0x00 // For iOS (the code is 0x01 for Android)
        case .polling:
            return 0xff
        case .registerDeviceUid:
            return 0x01 // This byte is changed to 0xff before being transmitted to the server
        }
    }

    public var isPolling: Bool {
        return self.byteId == 0xff
    }

    public func hasSameType(than other: ObvPushNotificationType) -> Bool {
        return self.byteId == other.byteId
    }
    
    public func isEqual(to other: ObvPushNotificationType) -> Bool {
        switch self {
        case .remote(pushToken: let deviceToken, voipToken: let voipToken, maskingUID: _, parameters: let parameters):
            switch other {
            case .remote(pushToken: let otherDeviceToken, voipToken: let otherVoipToken, maskingUID: _, parameters: let otherParameters):
                return deviceToken == otherDeviceToken && voipToken == otherVoipToken && parameters.useMultiDevice == otherParameters.useMultiDevice
            default:
                return false
            }
        case .polling(let selfInterval):
            switch other {
            case .polling(let otherInterval):
                return selfInterval == otherInterval
            default:
                return false
            }
        case .registerDeviceUid(parameters: let parameters):
            switch other {
            case .registerDeviceUid(parameters: let otherParameters):
                return parameters.useMultiDevice == otherParameters.useMultiDevice
            default:
                return false
            }
        }
    }
    
    // ObvCodable
    
    public func obvEncode() -> ObvEncoded {
        switch self {
        case .remote(pushToken: let pushToken, voipToken: let voipToken, maskingUID: let maskingUID, parameters: let parameters):
            if let _voipToken = voipToken {
                return [Data([byteId]).obvEncode(), pushToken.obvEncode(), _voipToken.obvEncode(), maskingUID.obvEncode(), parameters.obvEncode()].obvEncode()
            } else {
                return [Data([byteId]).obvEncode(), pushToken.obvEncode(), maskingUID.obvEncode(), parameters.obvEncode()].obvEncode()
            }
        case .polling(let pollingInterval):
            return [Data([byteId]).obvEncode(), Int(pollingInterval).obvEncode()].obvEncode()
        case .registerDeviceUid(parameters: let parameters):
            return [Data([byteId]).obvEncode(), parameters.obvEncode()].obvEncode()
        }
    }
    
    public static func decode(_ obvEncoded: ObvEncoded) -> ObvPushNotificationType? {
        guard let decodedList = [ObvEncoded](obvEncoded) else {
            assertionFailure()
            return nil
        }
        guard let encodedByteId = decodedList.first else {
            assertionFailure()
            return nil
        }
        guard let byteIdAsData = Data(encodedByteId) else {
            assertionFailure()
            return nil
        }
        guard byteIdAsData.count == 1 else {
            assertionFailure()
            return nil
        }
        let byteId: UInt8 = byteIdAsData.first!
        
        switch byteId {
        case 0x00:
            if decodedList.count == 4 {
                guard let pushToken = Data(decodedList[1]) else { assertionFailure(); return nil }
                guard let maskingUID = UID(decodedList[2]) else { assertionFailure(); return nil }
                guard let parameters = ObvPushNotificationParameters.decode(decodedList[3]) else { assertionFailure(); return nil }
                return .remote(pushToken: pushToken, voipToken: nil, maskingUID: maskingUID, parameters: parameters)
            } else if decodedList.count == 5 {
                guard let pushToken = Data(decodedList[1]) else { assertionFailure(); return nil }
                guard let voipToken = Data(decodedList[2]) else { assertionFailure(); return nil }
                guard let maskingUID = UID(decodedList[3]) else { assertionFailure(); return nil }
                guard let parameters = ObvPushNotificationParameters.decode(decodedList[4]) else { assertionFailure(); return nil }
                return .remote(pushToken: pushToken, voipToken: voipToken, maskingUID: maskingUID, parameters: parameters)
            } else {
                return nil
            }
        case 0xff:
            guard decodedList.count == 2 else { return nil }
            guard let pollingInterval = Int(decodedList[1]) else { assertionFailure(); return nil }
            return ObvPushNotificationType.polling(pollingInterval: TimeInterval(pollingInterval))
        case 0x01:
            guard decodedList.count == 2 else { return nil }
            guard let parameters = ObvPushNotificationParameters.decode(decodedList[1]) else { assertionFailure(); return nil }
            return ObvPushNotificationType.registerDeviceUid(parameters: parameters)
        default:
            assertionFailure()
            return nil
        }
    }

    
}

// MARK: - CustomDebugStringConvertible
public extension ObvPushNotificationType {

    var debugDescription: String {
        switch self {
        case .polling(pollingInterval: let timeInterval):
            return "ObvPushNotificationType<Polling, timeInterval: \(timeInterval)>"
        case .remote(pushToken: let pushToken, voipToken: let voipToken, maskingUID: let maskingUID, parameters: let parameters):
            return "ObvPushNotificationType<Remote, token: \(pushToken.hexString()), voipToken: \(String(describing: voipToken?.hexString())) maskingUID: \(maskingUID.hexString()), parameters: (\(parameters.debugDescription))>"
        case .registerDeviceUid(parameters: let parameters):
            return "ObvPushNotificationType<RegisterDeviceUid, parameters: (\(parameters.debugDescription))>"
        }
    }

}


public struct ObvPushNotificationParameters: CustomDebugStringConvertible, ObvEncodable {

    public let kickOtherDevices: Bool
    public let useMultiDevice: Bool

    public init(kickOtherDevices: Bool, useMultiDevice: Bool) {
        self.kickOtherDevices = kickOtherDevices
        self.useMultiDevice = useMultiDevice
    }


    public var debugDescription: String {
        return "kickOtherDevices: \(kickOtherDevices), useMultiDevice: \(useMultiDevice)"
    }

    // ObvCodable
    
    public func obvEncode() -> ObvEncoded {
        return [kickOtherDevices, useMultiDevice].obvEncode()
    }
    
    public static func decode(_ obvEncoded: ObvEncoded) -> ObvPushNotificationParameters? {
        guard let decodedList = [ObvEncoded](obvEncoded) else { return nil }
        guard decodedList.count == 2 else { assertionFailure(); return nil }
        guard let kickOtherDevices = Bool(decodedList[0]) else { assertionFailure(); return nil }
        guard let useMultiDevice = Bool(decodedList[1]) else { assertionFailure(); return nil }
        return self.init(kickOtherDevices: kickOtherDevices, useMultiDevice: useMultiDevice)
    }

}
