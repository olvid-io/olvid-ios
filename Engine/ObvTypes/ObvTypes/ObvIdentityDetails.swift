/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

public struct ObvIdentityDetails: Equatable {
    
    public let coreDetails: ObvIdentityCoreDetails
    public let photoURL: URL?
    
    private static let errorDomain = String(describing: ObvIdentityDetails.self)
    
    public init(coreDetails: ObvIdentityCoreDetails, photoURL: URL?) {
        self.coreDetails = coreDetails
        self.photoURL = photoURL
    }
    
    public func removingSignedUserDetails() throws -> ObvIdentityDetails {
        let newCoreDetails = try coreDetails.removingSignedUserDetails()
        return ObvIdentityDetails(coreDetails: newCoreDetails,
                                  photoURL: photoURL)
    }

    public static func == (lhs: ObvIdentityDetails, rhs: ObvIdentityDetails) -> Bool {
        guard lhs.coreDetails == rhs.coreDetails else { return false }
        switch (lhs.photoURL?.path, rhs.photoURL?.path) {
        case (.none, .none): break
        case (.none, .some): return false
        case (.some, .none): return false
        case (.some(let path1), .some(let path2)):
            guard FileManager.default.contentsEqual(atPath: path1, andPath: path2) else {
                return false
            }
        }
        return true
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

    
    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let coreDetails = try values.decode(ObvIdentityCoreDetails.self, forKey: .coreDetails)
        let photoURL = try values.decodeIfPresent(URL.self, forKey: .photoURL)
        self.init(coreDetails: coreDetails, photoURL: photoURL)
    }

    
    static func decode(_ data: Data) throws -> ObvIdentityDetails {
        let decoder = JSONDecoder()
        return try decoder.decode(ObvIdentityDetails.self, from: data)
    }

}
