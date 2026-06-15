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


struct DstDiscussionExpectedRanges {
    
    let discussionIdentifier: JsonDiscussionIdentifier
    let rangesByThreadAndSender: [ObvCryptoId : [UUID : [ClosedRange<Int>]]]
    
    init(discussionIdentifier: ObvDiscussionIdentifier, messageIdentifiers: [ObvMessageAppIdentifier]) throws {
        
        for messageIdentifier in messageIdentifiers {
            guard discussionIdentifier == messageIdentifier.discussionIdentifier else {
                assertionFailure()
                throw ObvError.aMessageDoesNotBelongToTheSpecifiedDiscussion
            }
        }
        
        self.rangesByThreadAndSender = JsonMessagesHelpers.rangesByThreadAndSender(messageIdentifiers: messageIdentifiers)
        self.discussionIdentifier = JsonDiscussionIdentifier(discussionIdentifier)

    }
    
    
    init(discussionIdentifier: JsonDiscussionIdentifier, rangesByThreadAndSender: [ObvCryptoId : [UUID : [ClosedRange<Int>]]]) {
        self.discussionIdentifier = discussionIdentifier
        self.rangesByThreadAndSender = rangesByThreadAndSender
    }
    
}


extension DstDiscussionExpectedRanges: Equatable {
    // Synthesized implementation
}


extension DstDiscussionExpectedRanges: Codable {
    
    enum CodingKeys: String, CodingKey {
        case discussionIdentifier = "discussion"
        case rangesByThreadAndSender = "rangesByThreadAndSender" // Won't appear in the JSON
    }

    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(discussionIdentifier, forKey: .discussionIdentifier)
        let dict: [String: JsonRangesByThread] = .init(
            rangesByThreadAndSender,
            keyMapping: {
                $0.getIdentity().base64EncodedString()
            },
            valueMapping: {
                .init(ranges: $0)
            })
        try container.encode(dict, forKey: .rangesByThreadAndSender)
    }

    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.discussionIdentifier = try container.decode(JsonDiscussionIdentifier.self, forKey: .discussionIdentifier)
        let dict: [String: JsonRangesByThread] = try container.decode([String: JsonRangesByThread].self, forKey: .rangesByThreadAndSender)
        self.rangesByThreadAndSender = try .init(
            dict,
            keyMapping: {
                guard let identity = $0.base64EncodedToData else { assertionFailure(); throw ObvError.decodingError }
                return try ObvCryptoId(identity: identity)
            },
            valueMapping: {
                $0.ranges
            })
    }

    
}


// MARK: - Errors

extension DstDiscussionExpectedRanges {
    
    enum ObvError: Error {
        case aMessageDoesNotBelongToTheSpecifiedDiscussion
        case decodingError
    }

}
