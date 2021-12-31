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

public struct ObvCurrentDevice: Hashable, CustomStringConvertible {
    
    public let identifier: Data
    public let ownedIndentity: ObvOwnedIdentity
    
}

// MARK: Implementing CustomStringConvertible
extension ObvCurrentDevice {
    public var description: String {
        return "ObvCurrentDevice<\(ownedIndentity.description)>"
    }
}

internal extension ObvCurrentDevice {
    
    init?(currentDeviceUid: UID, identityDelegate: ObvIdentityDelegate, within obvContext: ObvContext) {
        let ownedCryptoIdentity: ObvCryptoIdentity
        do {
            ownedCryptoIdentity = try identityDelegate.getOwnedIdentityOfCurrentDeviceUid(currentDeviceUid, within: obvContext)
        } catch {
            return nil
        }
        guard let obvOwnedIdentity = ObvOwnedIdentity(ownedCryptoIdentity: ownedCryptoIdentity, identityDelegate: identityDelegate, within: obvContext) else { return nil }
        self.identifier = currentDeviceUid.raw
        self.ownedIndentity = obvOwnedIdentity
    }
    
}
