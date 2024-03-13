/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import ObvTypes


struct WellKnownJSON: Decodable {
    
    public let serverConfig: WellKnownServerConfigJSON
    public let appInfo: [String: AppInfo]
    
    enum CodingKeys: String, CodingKey {
        case serverConfig = "server"
        case appInfo = "app"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.serverConfig = try values.decode(WellKnownServerConfigJSON.self, forKey: .serverConfig)
        self.appInfo = try values.decode([String: AppInfo].self, forKey: .appInfo)
    }

    static public func decode(_ data: Data) throws -> WellKnownJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(WellKnownJSON.self, from: data)
    }

}



struct WellKnownServerConfigJSON: Decodable {
    
    public let webSocketURL: URL
    public let turnServerURLs: [String]
    
    enum CodingKeys: String, CodingKey {
        case webSocketURL = "ws_server"
        case turnServerURLs = "turn_servers"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.webSocketURL = try values.decode(URL.self, forKey: .webSocketURL)
        // REMARK Encode nil and [] as []
        self.turnServerURLs = try values.decodeIfPresent([String].self, forKey: .turnServerURLs) ?? []
    }

    static func jsonDecode(_ data: Data) throws -> WellKnownServerConfigJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(WellKnownServerConfigJSON.self, from: data)
    }

    
}
