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

public struct ObvIdentityDetails: Equatable, Sendable {
    
    public let coreDetails: ObvIdentityCoreDetails
    public let photoURL: URL?
    
    private static let errorDomain = String(describing: ObvIdentityDetails.self)
    
    public init(coreDetails: ObvIdentityCoreDetails, photoURL: URL?) {
        self.coreDetails = coreDetails
        self.photoURL = photoURL
    }
    
    /// When removing the signed details (typically, as we are leaving a company's keycloak), we also remove the position and company from the details.
    public func removingSignedUserDetailsAndPositionAndCompany() throws -> ObvIdentityDetails {
        let newCoreDetails = try coreDetails.removingSignedUserDetailsAndPositionAndCompany()
        return ObvIdentityDetails(coreDetails: newCoreDetails,
                                  photoURL: photoURL)
    }

    public static func == (lhs: ObvIdentityDetails, rhs: ObvIdentityDetails) -> Bool {
        guard lhs.coreDetails == rhs.coreDetails else { return false }
        guard haveIdenticalPhotos(lhs: lhs, rhs: rhs) else { return false }
        return true
    }
    
    
    private static func haveIdenticalPhotos(lhs: ObvIdentityDetails, rhs: ObvIdentityDetails) -> Bool {
        switch (lhs.photoURL?.path, rhs.photoURL?.path) {
        case (.none, .none): return true
        case (.none, .some): return false
        case (.some, .none): return false
        case (.some(let path1), .some(let path2)):
            if path1 == path2 {
                return true
            } else {
                return FileManager.default.contentsEqual(atPath: path1, andPath: path2)
            }
        }
    }

    
    public func getDisplayNameWithStyle(_ style: ObvIdentityCoreDetails.DisplayNameStyle) -> String {
        return coreDetails.getDisplayNameWithStyle(style)
    }
    
}


/// Helper extension allowing to compute the differences between the trusted and published details of a contact.
/// Note that the engine automatically accepts changes made to the position or company.
public extension ObvIdentityDetails {
    
    struct Differences: OptionSet, Sendable {
        public let rawValue: Int
        public static let firstName = Differences(rawValue: 1 << 0)
        public static let lastName = Differences(rawValue: 1 << 1)
        public static let photo = Differences(rawValue: 1 << 2)
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }

    func differencesWith(_ other: Self) -> Differences {
        var differences: Differences = []
        if self.coreDetails.firstName != other.coreDetails.firstName { differences.insert(.firstName) }
        if self.coreDetails.lastName != other.coreDetails.lastName { differences.insert(.lastName) }
        if !Self.haveIdenticalPhotos(lhs: self, rhs: other) { differences.insert(.photo) }
        return differences
    }

}


extension ObvIdentityDetails: Codable {
    
    enum CodingKeys: String, CodingKey {
        case coreDetails = "details"
        case photoURL = "photo_url"
    }

    
    public init(_ data: Data) throws {
        let decoder = JSONDecoder()
        self = try decoder.decode(ObvIdentityDetails.self, from: data)
    }

    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coreDetails, forKey: .coreDetails)
        try container.encodeIfPresent(photoURL, forKey: .photoURL)
    }

    
    public func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let coreDetails = try values.decode(ObvIdentityCoreDetails.self, forKey: .coreDetails)
        let photoURL = try values.decodeIfPresent(URL.self, forKey: .photoURL)
        self.init(coreDetails: coreDetails, photoURL: photoURL)
    }

    
    static func jsonDecode(_ data: Data) throws -> ObvIdentityDetails {
        let decoder = JSONDecoder()
        return try decoder.decode(ObvIdentityDetails.self, from: data)
    }

}
