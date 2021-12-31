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
import ObvEncoder

public enum ObvChannelMessageType: Int, ObvCodable {
    case ProtocolMessage = 0
    case ApplicationMessage = 1
    case DialogMessage = 2
    case DialogResponseMessage = 3
    case ServerQuery = 4
    case ServerResponse = 5
}

// Implementing ObvCodable
extension ObvChannelMessageType {
    public init?(_ obvEncoded: ObvEncoded) {
        guard let intValue = Int(obvEncoded) else { return nil }
        guard let type = ObvChannelMessageType(rawValue: intValue) else { return nil }
        self = type
    }
    
    public func encode() -> ObvEncoded {
        let intValue = self.rawValue
        return intValue.encode()
    }
}
