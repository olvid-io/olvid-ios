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
import ObvTypes

extension ObvPushNotificationType: ObvEncodable {
    
    public func encode() -> ObvEncoded {
        switch self {
        case .remote(pushToken: let pushToken, voipToken: let voipToken, maskingUID: let maskingUID, parameters: let parameters):
            if let _voipToken = voipToken {
                return [Data([byteId]).encode(), pushToken.encode(), _voipToken.encode(), maskingUID.encode(), parameters.encode()].encode()
            } else {
                return [Data([byteId]).encode(), pushToken.encode(), maskingUID.encode(), parameters.encode()].encode()
            }
        case .polling(let pollingInterval):
            return [Data([byteId]).encode(), Int(pollingInterval).encode()].encode()
        case .registerDeviceUid(parameters: let parameters):
            return [Data([byteId]).encode(), parameters.encode()].encode()
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


extension ObvPushNotificationParameters: ObvEncodable {
    
    public func encode() -> ObvEncoded {
        return [kickOtherDevices, useMultiDevice].encode()
    }
    
    public static func decode(_ obvEncoded: ObvEncoded) -> ObvPushNotificationParameters? {
        guard let decodedList = [ObvEncoded](obvEncoded) else { return nil }
        guard decodedList.count == 2 else { assertionFailure(); return nil }
        guard let kickOtherDevices = Bool(decodedList[0]) else { assertionFailure(); return nil }
        guard let useMultiDevice = Bool(decodedList[1]) else { assertionFailure(); return nil }
        return self.init(kickOtherDevices: kickOtherDevices, useMultiDevice: useMultiDevice)
    }
}
