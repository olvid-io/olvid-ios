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

extension Bool: ObvCodable {
    
    private static let encodingLength = 1
    
    public init?(_ obvEncoded: ObvEncoded) {
        guard obvEncoded.byteId == .bool else { return nil }
        guard obvEncoded.innerLength == Bool.encodingLength else { return nil }
        guard let lastByte = obvEncoded.rawData.last else { return nil }
        switch lastByte {
        case 0x00:
            self = false
        case 0x01:
            self = true
        default:
            return nil
        }
    }
    
    public func encode() -> ObvEncoded {
        let innerData: Data
        if self {
            innerData = Data([0x01])
        } else {
            innerData = Data([0x00])
        }
        return ObvEncoded(byteId: .bool, innerData: innerData)
    }
}
