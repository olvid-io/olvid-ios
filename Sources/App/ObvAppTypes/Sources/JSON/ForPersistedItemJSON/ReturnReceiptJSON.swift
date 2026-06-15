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
import OSLog
import ObvTypes


public struct ReturnReceiptJSON {
    
    private let nonce: Data
    private let key: Data
    
    public var elements: ObvReturnReceiptElements {
        return ObvReturnReceiptElements(nonce: nonce, key: key)
    }

    public init(returnReceiptElements: ObvReturnReceiptElements) {
        self.nonce = returnReceiptElements.nonce
        self.key = returnReceiptElements.key
    }
    
    private init(nonce: Data, key: Data) {
        self.nonce = nonce
        self.key = key
    }

}


extension ReturnReceiptJSON: Codable {
    
    enum CodingKeys: String, CodingKey {
        case nonce = "nonce"
        case key = "key"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.nonce = try values.decode(Data.self, forKey: .nonce)
        self.key = try values.decode(Data.self, forKey: .key)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nonce, forKey: .nonce)
        try container.encode(key, forKey: .key)
    }
    
    public func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
    
    public static func jsonDecode(_ data: Data) throws -> ReturnReceiptJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(ReturnReceiptJSON.self, from: data)
    }

}
