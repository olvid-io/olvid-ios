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


struct JsonZipMessages {
    
    let discussionIdentifier: JsonDiscussionIdentifier
    let senderCryptoId: ObvCryptoId
    let senderThreadIdentifier: UUID
    let messages: [JsonMessageInThread]
    
    private init(discussionIdentifier: JsonDiscussionIdentifier,
                 senderCryptoId: ObvCryptoId,
                 senderThreadIdentifier: UUID,
                 messages: [JsonMessageInThread]) {
        self.discussionIdentifier = discussionIdentifier
        self.senderCryptoId = senderCryptoId
        self.senderThreadIdentifier = senderThreadIdentifier
        self.messages = messages
    }
    
}


// MARK: - Implementing Codable

extension JsonZipMessages: Codable {
    
    private enum CodingKeys: String, CodingKey {
        case discussionIdentifier = "discussion"
        case senderCryptoId = "sender"
        case senderThreadIdentifier = "threadId"
        case messages = "messages"
    }
    
}


// MARK: - Helpers

extension JsonZipMessages {
    
    init(srcMessages: SrcMessages) {
        self.init(discussionIdentifier: srcMessages.discussionIdentifier,
                  senderCryptoId: srcMessages.sender,
                  senderThreadIdentifier: srcMessages.threadId,
                  messages: srcMessages.messages)
    }
    
}


extension JsonZipMessages {
    
    func toListOfObvMessagesIdentifiers(ownedCryptoId: ObvCryptoId) throws -> [ObvMessageAppIdentifier] {
        let discussionIdentifier = try self.discussionIdentifier.getDiscussionIdentifier(ownedCryptoId: ownedCryptoId)
        if senderCryptoId == ownedCryptoId {
            return self.messages.map { message in
                    .sent(discussionIdentifier: discussionIdentifier,
                          senderThreadIdentifier: self.senderThreadIdentifier,
                          senderSequenceNumber: message.senderSequenceNumber)
            }
        } else {
            return self.messages.map { message in
                    .received(discussionIdentifier: discussionIdentifier,
                              senderIdentifier: senderCryptoId.getIdentity(),
                              senderThreadIdentifier: self.senderThreadIdentifier,
                              senderSequenceNumber: message.senderSequenceNumber)
            }
        }
    }
    
}


extension [JsonZipMessages] {
    
    func toListOfObvMessagesIdentifiers(ownedCryptoId: ObvCryptoId) throws -> [ObvMessageAppIdentifier] {
        return try self.flatMap({ try $0.toListOfObvMessagesIdentifiers(ownedCryptoId: ownedCryptoId) })
    }
    
}


extension JsonZipMessages {
    
    func toSrcMessages(dstDiscussionExpectedRangesForDiscussion: [JsonDiscussionIdentifier : DstDiscussionExpectedRanges]) -> SrcMessages? {
        guard let dstDiscussionExpectedRanges = dstDiscussionExpectedRangesForDiscussion[discussionIdentifier] else { return nil }
        let messagesToKeep = self.messages.filter { jsonMessageInThread in
            guard let closedRange = dstDiscussionExpectedRanges.rangesByThreadAndSender[self.senderCryptoId]?[self.senderThreadIdentifier] else {
                return false
            }
            let isInRange = closedRange.contains(where: { $0.contains(jsonMessageInThread.senderSequenceNumber) })
            return isInRange
        }
        return .init(discussionIdentifier: discussionIdentifier,
                     sender: senderCryptoId,
                     threadId: senderThreadIdentifier,
                     messages: messagesToKeep,
                     missingMessageCount: 0)
    }
    
}
