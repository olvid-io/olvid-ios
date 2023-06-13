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
import ObvTypes


protocol KeycloakManagerApiResult {
    
    static func decode(_ data: Data) throws -> Self

}

extension KeycloakManagerApiResult {
    
    static func decode<T: Decodable>(_ data: Data) throws -> T {
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }
    
}

extension KeycloakManager {
    
    
    struct APIQueryForGroupsPath: Encodable {
    
        let latestGetGroupsTimestamp: Date // Server timestamp, stored within the engine
        
        init(latestGetGroupsTimestamp: Date) {
            let oneHour = TimeInterval(hours: 1)
            self.latestGetGroupsTimestamp = latestGetGroupsTimestamp.addingTimeInterval(-oneHour)
        }

        enum CodingKeys: String, CodingKey {
            case latestLocalRevocationListTimestamp = "timestamp"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(latestGetGroupsTimestamp.epochInMs, forKey: .latestLocalRevocationListTimestamp)
        }

        func jsonEncode() throws -> Data {
            let encoder = JSONEncoder()
            return try encoder.encode(self)
        }

    }
    
    
    struct ApiResultForGroupsPath: Decodable, KeycloakManagerApiResult {

        let signedGroupBlobs: Set<String>
        let signedGroupDeletions: Set<String>
        let signedGroupKicks: Set<String>
        let currentServerTimestamp: Date
        
        enum CodingKeys: String, CodingKey {
            case signedGroupBlobs = "signed_group_blobs"
            case signedGroupDeletions = "signed_group_deletions"
            case signedGroupKicks = "signed_group_kicks"
            case currentServerTimestamp = "current_timestamp"
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            debugPrint(values.allKeys)
            self.signedGroupBlobs = try values.decodeIfPresent(Set<String>.self, forKey: .signedGroupBlobs) ?? Set<String>()
            self.signedGroupDeletions = try values.decodeIfPresent(Set<String>.self, forKey: .signedGroupDeletions) ?? Set<String>()
            self.signedGroupKicks = try values.decodeIfPresent(Set<String>.self, forKey: .signedGroupKicks) ?? Set<String>()
            let rawCurrentServerTimestamp = try values.decode(Int.self, forKey: .currentServerTimestamp)
            self.currentServerTimestamp = Date(epochInMs: Int64(rawCurrentServerTimestamp))
        }
        
    }
    

    struct ApiQueryForMePath: Encodable {

        let latestLocalRevocationListTimestamp: Date // Server timestamp, stored within the engine

        init(latestLocalRevocationListTimestamp: Date) {
            let oneHour = TimeInterval(hours: 1)
            self.latestLocalRevocationListTimestamp = latestLocalRevocationListTimestamp.addingTimeInterval(-oneHour)
        }

        enum CodingKeys: String, CodingKey {
            case latestLocalRevocationListTimestamp = "timestamp"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(latestLocalRevocationListTimestamp.epochInMs, forKey: .latestLocalRevocationListTimestamp)
        }

        func jsonEncode() throws -> Data {
            let encoder = JSONEncoder()
            return try encoder.encode(self)
        }

    }


    struct ApiResultForMePath: Decodable, KeycloakManagerApiResult {

        let signature: String
        let server: URL
        let revocationAllowed: Bool
        let apiKey: UUID?
        let selfRevocationTestNonce: String?
        let pushTopics: Set<String>
        let signedRevocations: [String]?
        let currentServerTimestamp: Date?
        let minimumIOSBuildVersion: Int?

        enum CodingKeys: String, CodingKey {
            case signature = "signature"
            case apiKey = "api-key"
            case server = "server"
            case revocationAllowed = "revocation-allowed"
            case selfRevocationTestNonce = "nonce"
            case pushTopics = "push-topics"
            case signedRevocations = "signed-revocations"
            case currentServerTimestamp = "current-timestamp"
            case minimumBuildVersions = "min-build-versions"
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            signature = try values.decode(String.self, forKey: .signature)
            let serverAsString = try values.decode(String.self, forKey: .server)
            guard let _server = URL(string: serverAsString) else { throw KeycloakManager.makeError(message: "Could not turn string URL into URL") }
            self.server = _server
            revocationAllowed = try values.decode(Bool.self, forKey: .revocationAllowed)
            self.apiKey = try values.decodeIfPresent(UUID.self, forKey: .apiKey)
            self.selfRevocationTestNonce = try values.decodeIfPresent(String.self, forKey: .selfRevocationTestNonce)
            self.pushTopics = Set(try values.decodeIfPresent([String].self, forKey: .pushTopics) ?? [])
            self.signedRevocations = try values.decodeIfPresent([String].self, forKey: .signedRevocations)
            if let rawCurrentServerTimestamp = try values.decodeIfPresent(Int.self, forKey: .currentServerTimestamp) {
                self.currentServerTimestamp = Date(epochInMs: Int64(rawCurrentServerTimestamp))
            } else {
                self.currentServerTimestamp = nil
            }
            let minimumBuildVersions = try values.decodeIfPresent([String: Int].self, forKey: .minimumBuildVersions) ?? [:]
            self.minimumIOSBuildVersion = minimumBuildVersions["ios"]
        }
    }


    struct ApiResultForGetKeyPath: Decodable, KeycloakManagerApiResult {
        let signature: String
    }


    struct ApiResultForPutKeyPath: Decodable, KeycloakManagerApiResult {}


    struct ApiResultForSearchPath: Decodable, KeycloakManagerApiResult {
        let userDetails: [ObvKeycloakUserDetails]?
        let numberOfResultsOnServer: Int?
        let errorCode: Int?

        enum CodingKeys: String, CodingKey {
            case userDetails = "results"
            case errorCode = "error"
            case numberOfResultsOnServer = "count"
        }
    }

    struct ApiResultForRevocationTestPath: Decodable, KeycloakManagerApiResult {
        let isRevoked: Bool

        static func decode(_ data: Data) throws -> ApiResultForRevocationTestPath {
            guard data.count == 1 else { throw KeycloakManager.makeError(message: "Unexpected value returned by the server for the revocation test") }
            switch data.first! {
            case 0x00:
                return ApiResultForRevocationTestPath(isRevoked: false)
            case 0x01:
                return ApiResultForRevocationTestPath(isRevoked: true)
            default:
                throw KeycloakManager.makeError(message: "Unexpected byte returned by the server for the revocation test")
            }
        }

    }
}
