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

extension Data: ObvCodable {
    
    public init?(_ obvEncoded: ObvEncoded) {
        guard obvEncoded.byteId == .bytes else { return nil }
        self = obvEncoded.innerData
    }
    
    public func obvEncode() -> ObvEncoded {
        return ObvEncoded(byteId: .bytes, innerData: self)
    }
    
    /// When the data is the representation of an encoded element, this method returns an appropriate ObvEncoded instance. Otherwise, it returns nil.
    public func asObvEncoded() -> ObvEncoded? {
        return ObvEncoded.init(withRawData: self)
    }
    
}
