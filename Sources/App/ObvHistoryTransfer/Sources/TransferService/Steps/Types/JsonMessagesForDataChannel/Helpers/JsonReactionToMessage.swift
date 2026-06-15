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


public struct JsonReactionToMessage: Sendable {
    let emoji: String
    let sender: ObvCryptoId
    let timestamp: Date
    
    public init(emoji: String,
                sender: ObvCryptoId,
                timestamp: Date) {
        self.emoji = emoji
        self.sender = sender
        self.timestamp = timestamp
    }
    
}


extension JsonReactionToMessage: Codable {
    
    enum CodingKeys: String, CodingKey {
        case emoji = "reaction"
        case sender = "sender"
        case timestamp = "timestamp"
    }
    
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.emoji, forKey: .emoji)
        try container.encode(self.sender, forKey: .sender)
        try container.encode(self.timestamp.epochInMs, forKey: .timestamp)
    }
    
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.emoji = try container.decode(String.self, forKey: .emoji)
        self.sender = try container.decode(ObvCryptoId.self, forKey: .sender)
        let timestampInEpochInMs: Int64 = try container.decode(Int64.self, forKey: .timestamp)
        self.timestamp = Date(epochInMs: timestampInEpochInMs)
    }
    
}
