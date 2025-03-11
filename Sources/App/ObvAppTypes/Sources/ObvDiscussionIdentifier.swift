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
import ObvTypes
import ObvEncoder


/// This type uniquely identifies a discussion.
///
/// It shall be used instead of the legacy type `DiscussionIdentifier` defined within the app.
public enum ObvDiscussionIdentifier: Equatable, Hashable {
    
    case oneToOne(id: ObvContactIdentifier)
    case groupV1(id: ObvGroupV1Identifier)
    case groupV2(id: ObvGroupV2Identifier)
    
    public var ownedCryptoId: ObvCryptoId {
        switch self {
        case .oneToOne(let id):
            id.ownedCryptoId
        case .groupV1(let id):
            id.ownedCryptoId
        case .groupV2(let id):
            id.ownedCryptoId
        }
    }
    
}


// MARK: - Implementing ObvCodable, used by LosslessStringConvertible

extension ObvDiscussionIdentifier: ObvCodable {
    
    public func obvEncode() -> ObvEncoded {
        switch self {
        case .oneToOne(let id):
            return [self.discussionIdentifierRaw.obvEncode(), id.obvEncode()].obvEncode()
        case .groupV1(let id):
            return [self.discussionIdentifierRaw.obvEncode(), id.obvEncode()].obvEncode()
        case .groupV2(let id):
            return [self.discussionIdentifierRaw.obvEncode(), id.obvEncode()].obvEncode()
        }
    }
    
    
    public init?(_ obvEncoded: ObvEncoded) {
        guard let encodeds = [ObvEncoded](obvEncoded, expectedCount: 2) else {
            assertionFailure()
            return nil
        }
        do {
            let discussionIdentifierRaw: DiscussionIdentifierRaw = try encodeds[0].obvDecode()
            switch discussionIdentifierRaw {
            case .oneToOne:
                let id: ObvContactIdentifier = try encodeds[1].obvDecode()
                self = .oneToOne(id: id)
            case .groupV1:
                let id: ObvGroupV1Identifier = try encodeds[1].obvDecode()
                self = .groupV1(id: id)
            case .groupV2:
                let id: ObvGroupV2Identifier = try encodeds[1].obvDecode()
                self = .groupV2(id: id)
            }
        } catch {
            assertionFailure()
            return nil
        }
    }
    
    
    private var discussionIdentifierRaw: DiscussionIdentifierRaw {
        switch self {
        case .oneToOne: return .oneToOne
        case .groupV1: return .groupV1
        case .groupV2: return .groupV2
        }
    }

    
    private enum DiscussionIdentifierRaw: String, ObvCodable {
        
        case oneToOne = "o2o"
        case groupV1 = "gv1"
        case groupV2 = "gv2"
        
        func obvEncode() -> ObvEncoded {
            self.rawValue.obvEncode()
        }
        
        init?(_ obvEncoded: ObvEncoded) {
            guard let rawValue: String = try? obvEncoded.obvDecode() else {
                assertionFailure()
                return nil
            }
            self.init(rawValue: rawValue)
        }
        
    }

}


// MARK: - Implementing LosslessStringConvertible, leveraging the ObvCodable conformance

extension ObvDiscussionIdentifier: LosslessStringConvertible {
    
    public var description: String {
        self.obvEncode().rawData.hexString()
    }
    
    
    public init?(_ description: String) {
        guard let rawData = Data(hexString: description) else { assertionFailure(); return nil }
        guard let encoded = ObvEncoded(withRawData: rawData) else { assertionFailure(); return nil}
        do {
            self = try encoded.obvDecode()
        } catch {
            assertionFailure()
            return nil
        }
    }
    
}


// MARK: - Implementing

extension ObvDiscussionIdentifier: CustomDebugStringConvertible {
    
    public var debugDescription: String {
        "ObvDiscussionIdentifier<\(self.description.prefix(8))>"
    }
    
}


// MARK: - Codable

//extension ObvDiscussionIdentifier: Codable {
//    
//    enum CodingKeys: String, CodingKey {
//        case discussionId = "discussionId"
//        case identifier = "id"
//    }
//    
//    
//    public func encode(to encoder: any Encoder) throws {
//        do {
//            var container = encoder.container(keyedBy: CodingKeys.self)
//            try container.encode(self.discussionIdentifierRaw, forKey: .discussionId)
//            switch self {
//            case .oneToOne(let id):
//                try container.encode(id, forKey: .identifier)
//            case .groupV1(let id):
//                try container.encode(id, forKey: .identifier)
//            case .groupV2(let id):
//                try container.encode(id, forKey: .identifier)
//            }
//        } catch {
//            assertionFailure()
//            throw error
//        }
//    }
//    
//    
//    public init(from decoder: any Decoder) throws {
//        let values = try decoder.container(keyedBy: CodingKeys.self)
//        let discussionIdentifierRaw = try values.decode(DiscussionIdentifierRaw.self, forKey: .discussionId)
//        switch discussionIdentifierRaw {
//        case .oneToOne:
//            let id = try values.decode(ObvContactIdentifier.self, forKey: .identifier)
//            self = .oneToOne(id: id)
//        case .groupV1:
//            let id = try values.decode(ObvGroupV1Identifier.self, forKey: .identifier)
//            self = .groupV1(id: id)
//        case .groupV2:
//            let id = try values.decode(ObvGroupV2Identifier.self, forKey: .identifier)
//            self = .groupV2(id: id)
//        }
//    }
//
//    
//    private enum DiscussionIdentifierRaw: String, Codable {
//        case oneToOne = "o2o"
//        case groupV1 = "gv1"
//        case groupV2 = "gv2"
//    }
//    
//    
//    private var discussionIdentifierRaw: DiscussionIdentifierRaw {
//        switch self {
//        case .oneToOne: return .oneToOne
//        case .groupV1: return .groupV1
//        case .groupV2: return .groupV2
//        }
//    }
//
//    
//    public func encodeToJson() throws -> Data {
//        let encoder = JSONEncoder()
//        return try encoder.encode(self)
//    }
//    
//    
//    public static func decodeFromJson(data: Data) throws -> Self {
//        let decoder = JSONDecoder()
//        return try decoder.decode(ObvDiscussionIdentifier.self, from: data)
//    }
//
//}
