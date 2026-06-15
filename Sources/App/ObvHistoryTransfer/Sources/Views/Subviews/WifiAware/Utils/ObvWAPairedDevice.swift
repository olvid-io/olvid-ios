/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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


public struct ObvWAPairedDevice: Identifiable, Sendable, Equatable, Hashable {
    
    public let id: UInt64
    let pairingInfo: ObvPairingInfo?
    
    struct ObvPairingInfo: Sendable, Equatable, Hashable {
        let vendorName: String
        let modelName: String
        let pairingName: String
        let description: String
        init(vendorName: String, modelName: String, pairingName: String, description: String) {
            self.vendorName = vendorName
            self.modelName = modelName
            self.pairingName = pairingName
            self.description = description
        }
    }
    
}
