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
import CoreData
import ObvCrypto
import ObvTypes
import ObvMetaManager
import OlvidUtils


public struct ObvRemoteOwnedDevice: Hashable, CustomStringConvertible {
    
    public let identifier: Data
    public let ownedIndentity: ObvOwnedIdentity
    
}


// MARK: Implementing CustomStringConvertible
extension ObvRemoteOwnedDevice {
    public var description: String {
        return "ObvRemoteOwnedDevice<\(ownedIndentity.description)>"
    }
}

internal extension ObvRemoteOwnedDevice {
    
    init?(remoteOwnedDeviceUid: UID, ownedCryptoIdentity: ObvCryptoIdentity, identityDelegate: ObvIdentityDelegate, within obvContext: ObvContext) {
        guard let ownedIdentity = ObvOwnedIdentity(ownedCryptoIdentity: ownedCryptoIdentity, identityDelegate: identityDelegate, within: obvContext) else { return nil }
        do {
            guard try identityDelegate.isDevice(withUid: remoteOwnedDeviceUid, aRemoteDeviceOfOwnedIdentity: ownedCryptoIdentity, within: obvContext) else { return nil }
        } catch {
            return nil
        }
        self.identifier = remoteOwnedDeviceUid.raw
        self.ownedIndentity = ownedIdentity
    }
    
}
