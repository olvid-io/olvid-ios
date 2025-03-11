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

extension UInt8: ObvCodable {
    
    public func obvEncode() -> ObvEncoded {
        return Data([self]).obvEncode()
    }

    public init?(_ obvEncoded: ObvEncoded) {
        guard let data = Data(obvEncoded) else { return nil }
        guard data.count == 1 else { return nil }
        guard let byte = data.first else { return nil }
        self = byte
    }
    
}
