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
import ObvAppTypes

/// Message sent by the source at the very beginning of the transfer.
///
/// This message contains all the identifiers of the available discussions, as well as all the sha256 of the attachments (with their length).
/// These sha256 are sent now to allow the showing of an accurate progress to the user during the transfer.
struct SrcDiscussionList: Sendable, Equatable {
    
    let discussions: [JsonDiscussionIdentifier]
    let sha256s: [Data: UInt64] // each key is a sha256, the corresponding value is the length of the file
    
    init(discussionIdentifiers: [ObvDiscussionIdentifier], sha256Map: [Data : UInt64]) {
        self.discussions = discussionIdentifiers.map { .init($0) }
        self.sha256s = sha256Map
    }
    
}


extension SrcDiscussionList: Codable {
    
    enum CodingKeys: String, CodingKey {
        case discussions = "discussions"
        case sha256s = "sha256s"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(discussions, forKey: .discussions)
        let dict: [String: UInt64] = .init(sha256s, keyMapping: { $0.base64EncodedString() }, valueMapping: { $0 })
        try container.encode(dict, forKey: .sha256s)
    }

    public init(from decoder: Decoder) throws {
        do {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            self.discussions = try values.decode([JsonDiscussionIdentifier].self, forKey: .discussions)
            do {
                let dict: [String: UInt64] = try values.decode([String: UInt64].self, forKey: .sha256s)
                self.sha256s = Dictionary(dict, keyMapping: { $0.base64EncodedToData }, valueMapping: { $0 })
            }
        } catch {
            assertionFailure()
            throw error
        }
    }

}
