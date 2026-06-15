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
import ObvTypes
import ObvAppTypes
import ObvEncoder


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
    
    /// Part of the Id-based authentication process: used to request a challenge to the keycloak server
    struct APIQueryForKeycloakIdBasedAuthRequestChallenge {
        
        let keycloakUserId: String
        let nonce: Data

        var dataToSend: Data {
            [keycloakUserId.obvEncode(), nonce.obvEncode()].obvEncode().rawData
        }
        
    }
    
    /// Part of the Id-based authentication process
    struct APIResultForKeycloakIdBasedAuthRequestChallenge: Decodable, KeycloakManagerApiResult {
        
        let nonce: Data
        let challenge: Data
        
        
        private init (nonce: Data, challenge: Data) {
            self.nonce = nonce
            self.challenge = challenge
        }
        
        
        init(from decoder: Decoder) throws {
            assertionFailure("Since this particular response is not a JSON, this is not expected to be called")
            throw ObvError.malformedServerResponse
        }
        
        
        public enum PossibleReturnStatus: UInt8 {
            case ok = 0x00
            case parsingError = 0xfe
        }

        
        /// Override of the `KeycloakManagerApiResult` default implementation of
        /// `static func decode<T>(_ data: Data) throws -> T where T : Decodable`
        /// as, for this particular API result, the server does not return a JSON encoded value, but an ObvEncoded value.
        static func decode(_ data: Data) throws -> Self {
            guard let encodedOfList = ObvEncoded(withRawData: data) else { assertionFailure(); throw ObvError.decodingError }
            guard var listOfReturnedData = [ObvEncoded](encodedOfList) else { assertionFailure(); throw ObvError.decodingError }
            guard !listOfReturnedData.isEmpty else { assertionFailure(); throw ObvError.decodingError }
            let encodedServerReturnedStatus = listOfReturnedData.removeFirst()
            guard let decodedServerReturnedStatus = Data(encodedServerReturnedStatus),
                decodedServerReturnedStatus.count == 1 else {
                assertionFailure()
                throw ObvError.decodingError
            }
            let rawServerReturnedStatus: UInt8 = decodedServerReturnedStatus[decodedServerReturnedStatus.startIndex]
            guard let status = PossibleReturnStatus(rawValue: rawServerReturnedStatus) else { assertionFailure(); throw ObvError.decodingError }
            switch status {
            case .parsingError:
                assertionFailure()
                throw ObvError.parsingError
            case .ok:
                guard listOfReturnedData.count == 2 else {
                    assertionFailure()
                    throw ObvError.malformedServerResponse
                }
                guard let challenge = Data(listOfReturnedData[0]) else {
                    assertionFailure()
                    throw ObvError.malformedServerResponse
                }
                guard let nonce = Data(listOfReturnedData[1]) else {
                    assertionFailure()
                    throw ObvError.malformedServerResponse
                }
                return Self.init(nonce: nonce, challenge: challenge)
            }
        }
        
        enum ObvError: Error {
            case decodingError
            case parsingError
            case malformedServerResponse
        }
        
    }
    
    
    /// Part of the ID-based authentication process: carries the solved challenge response
    /// back to the Keycloak server in exchange for a session (access + refresh tokens).
    struct APIQueryForKeycloakIdBasedAuthRequestSession {
        
        let challengeResponse: Data
        let nonce: Data

        var dataToSend: Data {
            [challengeResponse.obvEncode(), nonce.obvEncode()].obvEncode().rawData
        }
        
    }

    
    /// Server response to the `getSession` request in the ID-based authentication flow.
    /// Contains the `access_token` and `refresh_token` that will be wrapped into an `OIDAuthState`.
    struct APIResultForKeycloakIdBasedAuthRequestSession: Decodable, KeycloakManagerApiResult {
        
        let accessToken: String
        let refreshToken: String

        /// When querying the `getSession` API during ID-based authentication, we can receive `permissionDenied`
        /// if ID-based authentication is not enabled for the user.
        enum PossibleReturnStatus: UInt8 {
            case ok = 0x00
            case permissionDenied = 0x0e
            case parsingError = 0xfe
            case generalError = 0xff
        }
        
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
        }

        /// Overrides the default `KeycloakManagerApiResult` implementation of `decode(_:)`.
        ///
        /// For this particular API result, the server does not return a raw JSON payload. Instead, it returns
        /// data encoded using the `ObvEncoded` format — a binary encoding specific to the Olvid protocol layer.
        ///
        /// The decoding process works as follows:
        /// 1. The raw `Data` is parsed as an `ObvEncoded` value, which wraps a list of encoded items.
        /// 2. The first item in the list is the server return status (a single `UInt8` byte): `0x00` for success,
        ///    `0xfe` for a parsing error, and `0xff` for a general error.
        /// 3. On success, the second (and only remaining) item is itself an `ObvEncoded` `Data`, which contains
        ///    the actual payload serialized as JSON.
        /// 4. That JSON `Data` is then decoded using a standard `JSONDecoder` into `Self`.
        static func decode(_ data: Data) throws -> Self {
            guard let encodedOfList = ObvEncoded(withRawData: data) else { assertionFailure(); throw ObvError.decodingError }
            guard var listOfReturnedData = [ObvEncoded](encodedOfList) else { assertionFailure(); throw ObvError.decodingError }
            guard !listOfReturnedData.isEmpty else { assertionFailure(); throw ObvError.decodingError }
            let encodedServerReturnedStatus = listOfReturnedData.removeFirst()
            guard let decodedServerReturnedStatus = Data(encodedServerReturnedStatus),
                decodedServerReturnedStatus.count == 1 else {
                assertionFailure()
                throw ObvError.decodingError
            }
            let rawServerReturnedStatus: UInt8 = decodedServerReturnedStatus[decodedServerReturnedStatus.startIndex]
            guard let status = PossibleReturnStatus(rawValue: rawServerReturnedStatus) else { assertionFailure(); throw ObvError.decodingError }
            switch status {
            case .parsingError:
                assertionFailure()
                throw ObvError.parsingError
            case .generalError:
                assertionFailure()
                throw ObvError.generalError
            case .permissionDenied:
                throw ObvError.permissionDenied
            case .ok:
                guard listOfReturnedData.count == 1 else {
                    assertionFailure()
                    throw ObvError.malformedServerResponse
                }
                guard let serializedAuthSession = Data(listOfReturnedData[0]) else { assertionFailure(); throw ObvError.decodingError }
                
                let jsonDecoder = JSONDecoder()
                let session = try jsonDecoder.decode(Self.self, from: serializedAuthSession)
                                
                return session
                
            }
        }
        
        enum ObvError: Error {
            case decodingError
            case parsingError
            case generalError
            case malformedServerResponse
            case permissionDenied
        }
        
    }
    
    
    /// The token pair returned by the `olvid-rest/getMagicSession` endpoint when a valid magic link is exchanged.
    struct APIResultForMagicLinkAuthRequest: Decodable, KeycloakManagerApiResult {
        let accessToken: String
        let refreshToken: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
        }

    }
    
    
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
    
    
    struct ApiQueryForTransferProof: Encodable {
        
        public let sessionNumber: ObvOwnedIdentityTransferSessionNumber
        public let sas: ObvOwnedIdentityTransferSas

        init(sessionNumber: ObvOwnedIdentityTransferSessionNumber, sas: ObvOwnedIdentityTransferSas) {
            self.sessionNumber = sessionNumber
            self.sas = sas
        }
        
        init(transferProofElements: ObvKeycloakTransferProofElements) {
            self.sessionNumber = transferProofElements.sessionNumber
            self.sas = transferProofElements.sas
        }
        
        enum CodingKeys: String, CodingKey {
            case sessionNumber = "session_id"
            case sas = "sas"
        }
        
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            let sessionNumberAsString = String(sessionNumber.digits)
            try container.encode(sessionNumberAsString, forKey: .sessionNumber)
            let sasAsString = String(sas.digits)
            try container.encode(sasAsString, forKey: .sas)
        }

        func jsonEncode() throws -> Data {
            let encoder = JSONEncoder()
            return try encoder.encode(self)
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
    
    
    struct ApiResultForTransferProofPath: Decodable, KeycloakManagerApiResult {
        
        let signature: String

        enum CodingKeys: String, CodingKey {
            case signature = "signature"
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
        let isTransferRestricted: Bool

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
            case isTransferRestricted = "transfer-restricted"
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
            self.isTransferRestricted = try values.decodeIfPresent(Bool.self, forKey: .isTransferRestricted) ?? false
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

extension OlvidWellKnownJson: KeycloakManagerApiResult {}
