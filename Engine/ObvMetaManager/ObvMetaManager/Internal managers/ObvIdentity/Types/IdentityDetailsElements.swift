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
import ObvCrypto
import ObvTypes
import ObvEncoder

/// This structure is used to communicate contact identity details informations between the protocol manager and the identity manager. It is also used within the protocol allowing to publish owned details as well as within the channel creation (when sending the ack).
/// The equivalent structure under Android is called JsonIdentityDetailsWithVersionAndPhoto.
public struct IdentityDetailsElements {
    
    public let version: Int
    public let coreDetails: ObvIdentityCoreDetails
    public let photoServerKeyAndLabel: PhotoServerKeyAndLabel?

    public init(version: Int, coreDetails: ObvIdentityCoreDetails, photoServerKeyAndLabel: PhotoServerKeyAndLabel?) {
        self.version = version
        self.coreDetails = coreDetails
        self.photoServerKeyAndLabel = photoServerKeyAndLabel
    }
    
    
    public func fieldsAreTheSameButVersionAndSignedDetailsAreNotConsidered(than other: IdentityDetailsElements) -> Bool {
        return self.coreDetails.fieldsAreTheSameAndSignedDetailsAreNotConsidered(than: other.coreDetails) && self.photoServerKeyAndLabel == other.photoServerKeyAndLabel
    }
    
}

extension IdentityDetailsElements: Codable {
    
    enum CodingKeys: String, CodingKey {
        case version = "version"
        case coreDetails = "details"
    }

    public init(_ data: Data) throws {
        let decoder = JSONDecoder()
        self = try decoder.decode(IdentityDetailsElements.self, from: data)
    }
    
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(coreDetails, forKey: .coreDetails)
        try photoServerKeyAndLabel?.encode(to: encoder)
    }
    
    
    public func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
    
    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .version)
        let coreDetails = try values.decode(ObvIdentityCoreDetails.self, forKey: .coreDetails)
        let photoServerKeyAndLabel = try? PhotoServerKeyAndLabel(from: decoder)
        self.init(version: version, coreDetails: coreDetails, photoServerKeyAndLabel: photoServerKeyAndLabel)
    }
    
    
    static func jsonDecode(_ data: Data) throws -> IdentityDetailsElements {
        let decoder = JSONDecoder()
        return try decoder.decode(IdentityDetailsElements.self, from: data)
    }

}
