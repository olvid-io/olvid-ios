/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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


public enum ObvGroupIdentifier: Equatable, Sendable, Hashable {
    
    case groupV1(ObvGroupV1Identifier)
    case groupV2(ObvGroupV2Identifier)
    
    public var ownedCryptoId: ObvCryptoId {
        switch self {
        case .groupV1(let obvGroupV1Identifier):
            return obvGroupV1Identifier.ownedCryptoId
        case .groupV2(let obvGroupV2Identifier):
            return obvGroupV2Identifier.ownedCryptoId
        }
    }
    
}


extension ObvGroupIdentifier: Identifiable {
    
    public var id: Data {
        switch self {
        case .groupV1(let obvGroupV1Identifier):
            return Data(repeating: 0x01, count: 1) + obvGroupV1Identifier.id
        case .groupV2(let obvGroupV2Identifier):
            return Data(repeating: 0x02, count: 1) + obvGroupV2Identifier.id
        }
    }
    
}
