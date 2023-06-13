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
import OlvidUtils
import JWS


public struct SignedObvKeycloakUserDetails {
    
    public let userDetails: ObvKeycloakUserDetails
    public let signedUserDetails: String
    
    public func identical(to other: SignedObvKeycloakUserDetails, acceptableTimestampsDifference: TimeInterval) -> Bool {
        self.userDetails.identical(to: other.userDetails, acceptableTimestampsDifference: acceptableTimestampsDifference)
    }
    
    public static func verifySignedUserDetails(_ signedUserDetails: String, with jwks: ObvJWKSet) throws -> (signedUserDetails: SignedObvKeycloakUserDetails, signatureVerificationKey: ObvJWK) {
        let (jsonPayload, signatureVerificationKey) = try JWSUtil.verifySignature(jwks: jwks, signature: signedUserDetails)
        let contactUserDetails = try ObvKeycloakUserDetails(jsonPayload)
        let signedUserDetails = self.init(userDetails: contactUserDetails, signedUserDetails: signedUserDetails)
        return (signedUserDetails, signatureVerificationKey)
    }

    public static func verifySignedUserDetails(_ signedUserDetails: String, with jwk: ObvJWK) throws -> SignedObvKeycloakUserDetails {
        let (jsonPayload, signatureVerificationKey) = try JWSUtil.verifySignature(signatureVerificationKey: jwk, signature: signedUserDetails)
        assert(signatureVerificationKey == jwk)
        let contactUserDetails = try ObvKeycloakUserDetails(jsonPayload)
        let signedUserDetails = self.init(userDetails: contactUserDetails, signedUserDetails: signedUserDetails)
        return signedUserDetails
    }

    private init(userDetails: ObvKeycloakUserDetails, signedUserDetails: String) {
        self.userDetails = userDetails
        self.signedUserDetails = signedUserDetails
    }
    
    public func getObvIdentityCoreDetails() throws -> ObvIdentityCoreDetails {
        return try ObvIdentityCoreDetails(firstName: userDetails.firstName,
                                          lastName: userDetails.lastName,
                                          company: userDetails.company,
                                          position: userDetails.position,
                                          signedUserDetails: signedUserDetails)
    }

    public var id: String { self.userDetails.id }
    public var identity: Data? { self.userDetails.identity }
    public var username: String? { self.userDetails.username }
    public var firstName: String? { self.userDetails.firstName }
    public var lastName: String? { self.userDetails.lastName }
    public var position: String? { self.userDetails.position }
    public var company: String? { self.userDetails.company }
    public var descriptiveCharacter: String? { self.userDetails.descriptiveCharacter }
    public var timestamp: Date? { self.userDetails.timestamp }
    
    public func toObvIdentityCoreDetails() throws -> ObvIdentityCoreDetails {
        try ObvIdentityCoreDetails(firstName: firstName, lastName: lastName, company: company, position: position, signedUserDetails: signedUserDetails)
    }

}


// MARK: - ObvKeycloakUserDetails

/// Corresponds to the `JsonKeycloakUserDetails` in Android
public struct ObvKeycloakUserDetails {
    
    public let id: String // This is the userId given by the keycloak server
    public let identity: Data?
    public let username: String?
    public let firstName: String?
    public let lastName: String?
    public let position: String?
    public let company: String?
    public let timestamp: Date?

    fileprivate func identical(to other: ObvKeycloakUserDetails, acceptableTimestampsDifference: TimeInterval) -> Bool {
        guard self.id == other.id &&
                self.identity == other.identity &&
                self.username == other.username &&
                self.firstName == other.firstName &&
                self.lastName ==  other.lastName &&
                self.position == other.position &&
                self.company == other.company
        else {
            return false
        }
        switch (self.timestamp, other.timestamp) {
        case (.none, .none):
            return true
        case (.none, .some), (.some, .none):
            return false
        case (.some(let t1), .some(let t2)):
            return abs(t1.timeIntervalSince(t2)) < acceptableTimestampsDifference
        }
    }
    

