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
import ObvEngine

struct OlvidURL {
    
    let url: URL
    let category: Category
    
    enum Category {
        case invitation(urlIdentity: ObvURLIdentity)
        case mutualScan(mutualScanURL: ObvMutualScanUrl)
        case configuration(serverAndAPIKey: ServerAndAPIKey?, betaConfiguration: BetaConfiguration?, keycloakConfig: KeycloakConfiguration?)
        case openIdRedirect
    }
        
    init?(urlRepresentation: URL) {
        guard urlRepresentation.scheme == "https" else { assertionFailure(); return nil }
        guard let urlComponents = URLComponents(url: urlRepresentation, resolvingAgainstBaseURL: true) else { assertionFailure(); return nil }
        switch urlComponents.host {
        case ObvMessengerConstants.Host.forConfigurations:
            if let serverAndAPIKey = ServerAndAPIKey(urlRepresentation: urlRepresentation) {
                // For now, if the URL representation decodes to a ServerAndAPIKey, we do not expect to find a BetaConfiguration nor a KeycloakConfiguration
                assert(BetaConfiguration(urlRepresentation: urlRepresentation) == nil && KeycloakConfiguration(urlRepresentation: urlRepresentation) == nil)
                self.category = .configuration(serverAndAPIKey: serverAndAPIKey, betaConfiguration: nil, keycloakConfig: nil)
                self.url = urlRepresentation
                return
            } else if let betaConfiguration = BetaConfiguration(urlRepresentation: urlRepresentation) {
                // For now, if the URL representation decodes to a BetaConfiguration, we do not expect to find a ServerAndAPIKey nor a KeycloakConfiguration
                assert(ServerAndAPIKey(urlRepresentation: urlRepresentation) == nil && KeycloakConfiguration(urlRepresentation: urlRepresentation) == nil)
                self.category = .configuration(serverAndAPIKey: nil, betaConfiguration: betaConfiguration, keycloakConfig: nil)
                self.url = urlRepresentation
                return
            } else if let keycloakConfig = KeycloakConfiguration(urlRepresentation: urlRepresentation) {
                // For now, if the URL representation decodes to a KeycloakConfiguration, we do not expect to find a ServerAndAPIKey nor a BetaConfiguration
                assert(ServerAndAPIKey(urlRepresentation: urlRepresentation) == nil && BetaConfiguration(urlRepresentation: urlRepresentation) == nil)
                self.category = .configuration(serverAndAPIKey: nil, betaConfiguration: nil, keycloakConfig: keycloakConfig)
                self.url = urlRepresentation
                return
            } else {
                assertionFailure()
                return nil
            }
        case ObvMessengerConstants.Host.forInvitations:
            if let mutualScanURL = ObvMutualScanUrl(urlRepresentation: urlRepresentation) {
                self.category = .mutualScan(mutualScanURL: mutualScanURL)
                self.url = urlRepresentation
                return
            } else if let urlIdentity = ObvURLIdentity(urlRepresentation: urlRepresentation) {
                self.category = .invitation(urlIdentity: urlIdentity)
                self.url = urlRepresentation
                return
            } else {
                assertionFailure()
                return nil
            }
        case ObvMessengerConstants.Host.forOpenIdRedirect:
            self.category = .openIdRedirect
            self.url = urlRepresentation
            return
        default:
            assertionFailure()
            return nil
        }
    }

}


/// This struct represents custom settings that can be scanned for beta testing.
/// For now, we do not support "skipSas" nor "scaledTurn". We only support `beta`,
/// which can allow a standard user to access the same settings than a TestFlight user.
struct BetaConfiguration: Decodable, CodableOlvidURL {
    
    let beta: Bool
    
    enum CodingKeys: String, CodingKey {
        case settings = "settings"
        case beta = "beta"
    }
    
    init(beta: Bool) {
        self.beta = beta
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let container = try values.nestedContainer(keyedBy: CodingKeys.self, forKey: .settings)
        self.beta = try container.decodeIfPresent(Bool.self, forKey: .beta) ?? false
    }

}


struct ServerAndAPIKey: Codable, Equatable, CodableOlvidURL {

    let server: URL
    let apiKey: UUID
    
    enum CodingKeys: String, CodingKey {
        case server = "server"
        case apiKey = "apikey"
    }

}


struct KeycloakConfiguration: Decodable, CodableOlvidURL, Equatable {
    
    let serverURL: URL // Keycloak server URL
    let clientId: String
    let clientSecret: String?
    
    enum CodingKeys: String, CodingKey {
        case serverURL = "server"
        case clientId = "cid"
        case clientSecret = "secret"
        case keycloak = "keycloak"
    }

    init(serverURL: URL, clientId: String, clientSecret: String?) {
        self.serverURL = serverURL
        self.clientId = clientId
        self.clientSecret = clientSecret
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let container = try values.nestedContainer(keyedBy: CodingKeys.self, forKey: .keycloak)
        do {
            self.serverURL = try container.decode(URL.self, forKey: .serverURL)
        } catch {
            // It might be the case that the string describing the URL has spaces in it, or accents. We try to be resilient here.
            let serverURLAsString = try container.decode(String.self, forKey: .serverURL)
            guard let components = NSURLComponents(string: serverURLAsString) else { throw error }
            guard let urlFromComponents = components.url else { throw error }
            self.serverURL = urlFromComponents
        }
        self.clientId = try container.decode(String.self, forKey: .clientId)
        self.clientSecret = try container.decodeIfPresent(String.self, forKey: .clientSecret)
    }

}


// MARK: - CodableOlvidURL protocol

fileprivate protocol CodableOlvidURL: Decodable {}

extension CodableOlvidURL {
    
    static func jsonDecode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        return try decoder.decode(Self.self, from: data)
    }

    init?(urlRepresentation: URL) {
        guard let components = URLComponents(url: urlRepresentation, resolvingAgainstBaseURL: false) else { return nil }
        let rawBase64: String
        do {
            if let fragment = components.fragment {
                rawBase64 = fragment
            } else {
                var path = components.path
                path.removeFirst()
                rawBase64 = path
            }
        }
        let base64EncodedString = rawBase64
            .replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: "-", with: "+")
            .padding(toLength: ((rawBase64.count+3)/4)*4, withPad: "====", startingAt: 0)
        guard let raw = Data(base64Encoded: base64EncodedString) else { return nil }
        guard let item = try? Self.jsonDecode(raw) else { return nil }
        self = item
    }
    
}
