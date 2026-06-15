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


public struct DiscussionSharedConfigurationForKeycloakGroupJSON {
    
    public let expiration: ExpirationJSON?

    private init(expiration: ExpirationJSON) {
        self.expiration = expiration
    }

}


extension DiscussionSharedConfigurationForKeycloakGroupJSON: Decodable {
    
    enum CodingKeys: String, CodingKey {
        case expiration = "exp"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.expiration = try values.decodeIfPresent(ExpirationJSON.self, forKey: .expiration)
    }

}


extension DiscussionSharedConfigurationForKeycloakGroupJSON {

    public static func jsonDecode(_ data: Data) throws -> DiscussionSharedConfigurationForKeycloakGroupJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(DiscussionSharedConfigurationForKeycloakGroupJSON.self, from: data)
    }
    
}
