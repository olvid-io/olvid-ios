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
import OlvidUtils


public struct JsonPollVoteForMessage: Sendable {
    let candidate: UUID
    let voted: Bool
    let version: Int
    let sender: ObvCryptoId
    let timestamp: Date
    
    public init(candidate: UUID,
         voted: Bool,
         version: Int,
         sender: ObvCryptoId,
         timestamp: Date) {
        self.candidate = candidate
        self.voted = voted
        self.version = version
        self.sender = sender
        self.timestamp = timestamp
    }
    
}


extension JsonPollVoteForMessage: Codable {
    
    enum CodingKeys: String, CodingKey {
        case candidate = "candidate"
        case voted = "voted"
        case version = "version"
        case sender = "sender"
        case timestamp = "timestamp"
    }
    
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.candidate, forKey: .candidate)
        try container.encode(self.voted, forKey: .voted)
        try container.encode(self.version, forKey: .version)
        try container.encode(self.sender, forKey: .sender)
        try container.encode(self.timestamp.epochInMs, forKey: .timestamp)
    }
    
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.candidate = try container.decode(UUID.self, forKey: .candidate)
        self.voted = try container.decode(Bool.self, forKey: .voted)
        self.version = try container.decode(Int.self, forKey: .version)
        self.sender = try container.decode(ObvCryptoId.self, forKey: .sender)
        let timestampInEpochInMs: Int64 = try container.decode(Int64.self, forKey: .timestamp)
        self.timestamp = Date(epochInMs: timestampInEpochInMs)
    }
    
}
