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

public struct ObvGroupV2Identifier: Hashable {
    
    public let ownedCryptoId: ObvCryptoId
    public let identifier: ObvGroupV2.Identifier
 
    
    public init(ownedCryptoId: ObvCryptoId, identifier: ObvGroupV2.Identifier) {
        self.ownedCryptoId = ownedCryptoId
        self.identifier = identifier
    }
}


/// 2023-09-23 Type introduced for sync snapshots. It should have been introduced earlier...
public typealias GroupV2Identifier = Data
