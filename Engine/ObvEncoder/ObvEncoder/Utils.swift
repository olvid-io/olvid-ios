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

public extension String {
    
    private static func decodeNibble(_ u: UInt8) -> UInt8? {
        switch(u) {
        case 0x30 ... 0x39:
            return UInt8(u - 0x30)
        case 0x41 ... 0x46:
            return UInt8(u - 0x41 + 10)
        case 0x61 ... 0x66:
            return UInt8(u - 0x61 + 10)
        default:
            return nil
        }
    }
    
    
    func dataFromHexString() -> Data? {
        if self.count == 0 {
            return Data()
        }
        guard self.count % 2 == 0 else { return nil }
        let nbrOfCharactersToDrop: Int
        if self.hasPrefix("0x") {
            nbrOfCharactersToDrop = 2
        } else {
            nbrOfCharactersToDrop = 0
        }
        let nibbles = self.dropFirst(nbrOfCharactersToDrop).utf8.map() { return String.decodeNibble($0) }
        guard !nibbles.contains(nil) else { return nil }
        let dataAsBytes = stride(from: 0, to: nibbles.count, by: 2).map {
            return UInt8((nibbles[$0]! << 4) + nibbles[$0+1]!)
        }
        return Data(dataAsBytes)
    }
}
