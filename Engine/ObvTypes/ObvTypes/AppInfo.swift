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

public enum AppInfo {
    case int(_: Int)
    case string(_: String)
    case bool(_: Bool)
    case dictionary(_: [String: AppInfo])
    case array(_: [AppInfo])
    case unknown
}

extension AppInfo: Codable {

    public init(from decoder: Decoder) throws {
        let values = try decoder.singleValueContainer()
        if let value = try? values.decode(Int.self) {
            self = .int(value)
        } else if let value = try? values.decode(String.self) {
            self = .string(value)
        } else if let value = try? values.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? values.decode([String: AppInfo].self) {
            self = .dictionary(value)
        } else if let value = try? values.decode([AppInfo].self) {
            self = .array(value)
        } else {
            self = .unknown
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .dictionary(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .unknown:
            try container.encodeNil()
        }
    }
}
