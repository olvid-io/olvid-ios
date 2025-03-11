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
import ObvCrypto
import ObvTypes
import ObvEncoder

struct GroupIdentifierForMigrationV9ToV10 {
    
    public let ownerIdentity: ObvCryptoIdentity
    public let uid: UID
    public let name: String
    
    public var raw: Data {
        return ownerIdentity.getIdentity() + uid.raw
    }
    
    public init(ownerIdentity: ObvCryptoIdentity, uid: UID, name: String) {
        self.ownerIdentity = ownerIdentity
        self.uid = uid
        self.name = name
    }
    
}

extension GroupIdentifierForMigrationV9ToV10: ObvCodable {
    
    public func obvEncode() -> ObvEncoded {
        return [self.ownerIdentity, self.uid, self.name].obvEncode()
    }
    
    
    public init?(_ encoded: ObvEncoded) {
        do { (ownerIdentity, uid, name) = try encoded.obvDecode() } catch { return nil }
    }
    
}


extension GroupIdentifierForMigrationV9ToV10: Hashable {
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.ownerIdentity)
        hasher.combine(self.uid)
    }
    
}
