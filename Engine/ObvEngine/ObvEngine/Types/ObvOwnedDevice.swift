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
import ObvTypes
import ObvCrypto

/// See also ``struct ObvRemoteOwnedDevice``.
public struct ObvOwnedDevice: Hashable, CustomStringConvertible {
    
    public let identifier: Data
    public let ownedCryptoId: ObvCryptoId
    public let secureChannelStatus: SecureChannelStatus
    public let name: String?
    public let expirationDate: Date?
    public let latestRegistrationDate: Date?

    public enum SecureChannelStatus: Equatable, Hashable {
        case currentDevice
        case creationInProgress(preKeyAvailable: Bool)
        case created(preKeyAvailable: Bool)
    }
    
    var isCurrentDevice: Bool {
        secureChannelStatus == .currentDevice
    }
    
    public var ownedDeviceIdentifier: ObvOwnedDeviceIdentifier? {
        guard let deviceUID = UID(uid: identifier) else {
            assertionFailure()
            return nil
        }
        return ObvOwnedDeviceIdentifier(ownedCryptoId: ownedCryptoId, deviceUID: deviceUID)
    }
    
    init(identifier: Data, ownedCryptoIdentity: ObvCryptoIdentity, secureChannelStatus: SecureChannelStatus, name: String?, expirationDate: Date?, latestRegistrationDate: Date?) {
        self.identifier = identifier
        self.ownedCryptoId = ObvCryptoId(cryptoIdentity: ownedCryptoIdentity)
        self.secureChannelStatus = secureChannelStatus
        self.name = name
        self.expirationDate = expirationDate
        self.latestRegistrationDate = latestRegistrationDate
    }
    
}


// MARK: Implementing CustomStringConvertible
extension ObvOwnedDevice {
    public var description: String {
        return "ObvOwnedDevice<\(ownedCryptoId.description), \(identifier.description)>"
    }
}
