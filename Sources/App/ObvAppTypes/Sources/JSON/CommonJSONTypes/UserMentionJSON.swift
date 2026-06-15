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


/// Denotes a mention object
/// - Attention: Ranges are half-open, from a lower-bound and up-to, but **NOT** including, an upper-bound
/// - Attention: Mentions are only to be used with the mentioned contact's *real name*, not the nickname defined by the sender.
/// - Important: **Ranges are calculated based on UTF-16 code units offset**
///
///
/// For each mention, the JSON API has the following structure:
///
/// ```json
/// {
///   "mentions": [
///     {
///       "uid": <crypto_identity> (``ObvDataTypes/ObvCryptoId``)
///       "rs": 4,
///       "re": 2
///     }
///   ]
/// }
/// ```
public struct UserMentionJSON: Hashable, Sendable {
    /// The mentioned user's crypto ID
    public let mentionedCryptoId: ObvCryptoId
    
    /// The range of the mentioned user's name, within the UTF16 representation of ``MessageJSON/body``
    public let utf16Range: Range<Int>
    
    public init(mentionedCryptoId: ObvCryptoId, utf16Range: Range<Int>) {
        self.mentionedCryptoId = mentionedCryptoId
        self.utf16Range = utf16Range
    }
}



extension UserMentionJSON: Codable {

    enum CodingKeys: String, CodingKey {
        case mentionedCryptoId = "uid"
        case rangeStart = "rs"
        case rangeEnd = "re"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mentionedCryptoId, forKey: .mentionedCryptoId)
        try container.encode(utf16Range.lowerBound, forKey: .rangeStart)
        try container.encode(utf16Range.upperBound, forKey: .rangeEnd)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mentionedCryptoId = try container.decode(ObvCryptoId.self, forKey: .mentionedCryptoId)
        let lowerBound = try container.decode(Int.self, forKey: .rangeStart)
        let upperBound = try container.decode(Int.self, forKey: .rangeEnd)
        guard lowerBound < upperBound else {
            assertionFailure()
            throw MentionError.DecodingError.invalidMentionRange
        }
        let utf16Range = lowerBound..<upperBound
        self.init(mentionedCryptoId: mentionedCryptoId, utf16Range: utf16Range)
    }

}


extension UserMentionJSON {
    /// A namespace for encoding/decoding ``MessageJSON/UserMention``s
    enum MentionError {
        /// Possible decoding errors
        ///
        /// - mentionRangeNotWithinMessageRange: Denotes an error where the mention range is not contained within the actual message
        enum DecodingError: Error {
            case invalidMentionRange
        }
    }
}
