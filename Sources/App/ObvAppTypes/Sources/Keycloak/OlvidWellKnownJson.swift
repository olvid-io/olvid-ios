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


/// Decoded representation of the Olvid-specific well-known document served at
/// `<keycloakServerURL>/.well-known/olvid`.
///
/// This document advertises optional server capabilities (e.g. ID-based authentication)
/// and the minimum supported Olvid build versions per platform.
public struct OlvidWellKnownJson {
    
    public let supportsIdBasedAuth: Bool
    public let apiVersion: Int?
    public let minBuildVersions: OlvidWellKnownMinVersionsJson?
    
    /// Minimum build versions required by this server, per client platform.
    /// If `nil`, the server does not enforce any minimum version.
    public struct OlvidWellKnownMinVersionsJson {
        public let android: Int?
        public let iOS: Int?
        public let desktop: Int?
        public let daemon: Int?
        
    }

}


// MARK: - Implementing Decodable

extension OlvidWellKnownJson.OlvidWellKnownMinVersionsJson: Decodable {
    
    enum CodingKeys: String, CodingKey {
        case android = "android"
        case iOS = "ios"
        case desktop = "desktop"
        case daemon = "daemon"
    }

}

extension OlvidWellKnownJson: Decodable {
        
    enum CodingKeys: String, CodingKey {
        case supportsIdBasedAuth = "supportIdentityAuthentication"
        case apiVersion = "apiVersion"
        case minBuildVersions = "minBuildVersions"
    }
    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.supportsIdBasedAuth = try values.decodeIfPresent(Bool.self, forKey: .supportsIdBasedAuth) ?? false
        self.apiVersion = try values.decodeIfPresent(Int.self, forKey: .apiVersion)
        self.minBuildVersions = try values.decodeIfPresent(OlvidWellKnownMinVersionsJson.self, forKey: .minBuildVersions)
    }

}
