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


public struct MessageReferenceJSON: Codable, Equatable, Hashable, Sendable {
    
    public let senderSequenceNumber: Int
    public let senderThreadIdentifier: UUID // One identifier per device of the sender
    public let senderIdentifier: Data
    
    enum CodingKeys: String, CodingKey {
        case senderSequenceNumber = "ssn"
        case senderThreadIdentifier = "sti"
        case senderIdentifier = "si"
    }

    
    public init(senderSequenceNumber: Int, senderThreadIdentifier: UUID, senderIdentifier: Data) {
        self.senderSequenceNumber = senderSequenceNumber
        self.senderThreadIdentifier = senderThreadIdentifier
        self.senderIdentifier = senderIdentifier
    }
    
    
    public func getMessageIdentifier(discussionIdentifier: ObvDiscussionIdentifier) -> ObvMessageAppIdentifier {
        if senderIdentifier == discussionIdentifier.ownedCryptoId.getIdentity() {
            return .sent(
                discussionIdentifier: discussionIdentifier,
                senderThreadIdentifier: senderThreadIdentifier,
                senderSequenceNumber: senderSequenceNumber)
        } else {
            return ObvMessageAppIdentifier.received(
                discussionIdentifier: discussionIdentifier,
                senderIdentifier: senderIdentifier,
                senderThreadIdentifier: senderThreadIdentifier,
                senderSequenceNumber: senderSequenceNumber)
        }
    }
    
    
//    public init(from decoder: Decoder) throws {
//        let values = try decoder.container(keyedBy: CodingKeys.self)
//        self.senderSequenceNumber = try values.decode(Int.self, forKey: .senderSequenceNumber)
//        self.senderThreadIdentifier = try values.decode(UUID.self, forKey: .senderThreadIdentifier)
//        self.senderIdentifier = try values.decode(Data.self, forKey: .senderIdentifier)
//    }
//
//    public func encode(to encoder: Encoder) throws {
//        var container = encoder.container(keyedBy: CodingKeys.self)
//        try container.encode(senderSequenceNumber, forKey: .senderSequenceNumber)
//        try container.encode(senderThreadIdentifier, forKey: .senderThreadIdentifier)
//        try container.encode(senderIdentifier, forKey: .senderIdentifier)
//    }
    
}
