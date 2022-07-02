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

struct ObvGroupCoreDetailsForMigrationTov12: Equatable {
    
    public let name: String
    public let description: String?
    
    private static let errorDomain = "ObvGroupCoreDetailsForMigrationTov12"
    
    public init(name: String, description: String?) {
        self.name = name
        self.description = description
    }
}


// MARK: - Codable

extension ObvGroupCoreDetailsForMigrationTov12: Codable {
    
    enum CodingKeys: String, CodingKey {
        case name = "name"
        case description = "description"
    }
    
    
    public init(_ data: Data) throws {
        let decoder = JSONDecoder()
        self = try decoder.decode(ObvGroupCoreDetailsForMigrationTov12.self, from: data)
    }
    
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
    }
    
    
    public func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
    
    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let name = (try values.decode(String.self, forKey: .name))
        let description = try values.decodeIfPresent(String.self, forKey: .description)
        self.init(name: name, description: description)
    }
    
}
