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

public struct PollCandidateJSON: Codable, Equatable, Hashable, Sendable {
    public let uuid: UUID
    public let text: String
    
    enum CodingKeys: String, CodingKey {
        case uuid = "uuid"
        case text = "t"
    }
    
    public init(uuid: UUID,
                text: String) {
        self.uuid = uuid
        self.text = text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
                
        self.uuid = try container.decode(UUID.self, forKey: .uuid)
        self.text = try container.decode(String.self, forKey: .text)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.uuid, forKey: .uuid)
        try container.encode(self.text, forKey: .text)
    }

    public func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        return data
    }

    static func jsonDecode(_ data: Data) throws -> PollCandidateJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(PollCandidateJSON.self, from: data)
    }
}
