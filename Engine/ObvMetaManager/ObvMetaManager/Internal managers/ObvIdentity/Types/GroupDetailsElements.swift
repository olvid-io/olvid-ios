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
import ObvCrypto
import ObvTypes
import ObvEncoder

/// This structure is used within the protocol allowing to publish group details.
public struct GroupDetailsElements: Equatable {

    public let version: Int
    public let coreDetails: ObvGroupCoreDetails
    public let photoServerKeyAndLabel: PhotoServerKeyAndLabel?

    public init(version: Int, coreDetails: ObvGroupCoreDetails, photoServerKeyAndLabel: PhotoServerKeyAndLabel?) {
        self.version = version
        self.coreDetails = coreDetails
        self.photoServerKeyAndLabel = photoServerKeyAndLabel
    }

    public func withPhotoServerKeyAndLabel(_ photoServerKeyAndLabel: PhotoServerKeyAndLabel?) -> GroupDetailsElements {
        GroupDetailsElements(version: self.version, coreDetails: self.coreDetails, photoServerKeyAndLabel: photoServerKeyAndLabel)
    }

}


extension GroupDetailsElements: Codable {

    enum CodingKeys: String, CodingKey {
        case version = "version"
        case coreDetails = "details"
    }

    
    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(coreDetails, forKey: .coreDetails)
        try photoServerKeyAndLabel?.encode(to: encoder)
    }
    
    public init(_ data: Data) throws {
        let decoder = JSONDecoder()
        self = try decoder.decode(GroupDetailsElements.self, from: data)
    }


    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .version)
        let coreDetails = try values.decode(ObvGroupCoreDetails.self, forKey: .coreDetails)
        let photoServerKeyAndLabel = try? PhotoServerKeyAndLabel(from: decoder)
        self.init(version: version, coreDetails: coreDetails, photoServerKeyAndLabel: photoServerKeyAndLabel)
    }


    static func decode(_ data: Data) throws -> GroupDetailsElements {
        let decoder = JSONDecoder()
        return try decoder.decode(GroupDetailsElements.self, from: data)
    }

}

/// This structure is used to communicate group details informations between the protocol manager and the identity manager.
public struct GroupDetailsElementsWithPhoto {

    public let groupDetailsElements: GroupDetailsElements
    public let photoURL: URL?
    
    public var version: Int {
        groupDetailsElements.version
    }
    public var coreDetails: ObvGroupCoreDetails {
        groupDetailsElements.coreDetails
    }
    public var photoServerKeyAndLabel: PhotoServerKeyAndLabel? {
        groupDetailsElements.photoServerKeyAndLabel
    }
    
    public var obvGroupDetails: ObvGroupDetails {
        ObvGroupDetails(coreDetails: coreDetails, photoURL: photoURL)
    }
    
    public init(groupDetailsElements: GroupDetailsElements, photoURL: URL?) {
        self.groupDetailsElements = groupDetailsElements
        self.photoURL = photoURL
    }
    
    public init(coreDetails: ObvGroupCoreDetails, version: Int, photoServerKeyAndLabel: PhotoServerKeyAndLabel?, photoURL: URL?) {
        self.groupDetailsElements = GroupDetailsElements(version: version, coreDetails: coreDetails, photoServerKeyAndLabel: photoServerKeyAndLabel)
        self.photoURL = photoURL
    }

    /// This method allows to compare two `GroupDetailsElementsWithPhoto` instances without considering the version number.
    /// This is typically used within the app to decide whether to show two cards or only one in the Single Group view.
    public func hasIdenticalContent(as other: GroupDetailsElementsWithPhoto) -> Bool {
        guard self.coreDetails == other.coreDetails else { return false }
        guard hasIdenticalPhoto(as: other) else { return false }
        return true
    }
    
    public func hasIdenticalPhoto(as other: GroupDetailsElementsWithPhoto) -> Bool {
        return hasIdenticalPhotoThanPhotoAtURL(other.photoURL)
    }
    
    public func hasIdenticalPhotoThanPhotoAtURL(_ otherURL: URL?) -> Bool {
        switch (self.photoURL?.path, otherURL?.path) {
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
