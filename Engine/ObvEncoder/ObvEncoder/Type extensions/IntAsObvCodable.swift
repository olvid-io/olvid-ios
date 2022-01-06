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

extension Int: ObvCodable {
    
    private static let encodingLength = 8
    
    public static let lengthWhenObvEncoded = Int.encodingLength + ObvEncoded.lengthOverhead
    
    public init?(_ obvEncoded: ObvEncoded) {
        guard obvEncoded.byteId == .int else { return nil }
        guard obvEncoded.innerLength == Int.encodingLength else { return nil }
        self = ObvEncoded.lengthFrom(lengthAsData: obvEncoded.innerData)
    }
    
    public func encode() -> ObvEncoded {
        var innerData = Data()
        for i in 0..<Int.encodingLength {
            innerData.append(UInt8(self >> (8*(Int.encodingLength - 1 - i)) & 0xFF))
        }
        return ObvEncoded(byteId: .int, innerData: innerData)
    }
    
}
