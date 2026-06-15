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


struct DstExpectedSha256: Equatable {
    let sha256s: [Data: UInt64] // each key is a sha256, the corresponding value is the length of the file
    
}


extension DstExpectedSha256: Codable {
    
    enum CodingKeys: String, CodingKey {
        case sha256s = "expectedSha256s"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let dict: [String: UInt64] = .init(sha256s, keyMapping: { $0.base64EncodedString() }, valueMapping: { $0 })
        try container.encode(dict, forKey: .sha256s)
    }

    public init(from decoder: Decoder) throws {
        do {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            do {
                let dict: [String: UInt64] = try values.decode([String: UInt64].self, forKey: .sha256s)
                self.sha256s = Dictionary(dict, keyMapping: { $0.base64EncodedToData }, valueMapping: { $0 })
            }
        } catch {
            assertionFailure()
            throw error
        }
    }
    
}
