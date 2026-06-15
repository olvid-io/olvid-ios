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


extension UInt64 {
    
    func to8Bytes() -> Data {
        var innerData = Data()
        let byteLenght = 8
        for i in 0..<byteLenght {
            innerData.append(UInt8((self >> (8*(byteLenght - 1 - i))) & 0xFF))
        }
        return innerData
    }
    
    static func from8Bytes(_ data: Data) throws -> Self {
        guard data.count == 8 else {
            assertionFailure()
            throw RTCDataBufferHandler.ObvError.couldNotParseValue
        }
        var value: Self = 0
        for i in data.startIndex..<data.startIndex.advanced(by: 8) {
            value = (value << 8) | Self(data[i])
        }
        return value
    }

}
