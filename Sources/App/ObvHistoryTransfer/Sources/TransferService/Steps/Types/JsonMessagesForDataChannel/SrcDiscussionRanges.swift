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


/// Message sent by the source at the very beginning of the transfer.
///
/// The source sends one `SrcDiscussionRanges` per discussion. This message contains
/// - the identifier of the discussion
/// - the title of the discussion (which is only required to properly handle locked discussions)
/// - a dictionary keyed by the identity of the sender. Each value is a dictionary keyed by the sender thread identifier.
///   Each value is a list of ranges (implementeded as a list of size 2) where the first element is the sequence number of the first
///   message (included), and the second is the sequence number of the last message (included). All the messages in the range are sent by the same user.
struct SrcDiscussionRanges {
    
    let discussionIdentifier: JsonDiscussionIdentifier
    let discussionTitle: String
    let rangesByThreadAndSender: [ObvCryptoId : [UUID : [ClosedRange<Int>]]]

    /// We expect the message identifiers to be in "chronological" order.
    init(discussionTitle: String, discussionIdentifier: ObvDiscussionIdentifier, messageIdentifiers: [ObvMessageAppIdentifier]) throws {
        
        for messageIdentifier in messageIdentifiers {
            guard discussionIdentifier == messageIdentifier.discussionIdentifier else {
                assertionFailure()
                throw ObvError.aMessageDoesNotBelongToTheSpecifiedDiscussion
            }
        }
        
        self.rangesByThreadAndSender = JsonMessagesHelpers.rangesByThreadAndSender(messageIdentifiers: messageIdentifiers)
        self.discussionTitle = discussionTitle
        self.discussionIdentifier = JsonDiscussionIdentifier(discussionIdentifier)

    }
    
}


extension SrcDiscussionRanges: Equatable {
    // Synthesized implementation
}


// MARK: - Implementing Codable

extension SrcDiscussionRanges: Codable {
    
    enum CodingKeys: String, CodingKey {
        case discussionIdentifier = "discussion"
        case discussionTitle = "title"
        case rangesByThreadAndSender = "rangesByThreadAndSender" // Won't appear in the JSON
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(discussionIdentifier, forKey: .discussionIdentifier)
        try container.encode(discussionTitle, forKey: .discussionTitle)
        let dict: [String: JsonRangesByThread] = .init(rangesByThreadAndSender, keyMapping: { $0.getIdentity().base64EncodedString() }, valueMapping: { .init(ranges: $0) })
        try container.encode(dict, forKey: .rangesByThreadAndSender)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.discussionIdentifier = try container.decode(JsonDiscussionIdentifier.self, forKey: .discussionIdentifier)
        self.discussionTitle = try container.decode(String.self, forKey: .discussionTitle)
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


// MARK: - Private helpers for the initializer

extension SrcDiscussionRanges {
    
        
}


// MARK: - Errors

extension SrcDiscussionRanges {
    
    enum ObvError: Error {
        case aMessageDoesNotBelongToTheSpecifiedDiscussion
        case decodingError
    }

}
