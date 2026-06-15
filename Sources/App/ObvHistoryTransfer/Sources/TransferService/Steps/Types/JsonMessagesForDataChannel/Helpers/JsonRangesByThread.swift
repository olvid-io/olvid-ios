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


struct JsonRangesByThread {
    let ranges: [UUID : [ClosedRange<Int>]]
}


extension JsonRangesByThread: Codable {
    
    enum CodingKeys: String, CodingKey {
        case ranges = "ranges"
    }
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let dict: [String: [[Int]]] = .init(ranges, keyMapping: { $0.uuidString }, valueMapping: { $0.map({ [$0.lowerBound, $0.upperBound] }) })
        try container.encode(dict, forKey: .ranges)
    }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let ranges = try container.decode([String: [[Int]]].self, forKey: .ranges)
        self.ranges = try .init(
            ranges,
            keyMapping: {
                guard let uuid = UUID(uuidString: $0) else { assertionFailure(); throw ObvError.decodingFailed }
                return uuid
            },
            valueMapping: {
                guard $0.allSatisfy({ $0.count == 2 }) else { assertionFailure(); throw ObvError.decodingFailed }
                return $0.map({ $0[0]...$0[1] })
            })
    }
    
    enum ObvError: Error {
        case decodingFailed
    }
    
}

extension JsonRangesByThread: Equatable {
    // Synthetized implementation
}
