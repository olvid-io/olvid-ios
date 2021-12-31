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

public enum ObvPushNotificationType: CustomDebugStringConvertible {
    
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


public struct ObvPushNotificationParameters: CustomDebugStringConvertible {

    public let kickOtherDevices: Bool
    public let useMultiDevice: Bool

    public init(kickOtherDevices: Bool, useMultiDevice: Bool) {
        self.kickOtherDevices = kickOtherDevices
        self.useMultiDevice = useMultiDevice
    }


    public var debugDescription: String {
        return "kickOtherDevices: \(kickOtherDevices), useMultiDevice: \(useMultiDevice)"
    }

}
