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

extension Dictionary: ObvDecodable where Key == Data, Value == ObvEncoded {
    
    public init?(_ obvEncoded: ObvEncoded) {
        guard obvEncoded.byteId == .dictionary else { return nil }
        guard let unpackedList = ObvEncoded.unpack(obvEncoded), unpackedList.count % 2 == 0  else { return nil }
        self = ObvDictionary()
        for i in stride(from: 0, to: unpackedList.count, by: 2) {
            guard let key = Data(unpackedList[i]) else { return nil }
            let encodedValue = unpackedList[i.advanced(by: 1)]
            guard self[key] == nil else {
                return nil
            }
            self[key] = encodedValue
        }
    }
    
}

extension Dictionary where Key == Data, Value == ObvEncoded {

    public func obvEncode() -> ObvEncoded {
        var listToPack = [ObvEncoded]()
        for (data, encodedValue) in self {
            listToPack.append(data.obvEncode())
            listToPack.append(encodedValue)
        }
        return ObvEncoded.pack(listToPack, usingByteId: .dictionary)
    }

}

// This extension leverages the previous one
extension Dictionary: ObvEncodable where Key == Data, Value == ObvEncodable {
    
    public func obvEncode() -> ObvEncoded {
        let obvDict = self.mapValues { $0.obvEncode() }
        return obvDict.obvEncode()
    }
    
}