    /// A string made of one character, descriptive the user details
    public var descriptiveCharacter: String? {
        guard let character = [firstName, lastName]
                .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
                .filter({ !$0.isEmpty })
                .first?
                .first
        else { return nil }
        return String(character)
    }
    
    fileprivate init(id: String, identity: Data?, username: String?, firstName: String?, lastName: String?, position: String?, company: String?, timestamp: Date?) {
        self.id = id
        self.identity = identity
        self.username = username
        self.firstName = firstName
        self.lastName = lastName
        self.position = position
        self.company = company
        self.timestamp = timestamp
    }
    
    public func getCoreDetails() throws -> ObvIdentityCoreDetails {
        try ObvIdentityCoreDetails(firstName: firstName,
                                   lastName: lastName,
                                   company: company,
                                   position: position,
                                   signedUserDetails: nil)
    }
    
}

/// This struct is identifiable because it is used to display Keycloak search results in a SwiftUI interface. It is
/// comparable so as to sort these results within the same interface.
extension ObvKeycloakUserDetails: Codable, Identifiable, Hashable, Comparable {

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case identity = "identity"
        case username = "username"
        case firstName = "first-name"
        case lastName = "last-name"
        case position = "position"
        case company = "company"
        case timestamp = "timestamp"
    }

    fileprivate init(_ data: Data) throws {
        let decoder = JSONDecoder()
        self = try decoder.decode(ObvKeycloakUserDetails.self, from: data)
    }


    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(identity, forKey: .identity)
        try container.encodeIfPresent(username, forKey: .username)
        try container.encodeIfPresent(firstName, forKey: .firstName)
        try container.encodeIfPresent(lastName, forKey: .lastName)
        try container.encodeIfPresent(company, forKey: .company)
        try container.encodeIfPresent(position, forKey: .position)
        if let timestampInMs = timestamp?.epochInMs {
            try container.encode(timestampInMs, forKey: .timestamp)
        }
    }

    fileprivate func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }


    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let id = try values.decode(String.self, forKey: .id)
        let identity = (try values.decodeIfPresent(Data.self, forKey: .identity))
        let username = try values.decodeIfPresent(String.self, forKey: .username)
        let firstName = (try values.decodeIfPresent(String.self, forKey: .firstName))
        let lastName = try values.decodeIfPresent(String.self, forKey: .lastName)
        let company = try values.decodeIfPresent(String.self, forKey: .company)
        let position = try values.decodeIfPresent(String.self, forKey: .position)
        let timestamp: Date?
        if let timestampInMs = try values.decodeIfPresent(Int.self, forKey: .timestamp) {
            timestamp = Date(epochInMs: Int64(timestampInMs))
        } else {
            timestamp = nil
        }
        self.init(id: id, identity: identity, username: username, firstName: firstName, lastName: lastName, position: position, company: company, timestamp: timestamp)
    }


    fileprivate static func jsonDecode(_ data: Data) throws -> ObvKeycloakUserDetails {
        let decoder = JSONDecoder()
        return try decoder.decode(ObvKeycloakUserDetails.self, from: data)
    }

    public static func < (lhs: ObvKeycloakUserDetails, rhs: ObvKeycloakUserDetails) -> Bool {
        let lhsFullDisplayName = lhs.fullDisplayName
        let rhsFullDisplayName = lhs.fullDisplayName
        let comparisonResult = lhsFullDisplayName.compare(rhsFullDisplayName, options: .caseInsensitive)
        return comparisonResult == .orderedAscending
    }

    public var fullDisplayName: String {
        guard let coreDetails = try? ObvIdentityCoreDetails(firstName: firstName, lastName: lastName, company: company, position: position, signedUserDetails: nil) else { return "" }
        return coreDetails.getFullDisplayName()
    }

}
