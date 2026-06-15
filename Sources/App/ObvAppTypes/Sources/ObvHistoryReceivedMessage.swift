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
import UniformTypeIdentifiers


public struct ObvHistoryReceivedMessage: Sendable, Equatable, Hashable {
    
    public let kind: Kind
    public let messageIdentifierFromEngine: UidFromServer
    public let timestamp: Date
    private let rawBody: String?
    public let replyTo: MessageReferenceJSON?
    public let expirationLimitedExistence: TimeInterval?
    private let userMentions: [UserMentionJSON]
    public let forwarded: Bool
    public let edited: Bool
    public let location: LocationJSON?
    public let poll: PollJSON?
    public let reactions: [Reaction]
    public let pollVotes: [PollVote]
    public let attachments: [Attachment]
    public let suggestedDiscussionTitle: String?
    
    public init(kind: Kind,
                messageIdentifierFromEngine: UidFromServer,
                timestamp: Date,
                bodyAndMentions: StringAndUserMentions?,
                replyTo: MessageReferenceJSON?,
                expirationLimitedExistence: TimeInterval?,
                forwarded: Bool, edited: Bool,
                location: LocationJSON?,
                poll: PollJSON?,
                reactions: [Reaction],
                pollVotes: [PollVote],
                attachments: [Attachment],
                suggestedDiscussionTitle: String?) {
        self.kind = kind
        self.messageIdentifierFromEngine = messageIdentifierFromEngine
        self.timestamp = timestamp
        self.rawBody = bodyAndMentions?.body
        self.replyTo = replyTo
        self.expirationLimitedExistence = expirationLimitedExistence
        self.userMentions = bodyAndMentions?.mentions.map { UserMentionJSON(mentionedCryptoId: $0.mentionedCryptoId, utf16Range: $0.utf16Range) } ?? []
        self.forwarded = forwarded
        self.edited = edited
        self.location = location
        self.poll = poll
        self.reactions = reactions
        self.pollVotes = pollVotes
        self.attachments = attachments
        self.suggestedDiscussionTitle = suggestedDiscussionTitle
    }

    public enum Kind: Sendable, Equatable, Hashable {
        case sent(messageIdentifier: ObvMessageSentAppIdentifier, status: SentMessageStatus)
        case received(messageIdentifier: ObvMessageReceivedAppIdentifier)
        
        public enum SentMessageStatus: Int, Sendable, Equatable {
            case sentFromAnotherOwnedDevice = 1          // STATUS_SENT_FROM_ANOTHER_DEVICE
            case sent = 2                                // STATUS_SENT
            case partiallyDeliveredNotRead = 3           // STATUS_DELIVERED
            case partiallyDeliveredAndPartiallyRead = 4  // STATUS_DELIVERED_AND_READ
            case couldNotBeSentToOneOrMoreRecipients = 5 // STATUS_UNDELIVERED
            case fullyDeliveredAndNotRead = 6            // STATUS_DELIVERED_ALL
            case fullyDeliveredAndPartiallyRead = 7      // STATUS_DELIVERED_ALL_READ_ONE
            case fullyDeliveredAndFullyRead = 8          // STATUS_DELIVERED_ALL_READ_ALL
        }

        var discussionIdentifier: ObvDiscussionIdentifier {
            switch self {
            case .sent(let messageIdentifier, _):
                return messageIdentifier.discussionIdentifier
            case .received(let messageIdentifier):
                return messageIdentifier.discussionIdentifier
            }
        }
        
    }
    
    private var body: String? {
        rawBody?.replacingOccurrences(of: "\0", with: " ")
    }

    public var bodyAndMentions: StringAndUserMentions? {
        guard let body, !body.isEmpty else { return nil }
        let mentions: [StringAndUserMentions.UserMention] = self.userMentions.map({ .init(mentionedCryptoId: $0.mentionedCryptoId, utf16Range: $0.utf16Range) })
        return .init(body: body, mentions: mentions)
    }

    public enum UidFromServer: Sendable, Equatable, Hashable {
        case unknown
        case known(Data)
    }
    
    public struct Reaction: Sendable, Equatable, Hashable {
        public let emoji: String
        public let sender: ObvCryptoId
        public let timestamp: Date
        
        public init(emoji: String, sender: ObvCryptoId, timestamp: Date) {
            self.emoji = emoji
            self.sender = sender
            self.timestamp = timestamp
        }
    }
    
    public struct PollVote: Sendable, Equatable, Hashable {
        public let candidate: UUID
        public let voted: Bool
        public let version: Int
        public let sender: ObvCryptoId
        public let timestamp: Date
        
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
    
    public struct Attachment: Sendable, Equatable, Hashable {
        public let sha256: Data
        public let number: Int
        public let size: Int
        public let mimeType: String
        public let filename: String
        
        public init(sha256: Data,
                    number: Int,
                    size: Int,
                    mimeType: String,
                    filename: String) {
            self.sha256 = sha256
            self.number = number
            self.size = size
            self.mimeType = mimeType
            self.filename = filename
        }
        
        public var utType: UTType {
            UTType(mimeType: mimeType) ?? .data
        }
        
        public var uti: String {
            utType.identifier
        }
        
    }
    
}


extension ObvHistoryReceivedMessage {
    
    public var messageIdentifier: ObvMessageAppIdentifier {
        switch kind {
        case .sent(let messageIdentifier, _):
            messageIdentifier.messageAppIdentifier
        case .received(let messageIdentifier):
            messageIdentifier.messageAppIdentifier
        }
    }
    
    public var discussionIdentifier: ObvDiscussionIdentifier {
        self.messageIdentifier.discussionIdentifier
    }
    
}
