/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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


/// The Decodable conformance is used when decoding an Olvid URL.
public struct ObvKeycloakConfigurationAndServer: Decodable {
    
    public let distributionServerURL: URL // Distribution server
    public let keycloakConfiguration: ObvKeycloakConfiguration
    
    enum CodingKeys: String, CodingKey {
        case distributionServerURL = "server"
        case keycloakConfiguration = "keycloak"
    }

    public init(distributionServerURL: URL, keycloakConfiguration: ObvKeycloakConfiguration) {
        self.distributionServerURL = distributionServerURL
        self.keycloakConfiguration = keycloakConfiguration
    }
    
}


public struct ObvKeycloakConfiguration: Codable, Equatable {
    
    public let keycloakServerURL: URL // Keycloak server URL
    public let clientId: String
    public let clientSecret: String?
    
    enum CodingKeys: String, CodingKey {
        case keycloakServerURL = "server"
        case clientId = "cid"
        case clientSecret = "secret"
    }

    public init(keycloakServerURL: URL, clientId: String, clientSecret: String?) {
        self.keycloakServerURL = keycloakServerURL
        self.clientId = clientId
        self.clientSecret = clientSecret
    }
    
    
    /// Needs to be codable as we encode a keycloak configuration during a profile transfer when the profile is keycloak-managed and the keycloak enforces transfer protection
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keycloakServerURL, forKey: .keycloakServerURL)
        try container.encode(clientId, forKey: .clientId)
        try container.encodeIfPresent(clientSecret, forKey: .clientSecret)
    }
    

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        do {
            self.keycloakServerURL = try values.decode(URL.self, forKey: .keycloakServerURL)
        } catch {
            // It might be the case that the string describing the URL has spaces in it, or accents. We try to be resilient here.
            let serverURLAsString = try values.decode(String.self, forKey: .keycloakServerURL)
            guard let components = NSURLComponents(string: serverURLAsString) else { throw error }
            guard let urlFromComponents = components.url else { throw error }
            self.keycloakServerURL = urlFromComponents
        }
        self.clientId = try values.decode(String.self, forKey: .clientId)
        self.clientSecret = try values.decodeIfPresent(String.self, forKey: .clientSecret)
    }
    
    
    public func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
    
    
    public static func jsonDecode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        return try decoder.decode(Self.self, from: data)
    }

}
