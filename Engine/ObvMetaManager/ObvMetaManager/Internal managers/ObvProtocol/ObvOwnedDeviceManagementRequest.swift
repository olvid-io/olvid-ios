/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import ObvCrypto
import ObvEncoder

/// Type used by the initial message of the `OwnedDeviceManagementProtocol`.
public enum ObvOwnedDeviceManagementRequest: ObvCodable {
    
    case setOwnedDeviceName(ownedDeviceUID: UID, ownedDeviceName: String)
    case deactivateOtherOwnedDevice(ownedDeviceUID: UID)
    case setUnexpiringDevice(ownedDeviceUID: UID)
    
    
    private var rawValue: Int {
        switch self {
        case .setOwnedDeviceName:
            return 0
        case .deactivateOtherOwnedDevice:
            return 1
        case .setUnexpiringDevice:
            return 2
        }
    }

    
    public func obvEncode() -> ObvEncoder.ObvEncoded {
        switch self {
        case .setOwnedDeviceName(let ownedDeviceUID, let ownedDeviceName):
            return [rawValue, ownedDeviceUID, ownedDeviceName].obvEncode()
        case .deactivateOtherOwnedDevice(let ownedDeviceUID):
            return [rawValue, ownedDeviceUID].obvEncode()
        case .setUnexpiringDevice(let ownedDeviceUID):
            return [rawValue, ownedDeviceUID].obvEncode()
        }
    }

    
    public init?(_ obvEncoded: ObvEncoder.ObvEncoded) {
        guard let listOfEncoded = [ObvEncoded](obvEncoded) else { assertionFailure(); return nil }
        guard let encodedRawValue = listOfEncoded.first else { assertionFailure(); return nil }
        guard let rawValue = Int(encodedRawValue) else { assertionFailure(); return nil }
        switch rawValue {
        case 0:
            guard listOfEncoded.count == 3 else { assertionFailure(); return nil }
            guard let ownedDeviceUID = UID(listOfEncoded[1]) else { assertionFailure(); return nil }
            guard let ownedDeviceName = String(listOfEncoded[2]) else { assertionFailure(); return nil }
            self = .setOwnedDeviceName(ownedDeviceUID: ownedDeviceUID, ownedDeviceName: ownedDeviceName)
        case 1:
            guard listOfEncoded.count == 2 else { assertionFailure(); return nil }
            guard let ownedDeviceUID = UID(listOfEncoded[1]) else { assertionFailure(); return nil }
            self = .deactivateOtherOwnedDevice(ownedDeviceUID: ownedDeviceUID)
        case 2:
            guard listOfEncoded.count == 2 else { assertionFailure(); return nil }
            guard let ownedDeviceUID = UID(listOfEncoded[1]) else { assertionFailure(); return nil }
            self = .setUnexpiringDevice(ownedDeviceUID: ownedDeviceUID)
        default:
            assertionFailure()
            return nil
        }
    }
    
}
