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

// We keep a precision up to the microsecond
extension Date: ObvCodable {
    
    public func obvEncode() -> ObvEncoded {
        let precision = Double(10^6)
        return Int(timeIntervalSince1970 * precision).obvEncode()
    }
    
    
    public init?(_ obvEncoded: ObvEncoded) {
        let precision = Double(10^6)
        guard let val = Int(obvEncoded) else { return nil }
        let timeIntervalSince1970 = Double(val) / precision
        self = Date(timeIntervalSince1970: timeIntervalSince1970)
    }
    
}
