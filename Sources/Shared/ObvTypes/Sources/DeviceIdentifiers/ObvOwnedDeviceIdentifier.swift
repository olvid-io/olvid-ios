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
import ObvCrypto


public struct ObvOwnedDeviceIdentifier: Hashable, Sendable {
    
    public let ownedCryptoId: ObvCryptoId
    public let deviceUID: UID
    
    public init(ownedCryptoId: ObvCryptoId, deviceUID: UID) {
        self.ownedCryptoId = ownedCryptoId
        self.deviceUID = deviceUID
    }
    
}


extension ObvOwnedDeviceIdentifier: Identifiable {
    
    public var id: Data {
        self.ownedCryptoId.getIdentity() + self.deviceUID.raw
    }
    
}


// MARK: - Implementing LosslessStringConvertible

extension ObvOwnedDeviceIdentifier: LosslessStringConvertible {
    
    private static var separator: String { "|" }
    
    public var description: String {
        self.ownedCryptoId.description + Self.separator + deviceUID.hexString()
    }
    
    public init?(_ description: String) {
        let splits = description.split(separator: Self.separator, maxSplits: 1, omittingEmptySubsequences: true)
        guard splits.count == 2 else { assertionFailure(); return nil }
        guard let ownedCryptoId = ObvCryptoId(String(splits[0])) else { assertionFailure(); return nil }
        guard let deviceUID = UID(hexString: String(splits[1])) else { assertionFailure(); return nil }
        self.init(ownedCryptoId: ownedCryptoId,
                  deviceUID: deviceUID)
    }
    
}
