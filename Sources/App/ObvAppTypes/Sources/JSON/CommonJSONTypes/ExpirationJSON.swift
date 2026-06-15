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


public struct ExpirationJSON: Codable, Equatable, Hashable {

    public let readOnce: Bool
    public let visibilityDuration: TimeInterval?
    public let existenceDuration: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case readOnce = "ro"
        case visibilityDuration = "vis"
        case existenceDuration = "ex"
    }

    enum ExpirationJSONCodingError: Error {
        case decoding(String)
    }

    public init(readOnce: Bool, visibilityDuration: TimeInterval?, existenceDuration: TimeInterval?) {
        self.readOnce = readOnce
        self.visibilityDuration = visibilityDuration
        self.existenceDuration = existenceDuration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let readOnce = try container.decodeIfPresent(Bool.self, forKey: .readOnce) {
            self.readOnce = readOnce
        } else {
            self.readOnce = false
        }
        if let visibilityDuration = try container.decodeIfPresent(Int.self, forKey: .visibilityDuration) {
            self.visibilityDuration = TimeInterval(visibilityDuration)
        } else {
            self.visibilityDuration = nil
        }
        if let existenceDuration = try container.decodeIfPresent(Int.self, forKey: .existenceDuration) {
            self.existenceDuration = TimeInterval(existenceDuration)
        } else {
            self.existenceDuration = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if readOnce {
            try container.encodeIfPresent(readOnce, forKey: .readOnce)
        }
        if let visibilityDuration = self.visibilityDuration {
            try container.encodeIfPresent(Int(visibilityDuration), forKey: .visibilityDuration)
        }
        if let existenceDuration = self.existenceDuration {
            try container.encodeIfPresent(Int(existenceDuration), forKey: .existenceDuration)
        }
    }

    public func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        return data
    }

    public static func jsonDecode(_ data: Data) throws -> ExpirationJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(ExpirationJSON.self, from: data)
    }

}
