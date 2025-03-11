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
import ObvBigInt

extension BigInt: ObvCodable {
    
    public convenience init?(_ obvEncoded: ObvEncoded) {
        guard obvEncoded.byteId == .unsignedBigInt else { return nil }
        self.init([UInt8](obvEncoded.innerData))
    }
    
    public func obvEncode() -> ObvEncoded {
        let length = self.byteSize()
        return encode(withInnerLength: length)!
    }
    
    public func encode(withInnerLength innerLength: Int) -> ObvEncoded? {
        guard self.isNonNegative() else { return nil }
        guard let bytearray = try? [UInt8](self, count: innerLength) else { return nil }
        let innerData = Data(bytearray)
        return ObvEncoded(byteId: .unsignedBigInt, innerData: innerData)
    }
}
