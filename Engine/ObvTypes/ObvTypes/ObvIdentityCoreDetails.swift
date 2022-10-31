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

/// This types corresponds to the `JsonIdentityDetails` of Android
public struct ObvIdentityCoreDetails: Equatable {
    
    public let firstName: String?
    public let lastName: String?
    public let company: String?
    public let position: String?
    public let signedUserDetails: String? /// this is a JWT, non null when the identity is managed by a keycloak server
    
    private static let errorDomain = String(describing: ObvIdentityCoreDetails.self)
    
    private static func makeError(message: String) -> Error { NSError(domain: errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    public func removingSignedUserDetails() throws -> ObvIdentityCoreDetails {
        try ObvIdentityCoreDetails(firstName: firstName,
                                   lastName: lastName,
                                   company: company,
                                   position: position,
                                   signedUserDetails: nil)
    }
    
    public func fieldsAreTheSameAndSignedDetailsAreNotConsidered(than other: ObvIdentityCoreDetails) -> Bool {
        firstName == other.firstName &&
            lastName == other.lastName &&
            company == other.company &&
            position == other.position
    }    
    
    public init(firstName: String?, lastName: String?, company: String?, position: String?, signedUserDetails: String?) throws {
        guard ObvIdentityCoreDetails.areAcceptable(firstName: firstName, lastName: lastName) else {
            throw Self.makeError(message: "ObvIdentityCoreDetails are not acceptable")
        }
        self.firstName = firstName?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).mapToNilIfZeroLength()
        self.lastName = lastName?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).mapToNilIfZeroLength()
        self.company = company?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).mapToNilIfZeroLength()
        self.position = position?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).mapToNilIfZeroLength()
        self.signedUserDetails = signedUserDetails
    }
    
    private static func areAcceptable(firstName: String?, lastName: String?) -> Bool {
        let _firstName = firstName?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).mapToNilIfZeroLength()
        let _lastName = lastName?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).mapToNilIfZeroLength()
        return (_firstName, _lastName) != (nil, nil)
    }

    public func positionAtCompany() -> String {
        switch (position, company) {
        case (nil, nil):
            return ""
        case (.some, nil):
            return position!
        case (nil, .some):
            return company!
        case (.some, .some):
            return [position!, company!].joined(separator: " @ ")
        }
    }

    public func getFullDisplayName() -> String {
        let _firstName = firstName ?? ""
        let _lastName = lastName ?? ""
        let firstNameThenLastName = [_firstName, _lastName].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        if let positionAtCompany = positionAtCompany().mapToNilIfZeroLength() {
            return [firstNameThenLastName, "(\(positionAtCompany))"].joined(separator: " ")
        } else {
            return firstNameThenLastName
        }
    }

    public var personNameComponents: PersonNameComponents {
        var pnc = PersonNameComponents()
        pnc.familyName = lastName
        pnc.givenName = firstName
        return pnc
    }
}


extension ObvIdentityCoreDetails: Codable {
    
    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case company = "company"
        case position = "position"
        case signedUserDetails = "signed_user_details"
    }
    

    public init(_ data: Data) throws {
        let decoder = JSONDecoder()
        self = try decoder.decode(ObvIdentityCoreDetails.self, from: data)
    }
    
    
    public func encode(to encoder: Encoder) throws {
        guard firstName != nil || lastName != nil else {
            let message = "Both firstName and lastName are nil, which is not allowed."
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: ObvIdentityCoreDetails.errorDomain, code: 0, userInfo: userInfo)
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(firstName, forKey: .firstName)
        try container.encodeIfPresent(lastName, forKey: .lastName)
        try container.encodeIfPresent(company, forKey: .company)
        try container.encodeIfPresent(position, forKey: .position)
        try container.encodeIfPresent(signedUserDetails, forKey: .signedUserDetails)
    }
    
    
    public func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let firstName = (try values.decodeIfPresent(String.self, forKey: .firstName))
        let lastName = try values.decodeIfPresent(String.self, forKey: .lastName)
        let company = try values.decodeIfPresent(String.self, forKey: .company)
        let position = try values.decodeIfPresent(String.self, forKey: .position)
        let signedUserDetails = try values.decodeIfPresent(String.self, forKey: .signedUserDetails)
        try self.init(firstName: firstName, lastName: lastName, company: company, position: position, signedUserDetails: signedUserDetails)
    }
    
    
    public static func jsonDecode(_ data: Data) throws -> ObvIdentityCoreDetails {
        let decoder = JSONDecoder()
        return try decoder.decode(ObvIdentityCoreDetails.self, from: data)
    }
    
}


private extension String {
    
    func mapToNilIfZeroLength() -> String? {
        return self.isEmpty ? nil : self
    }
    
}
