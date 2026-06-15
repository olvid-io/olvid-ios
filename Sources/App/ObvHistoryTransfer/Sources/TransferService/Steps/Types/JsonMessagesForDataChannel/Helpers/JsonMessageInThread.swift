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


public struct JsonMessageInThread: Sendable {
    
    let senderSequenceNumber: Int
    let messageIdentifierFromEngine: UidFromServer
    let timestamp: Date
    let kind: Kind // Contains the status in case of a sent message
    private let rawBody: String?
    let replyTo: MessageReferenceJSON?
    let expirationLimitedExistence: TimeInterval?
    private let userMentions: [UserMentionJSON]
    let forwarded: Bool
    let edited: Bool
    // let bookmarked: Bool // Only exists on Android
    let location: LocationJSON?
    let poll: PollJSON?
    let reactions: [JsonReactionToMessage]
    let pollVotes: [JsonPollVoteForMessage]
    let attachments: [JsonAttachment]
    
    
    public init(senderSequenceNumber: Int,
                timestamp: Date,
                messageIdentifierFromEngine: UidFromServer,
                kind: Kind,
                bodyAndMentions: StringAndUserMentions?,
                replyTo: MessageReferenceJSON?,
                expirationLimitedExistence: TimeInterval?,
                forwarded: Bool,
                edited: Bool,
                location: LocationJSON?,
                poll: PollJSON?,
                reactions: [JsonReactionToMessage],
                pollVotes: [JsonPollVoteForMessage],
                attachments: [JsonAttachment]) {
        self.senderSequenceNumber = senderSequenceNumber
        self.messageIdentifierFromEngine = messageIdentifierFromEngine
        self.timestamp = timestamp
        self.kind = kind
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
    }
    
    
    public var body: String? {
        rawBody?.replacingOccurrences(of: "\0", with: " ")
    }

    public var bodyAndMentions: StringAndUserMentions? {
        guard let body, !body.isEmpty else { return nil }
        let mentions: [StringAndUserMentions.UserMention] = self.userMentions.map({ .init(mentionedCryptoId: $0.mentionedCryptoId, utf16Range: $0.utf16Range) })
        return .init(body: body, mentions: mentions)
    }

    public enum UidFromServer: Sendable, Equatable {
        case unknown
        case known(Data)
    }

    
    public enum Kind: Sendable, Equatable {
        case sent(status: SentMessageStatus)
        case received
                
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
        
    }
    
}


extension JsonMessageInThread: Codable {
    
    enum CodingKeys: String, CodingKey {
        case senderSequenceNumber = "sequenceNumber"
        case messageIdentifierFromEngine = "uidFromServer"
        case timestamp = "timestamp"
        case status = "status"
        case body = "body"
        case replyTo = "reply"
        case expirationLimitedExistence = "expiration"
        case userMentions = "mentions"
        case forwarded = "forwarded"
        case edited = "edited"
        // case bookmarked = "bookmarked" // Only exists on Android
        case location = "location"
        case poll = "poll"
        case reactions = "reactions"
        case pollVotes = "pollVotes"
        case attachments = "attachments"
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(senderSequenceNumber, forKey: .senderSequenceNumber)
        try container.encode(timestamp.epochInMs, forKey: .timestamp)
        switch kind {
        case .received:
            break
        case .sent(status: let status):
            try container.encode(status.rawValue, forKey: .status)
        }
        switch messageIdentifierFromEngine {
        case .known(let uidFromServer):
            try container.encode(uidFromServer, forKey: .messageIdentifierFromEngine)
        case .unknown:
            break
        }
        try container.encodeIfPresent(rawBody, forKey: .body)
        try container.encodeIfPresent(replyTo, forKey: .replyTo)
        try container.encodeIfPresent(expirationLimitedExistence, forKey: .expirationLimitedExistence)
        if body != nil, !userMentions.isEmpty {
            try container.encode(userMentions, forKey: .userMentions)
        }
        try container.encode(forwarded, forKey: .forwarded)
        try container.encode(edited, forKey: .edited)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(poll, forKey: .poll)
        if !reactions.isEmpty {
            try container.encode(reactions, forKey: .reactions)
        }
        if !pollVotes.isEmpty {
            try container.encode(pollVotes, forKey: .pollVotes)
        }
        if !attachments.isEmpty {
            try container.encode(attachments, forKey: .attachments)
        }
    }
 
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.senderSequenceNumber = try values.decode(Int.self, forKey: .senderSequenceNumber)
        let originalServerTimestampInMilliseconds = try values.decode(Int64.self, forKey: .timestamp)
        self.timestamp = Date(epochInMs: originalServerTimestampInMilliseconds)
        if let rawSentStatus = try values.decodeIfPresent(Int.self, forKey: .status) {
            guard let status: Kind.SentMessageStatus = .init(rawValue: rawSentStatus) else {
                assertionFailure()
                throw ObvError.decodingFailed
            }
            self.kind = .sent(status: status)
        } else {
            self.kind = .received
        }
        if let uidFromServer = try values.decodeIfPresent(Data.self, forKey: .messageIdentifierFromEngine) {
            self.messageIdentifierFromEngine = .known(uidFromServer)
        } else {
            self.messageIdentifierFromEngine = .unknown
        }
        self.rawBody = try values.decodeIfPresent(String.self, forKey: .body)
        self.replyTo = try values.decodeIfPresent(MessageReferenceJSON.self, forKey: .replyTo)
        if let expirationLimitedExistence = try values.decodeIfPresent(Int.self, forKey: .expirationLimitedExistence) {
            self.expirationLimitedExistence = TimeInterval(expirationLimitedExistence)
        } else {
            self.expirationLimitedExistence = nil
        }
        self.userMentions = values.decodeIfPresentAndContinueAfterError([UserMentionJSON].self, forKey: .userMentions) ?? []
        self.forwarded = try values.decodeIfPresent(Bool.self, forKey: .forwarded) ?? false
        self.edited = try values.decodeIfPresent(Bool.self, forKey: .edited) ?? false
        // let bookmarked: Bool // Only exists on Android
        self.location = try values.decodeIfPresent(LocationJSON.self, forKey: .location)
        self.poll = try values.decodeIfPresent(PollJSON.self, forKey: .poll)
        self.reactions = try values.decodeIfPresent([JsonReactionToMessage].self, forKey: .reactions) ?? []
        self.pollVotes = try values.decodeIfPresent([JsonPollVoteForMessage].self, forKey: .pollVotes) ?? []
        self.attachments = try values.decodeIfPresent([JsonAttachment].self, forKey: .attachments) ?? []

    }
    
    enum ObvError: Error {
        case decodingFailed
    }
    
}
