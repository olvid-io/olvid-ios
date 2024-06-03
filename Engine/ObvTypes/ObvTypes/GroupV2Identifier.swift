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

public struct ObvGroupV2Identifier: Hashable, Codable {
    
    public let ownedCryptoId: ObvCryptoId
    public let identifier: ObvGroupV2.Identifier
 
    
    public init(ownedCryptoId: ObvCryptoId, identifier: ObvGroupV2.Identifier) {
        self.ownedCryptoId = ownedCryptoId
        self.identifier = identifier
    }
}

// MARK: - LosslessStringConvertible

extension ObvGroupV2Identifier: LosslessStringConvertible, CustomStringConvertible {
    
    private static let separator: Character = "|"
    
    /// This serialization should **not** be used within long term storage since we may change it regularly.
    public init?(_ description: String) {
        let splits = description.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: { $0 == Self.separator })
        guard splits.count == 2,
              let ownedCryptoId = ObvCryptoId(String(splits[0])),
              let appGroupIdentifier = Data(hexString: String(splits[1])),
              let identifier = ObvGroupV2.Identifier(appGroupIdentifier: appGroupIdentifier)
        else {
            assertionFailure()
            return nil
        }
        self = .init(ownedCryptoId: ownedCryptoId, identifier: identifier)
    }
    
    
    /// This serialization should **not** be used within long term storage since we may change it regularly.
    public var description: String {
        [ownedCryptoId.description, identifier.appGroupIdentifier.hexString()]
            .joined(separator: String(Self.separator))
    }
    
}


/// 2023-09-23 Type introduced for sync snapshots. It should have been introduced earlier...
public typealias GroupV2Identifier = Data
