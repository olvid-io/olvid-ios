/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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
import os.log
import ObvEngine
import ObvTypes
import ObvCrypto
import OlvidUtils


public struct PersistedItemJSON: Codable {
    
    public let message: MessageJSON?
    public let returnReceipt: ReturnReceiptJSON?
    public let webrtcMessage: WebRTCMessageJSON?
    public let discussionSharedConfiguration: DiscussionSharedConfigurationJSON?
    public let deleteMessagesJSON: DeleteMessagesJSON?
    public let deleteDiscussionJSON: DeleteDiscussionJSON?
    public let querySharedSettingsJSON: QuerySharedSettingsJSON?
    public let updateMessageJSON: UpdateMessageJSON?
    public let reactionJSON: ReactionJSON?
    public let screenCaptureDetectionJSON: ScreenCaptureDetectionJSON?

    enum CodingKeys: String, CodingKey {
        case message = "message"
        case returnReceipt = "rr"
        case webrtcMessage = "rtc"
        case discussionSharedConfiguration = "settings"
        case deleteMessagesJSON = "delm"
        case deleteDiscussionJSON = "deld"
        case querySharedSettingsJSON = "qss"
        case updateMessageJSON = "upm"
        case reactionJSON = "reacm"
        case screenCaptureDetectionJSON = "scd"
    }
    
    public init(messageJSON: MessageJSON) {
        self.message = messageJSON
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.screenCaptureDetectionJSON = nil
    }
    
    public init(returnReceiptJSON: ReturnReceiptJSON) {
        self.message = nil
        self.returnReceipt = returnReceiptJSON
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.screenCaptureDetectionJSON = nil
    }
    
    public init(messageJSON: MessageJSON, returnReceiptJSON: ReturnReceiptJSON) {
        self.message = messageJSON
        self.returnReceipt = returnReceiptJSON
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.screenCaptureDetectionJSON = nil
    }
    
    public init(webrtcMessage: WebRTCMessageJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = webrtcMessage
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.screenCaptureDetectionJSON = nil
    }
    
    public init(discussionSharedConfiguration: DiscussionSharedConfigurationJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = discussionSharedConfiguration
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.screenCaptureDetectionJSON = nil
    }
    
    public init(deleteMessagesJSON: DeleteMessagesJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = deleteMessagesJSON
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.screenCaptureDetectionJSON = nil
    }

    public init(deleteDiscussionJSON: DeleteDiscussionJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = deleteDiscussionJSON
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.screenCaptureDetectionJSON = nil
    }
    
    public init(querySharedSettingsJSON: QuerySharedSettingsJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = querySharedSettingsJSON
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.screenCaptureDetectionJSON = nil
    }

    public init(updateMessageJSON: UpdateMessageJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = updateMessageJSON
        self.reactionJSON = nil
        self.screenCaptureDetectionJSON = nil
    }

    public init(reactionJSON: ReactionJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = reactionJSON
        self.screenCaptureDetectionJSON = nil
    }

    public init(screenCaptureDetectionJSON: ScreenCaptureDetectionJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.screenCaptureDetectionJSON = screenCaptureDetectionJSON
    }

    public func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    public static func jsonDecode(_ data: Data) throws -> PersistedItemJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(PersistedItemJSON.self, from: data)
    }

}


public struct DiscussionSharedConfigurationJSON: Codable {
    
    private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "DiscussionSharedConfigurationJSON")
    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { DiscussionSharedConfigurationJSON.makeError(message: message) }

    let version: Int
    let expiration: ExpirationJSON
    let groupV1Identifier: (groupUid: UID, groupOwner: ObvCryptoId)?
    let groupV2Identifier: Data?

    public var groupIdentifier: GroupIdentifier? {
        if let groupV1Identifier = groupV1Identifier {
            return .groupV1(groupV1Identifier: groupV1Identifier)
        } else if let groupV2Identifier = groupV2Identifier {
            return .groupV2(groupV2Identifier: groupV2Identifier)
        } else {
            return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case version = "version"
        case expiration = "exp"
        case groupUid = "guid" // For group V1
        case groupOwner = "go" // For group V1
        case groupV2Identifier = "gid2"
    }

    init(version: Int, expiration: ExpirationJSON) {
        self.version = version
        self.expiration = expiration
        self.groupV1Identifier = nil
        self.groupV2Identifier = nil
    }

    init(version: Int, expiration: ExpirationJSON, groupV1Identifier: (groupUid: UID, groupOwner: ObvCryptoId)) {
        self.version = version
        self.expiration = expiration
        self.groupV1Identifier = groupV1Identifier
        self.groupV2Identifier = nil
    }

    init(version: Int, expiration: ExpirationJSON, groupV2Identifier: Data) {
        self.version = version
        self.expiration = expiration
        self.groupV1Identifier = nil
        self.groupV2Identifier = groupV2Identifier
    }

    func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    static func jsonDecode(_ data: Data) throws -> DiscussionSharedConfigurationJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(DiscussionSharedConfigurationJSON.self, from: data)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let groupV1Identifier = groupV1Identifier {
            try container.encode(groupV1Identifier.groupUid.raw, forKey: .groupUid)
            try container.encode(groupV1Identifier.groupOwner.getIdentity(), forKey: .groupOwner)
        }
        if let groupV2Identifier = groupV2Identifier {
            try container.encode(groupV2Identifier, forKey: .groupV2Identifier)
        }
        try container.encode(version, forKey: .version)
        try container.encode(expiration, forKey: .expiration)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try values.decode(Int.self, forKey: .version)
        if let expiration = try values.decodeIfPresent(ExpirationJSON.self, forKey: .expiration) {
            self.expiration = expiration
        } else {
            self.expiration = ExpirationJSON(readOnce: false, visibilityDuration: nil, existenceDuration: nil)
        }
        
        let groupUidRaw = try values.decodeIfPresent(Data.self, forKey: .groupUid)
        let groupOwnerIdentity = try values.decodeIfPresent(Data.self, forKey: .groupOwner)
        
        let groupV2Identifier = try values.decodeIfPresent(Data.self, forKey: .groupV2Identifier)
        
        if let groupUidRaw = groupUidRaw,
            let groupOwnerIdentity = groupOwnerIdentity,
            let groupUid = UID(uid: groupUidRaw),
            let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) {
            self.groupV1Identifier = (groupUid, groupOwner)
            self.groupV2Identifier = nil
        } else if let groupV2Identifier = groupV2Identifier {
            self.groupV1Identifier = nil
            self.groupV2Identifier = groupV2Identifier
        } else {
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        }
    }

}


struct DiscussionSharedConfigurationForKeycloakGroupJSON: Decodable {
    
    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { DiscussionSharedConfigurationForKeycloakGroupJSON.makeError(message: message) }

    let expiration: ExpirationJSON?

    enum CodingKeys: String, CodingKey {
        case expiration = "exp"
    }

    private init(expiration: ExpirationJSON) {
        self.expiration = expiration
    }

    static func jsonDecode(_ data: Data) throws -> DiscussionSharedConfigurationForKeycloakGroupJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(DiscussionSharedConfigurationForKeycloakGroupJSON.self, from: data)
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.expiration = try values.decodeIfPresent(ExpirationJSON.self, forKey: .expiration)
    }

}


public struct ReturnReceiptJSON: Codable {
    
    private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "ReturnReceiptJSON")

    public enum Status: Int {
        case delivered = 1
        case read = 2
    }
    
    let nonce: Data
    let key: Data
    
    public var elements: (nonce: Data, key: Data) {
        return (nonce, key)
    }

    enum CodingKeys: String, CodingKey {
        case nonce = "nonce"
        case key = "key"
    }
    
    public init(returnReceiptElements: (nonce: Data, key: Data)) {
        self.nonce = returnReceiptElements.nonce
        self.key = returnReceiptElements.key
    }
    
    init(nonce: Data, key: Data) {
        self.nonce = nonce
        self.key = key
    }
        
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.nonce = try values.decode(Data.self, forKey: .nonce)
        self.key = try values.decode(Data.self, forKey: .key)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nonce, forKey: .nonce)
        try container.encode(key, forKey: .key)
    }
    
    func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
    
    static func jsonDecode(_ data: Data) throws -> ReturnReceiptJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(ReturnReceiptJSON.self, from: data)
    }
}


public struct ExpirationJSON: Codable, Equatable {

    public let readOnce: Bool
    public let visibilityDuration: TimeInterval?
    public let existenceDuration: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case readOnce = "ro"
        case visibilityDuration = "vis"
        case existenceDuration = "ex"
    }

    enum ExpirationJSONCodingError: Error {
        case decoding(String)
    }

    init(readOnce: Bool, visibilityDuration: TimeInterval?, existenceDuration: TimeInterval?) {
        self.readOnce = readOnce
        self.visibilityDuration = visibilityDuration
        self.existenceDuration = existenceDuration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let readOnce = try container.decodeIfPresent(Bool.self, forKey: .readOnce) {
            self.readOnce = readOnce
        } else {
            self.readOnce = false
        }
        if let visibilityDuration = try container.decodeIfPresent(Int.self, forKey: .visibilityDuration) {
            self.visibilityDuration = TimeInterval(visibilityDuration)
        } else {
            self.visibilityDuration = nil
        }
        if let existenceDuration = try container.decodeIfPresent(Int.self, forKey: .existenceDuration) {
            self.existenceDuration = TimeInterval(existenceDuration)
        } else {
            self.existenceDuration = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if readOnce {
            try container.encodeIfPresent(readOnce, forKey: .readOnce)
        }
        if let visibilityDuration = self.visibilityDuration {
            try container.encodeIfPresent(Int(visibilityDuration), forKey: .visibilityDuration)
        }
        if let existenceDuration = self.existenceDuration {
            try container.encodeIfPresent(Int(existenceDuration), forKey: .existenceDuration)
        }
    }

    func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        return data
    }

    static func jsonDecode(_ data: Data) throws -> ExpirationJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(ExpirationJSON.self, from: data)
    }

}

public struct MessageJSON: Codable {
    
    private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "MessageJSON")
    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { MessageJSON.makeError(message: message) }

    public let senderSequenceNumber: Int
    public let senderThreadIdentifier: UUID
    public let body: String?
    public let groupV1Identifier: (groupUid: UID, groupOwner: ObvCryptoId)?
    public let groupV2Identifier: Data?
    public let replyTo: MessageReferenceJSON?
    public let expiration: ExpirationJSON?
    let forwarded: Bool
    /// This is the server timestamp received the first time the sender sent infos about this message.
    /// It is used to properly sort messages in Group V2 discussions.
    public let originalServerTimestamp: Date?
    public let userMentions: [UserMention]


    public var groupIdentifier: GroupIdentifier? {
        if let groupV1Identifier = groupV1Identifier {
            return .groupV1(groupV1Identifier: groupV1Identifier)
        } else if let groupV2Identifier = groupV2Identifier {
            return .groupV2(groupV2Identifier: groupV2Identifier)
        } else {
            return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case senderSequenceNumber = "ssn"
        case senderThreadIdentifier = "sti"
        case groupUid = "guid" // For group v1
        case groupOwner = "go" // For group v1
        case groupV2Identifier = "gid2" // For group v2
        case body = "body"
        case replyTo = "re"
        case expiration = "exp"
        case forwarded = "fw"
        case originalServerTimestamp = "ost"
        case userMentions = "um"
    }
    
    public init(senderSequenceNumber: Int, senderThreadIdentifier: UUID, body: String?, replyTo: MessageReferenceJSON?, expiration: ExpirationJSON?, forwarded: Bool, userMentions: [UserMention]) {
        self.senderSequenceNumber = senderSequenceNumber
        self.senderThreadIdentifier = senderThreadIdentifier
        self.body = body
        self.groupV1Identifier = nil
        self.groupV2Identifier = nil
        self.replyTo = replyTo
        self.expiration = expiration
        self.forwarded = forwarded
        self.originalServerTimestamp = nil // Never set for oneToOne discussions
        self.userMentions = userMentions
    }

    public init(senderSequenceNumber: Int, senderThreadIdentifier: UUID, body: String?, groupV1Identifier: (groupUid: UID, groupOwner: ObvCryptoId), replyTo: MessageReferenceJSON?, expiration: ExpirationJSON?, forwarded: Bool, userMentions: [UserMention]) {
        self.senderSequenceNumber = senderSequenceNumber
        self.senderThreadIdentifier = senderThreadIdentifier
        self.body = body
        self.groupV1Identifier = groupV1Identifier
        self.groupV2Identifier = nil
        self.replyTo = replyTo
        self.expiration = expiration
        self.forwarded = forwarded
        self.originalServerTimestamp = nil // Never set for Group V1 discussions
        self.userMentions = userMentions
    }

    public init(senderSequenceNumber: Int, senderThreadIdentifier: UUID, body: String?, groupV2Identifier: Data, replyTo: MessageReferenceJSON?, expiration: ExpirationJSON?, forwarded: Bool, originalServerTimestamp: Date?, userMentions: [UserMention]) {
        self.senderSequenceNumber = senderSequenceNumber
        self.senderThreadIdentifier = senderThreadIdentifier
        self.body = body
        self.groupV1Identifier = nil
        self.groupV2Identifier = groupV2Identifier
        self.replyTo = replyTo
        self.expiration = expiration
        self.forwarded = forwarded
        self.originalServerTimestamp = originalServerTimestamp
        self.userMentions = userMentions
    }


    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.senderSequenceNumber = try values.decode(Int.self, forKey: .senderSequenceNumber)
        self.senderThreadIdentifier = try values.decode(UUID.self, forKey: .senderThreadIdentifier)
        let body = try values.decodeIfPresent(String.self, forKey: .body)

        self.body = body

        let groupUidRaw = try values.decodeIfPresent(Data.self, forKey: .groupUid)
        let groupOwnerIdentity = try values.decodeIfPresent(Data.self, forKey: .groupOwner)
        
        let groupV2Identifier = try values.decodeIfPresent(Data.self, forKey: .groupV2Identifier)
        
        if let groupUidRaw = groupUidRaw,
            let groupOwnerIdentity = groupOwnerIdentity,
            let groupUid = UID(uid: groupUidRaw),
            let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) {
            self.groupV1Identifier = (groupUid, groupOwner)
            self.groupV2Identifier = nil
        } else if let groupV2Identifier = groupV2Identifier {
            self.groupV1Identifier = nil
            self.groupV2Identifier = groupV2Identifier
        } else {
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        }
                
        self.replyTo = try values.decodeIfPresent(MessageReferenceJSON.self, forKey: .replyTo)
        self.expiration = try values.decodeIfPresent(ExpirationJSON.self, forKey: .expiration)
        self.forwarded = try values.decodeIfPresent(Bool.self, forKey: .forwarded) ?? false
        
        let originalServerTimestampInMilliseconds = try values.decodeIfPresent(Int64.self, forKey: .originalServerTimestamp)
        if groupV2Identifier != nil, let originalServerTimestampInMilliseconds = originalServerTimestampInMilliseconds {
            self.originalServerTimestamp = Date(epochInMs: originalServerTimestampInMilliseconds)
        } else {
            self.originalServerTimestamp = nil
        }

        if let body,
           values.contains(.userMentions),
           try values.decodeNil(forKey: .userMentions) == false {
            let decodingBlock: (Decoder) throws -> UserMention?

            if #available(iOS 15, *) {
                let configuration = UserMention.Configuration(message: body)

                decodingBlock = { decoder -> UserMention? in
                    do {
                        return try UserMention(from: decoder, configuration: configuration)
                    } catch let error as UserMention.MentionError.DecodingError {
                        assertionFailure("failed to decode with error: \(error)") //used for debugging
                        return nil
                    }
                }
            } else {
                decodingBlock = { decoder -> UserMention? in
                    do {
                        return try UserMention(from: decoder, messageBody: body)
                    } catch let error as UserMention.MentionError.DecodingError {
                        assertionFailure("failed to decode with error: \(error)") //used for debugging
                        return nil
                    }
                }
            }

            var _storage: [UserMention] = []

            var container = try values.nestedUnkeyedContainer(forKey: .userMentions)

            while !container.isAtEnd {
                if let decodedMention = try decodingBlock(container.superDecoder()) {
                    _storage.append(decodedMention)
                }
            }

            userMentions = _storage
        } else {
            userMentions = []
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let groupV1Identifier = groupV1Identifier {
            try container.encode(groupV1Identifier.groupUid.raw, forKey: .groupUid)
            try container.encode(groupV1Identifier.groupOwner.getIdentity(), forKey: .groupOwner)
        }
        if let groupV2Identifier = groupV2Identifier {
            try container.encode(groupV2Identifier, forKey: .groupV2Identifier)
            try container.encodeIfPresent(originalServerTimestamp?.epochInMs, forKey: .originalServerTimestamp)
        }
        try container.encode(senderSequenceNumber, forKey: .senderSequenceNumber)
        try container.encode(senderThreadIdentifier, forKey: .senderThreadIdentifier)
        if let body = body {
            try container.encode(body, forKey: .body)
        }
        if let replyTo = replyTo {
            try container.encode(replyTo, forKey: .replyTo)
        }
        if let expiration = expiration {
            try container.encode(expiration, forKey: .expiration)
        }
        try container.encode(forwarded, forKey: .forwarded)

        if let body,
            userMentions.isEmpty == false {
            if #available(iOS 15, *) {
                let configuration = UserMention.Configuration(message: body)

                try container.encode(userMentions, forKey: .userMentions, configuration: configuration)
            } else {
                let encoder = container.superEncoder(forKey: .userMentions)

                var _innerContainer = encoder.unkeyedContainer()

                for aMention in userMentions {
                    let _currentDecoder = _innerContainer.superEncoder()

                    try aMention.encode(to: _currentDecoder, messageBody: body)
                }
            }
        }
    }
    
    func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
    
    static func jsonDecode(_ data: Data) throws -> MessageJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(MessageJSON.self, from: data)
    }
}

extension MessageJSON {
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
    public struct UserMention: Hashable {
        /// The mentioned user's crypto ID
        public let mentionedCryptoId: ObvCryptoId

        /// The range of the mentioned user's name, within ``MessageJSON/body``
        public let range: Range<String.Index>

        public init(mentionedCryptoId: ObvCryptoId, range: Range<String.Index>) {
            self.mentionedCryptoId = mentionedCryptoId
            self.range = range
        }
    }
}

@available(iOS, deprecated: 15, message: "Please use `CodableWithConfiguration` conformance now")
extension MessageJSON.UserMention: Codable {
    @available(*, deprecated, renamed: "init(from:messageBody:)")
    public init(from decoder: Decoder) throws {
        fatalError("init(from:) has not been implemented, please use init(from:messageBody:)")
    }

    @available(*, deprecated, renamed: "encode(to:messageBody:)")
    public func encode(to encoder: Encoder) throws {
        fatalError("encode(to:) has not been implemented, please use encode(to:messageBody:)")
    }

    public init(from decoder: Decoder, messageBody: String) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let data = try container.decode(Data.self, forKey: .mentionedCryptoId)

        mentionedCryptoId = try ObvCryptoId(identity: data)

        let rangeStart = try container.decode(Int.self, forKey: .rangeStart)

        let rangeEnd = try container.decode(Int.self, forKey: .rangeEnd)

        let startIndex = String.Index(utf16Offset: rangeStart, in: messageBody)

        let endIndex = String.Index(utf16Offset: rangeEnd, in: messageBody)

        let messageBodyRange = messageBody.startIndex..<messageBody.endIndex

        guard endIndex >= startIndex else {
            throw MentionError.DecodingError.mentionRangeInvalid(lower: startIndex, upper: endIndex)
        }

        if endIndex > messageBody.startIndex {
            guard messageBodyRange.contains(startIndex),
                  messageBodyRange.contains(messageBody.index(before: endIndex)) else {
                throw MentionError.DecodingError.mentionRangeNotWithinMessageRange(mentionRange: startIndex..<endIndex, message: messageBody)
            }
        }

        range = startIndex..<endIndex
    }

    public func encode(to encoder: Encoder, messageBody: String) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(mentionedCryptoId.cryptoIdentity.getIdentity(), forKey: .mentionedCryptoId)

        try container.encode(range.lowerBound.utf16Offset(in: messageBody), forKey: .rangeStart)

        try container.encode(range.upperBound.utf16Offset(in: messageBody), forKey: .rangeEnd)
    }
    
    private enum CodingKeys: String, CodingKey {
        case mentionedCryptoId = "uid"
        case rangeStart = "rs"
        case rangeEnd = "re"
    }
}

extension MessageJSON.UserMention {
    /// A namespace for encoding/decoding ``MessageJSON/UserMention``s
    enum MentionError {
        /// Possible decoding errors
        ///
        /// - mentionRangeInvalid: Denotes an inconsistent state within the string indices, more generally the lower is higher then the upper bound or vice-versa
        /// - mentionRangeNotWithinMessageRange: Denotes an error where the mention range is not contained within the actual message
        enum DecodingError: Error {
            /// Denotes an inconsistent state within the string indices, more generally the lower is higher then the upper bound or vice-versa
            case mentionRangeInvalid(lower: String.Index, upper: String.Index)
            /// Denotes an error where the mention range is not contained within the actual message
            case mentionRangeNotWithinMessageRange(mentionRange: Range<String.Index>, message: String)
        }
    }
}

@available(iOS 15, *)
extension MessageJSON.UserMention: CodableWithConfiguration {
    public typealias DecodingConfiguration = Configuration
    public typealias EncodingConfiguration = Configuration

    /// The configuration object for serializing a user mention
    public struct Configuration {
        /// The raw message body containing the mention
        let message: String
    }

    public init(from decoder: Decoder, configuration: DecodingConfiguration) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let data = try container.decode(Data.self, forKey: .mentionedCryptoId)

        self.mentionedCryptoId = try ObvCryptoId(identity: data)

        let rangeStart = try container.decode(Int.self, forKey: .rangeStart)

        let rangeEnd = try container.decode(Int.self, forKey: .rangeEnd)

        let messageBody = configuration.message

        let startIndex = String.Index(utf16Offset: rangeStart, in: messageBody)

        let endIndex = String.Index(utf16Offset: rangeEnd, in: messageBody)

        let messageBodyRange = messageBody.startIndex..<messageBody.endIndex

        guard endIndex >= startIndex else {
            throw MentionError.DecodingError.mentionRangeInvalid(lower: startIndex, upper: endIndex)
        }

        if endIndex > messageBody.startIndex {
            guard messageBodyRange.contains(startIndex),
                  messageBodyRange.contains(messageBody.index(before: endIndex)) else {
                throw MentionError.DecodingError.mentionRangeNotWithinMessageRange(mentionRange: startIndex..<endIndex, message: messageBody)
            }
        }

        range = startIndex..<endIndex
    }

    public func encode(to encoder: Encoder, configuration: Configuration) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(mentionedCryptoId.getIdentity(), forKey: .mentionedCryptoId)

        let messageBody = configuration.message

        try container.encode(range.lowerBound.utf16Offset(in: messageBody), forKey: .rangeStart)

        try container.encode(range.upperBound.utf16Offset(in: messageBody), forKey: .rangeEnd)
    }
}

public struct MessageReferenceJSON: Codable {
    
    public let senderSequenceNumber: Int
    public let senderThreadIdentifier: UUID
    public let senderIdentifier: Data
    
    enum CodingKeys: String, CodingKey {
        case senderSequenceNumber = "ssn"
        case senderThreadIdentifier = "sti"
        case senderIdentifier = "si"
    }

    
    init(senderSequenceNumber: Int, senderThreadIdentifier: UUID, senderIdentifier: Data) {
        self.senderSequenceNumber = senderSequenceNumber
        self.senderThreadIdentifier = senderThreadIdentifier
        self.senderIdentifier = senderIdentifier
    }
    
    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.senderSequenceNumber = try values.decode(Int.self, forKey: .senderSequenceNumber)
        self.senderThreadIdentifier = try values.decode(UUID.self, forKey: .senderThreadIdentifier)
        self.senderIdentifier = try values.decode(Data.self, forKey: .senderIdentifier)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(senderSequenceNumber, forKey: .senderSequenceNumber)
        try container.encode(senderThreadIdentifier, forKey: .senderThreadIdentifier)
        try container.encode(senderIdentifier, forKey: .senderIdentifier)
    }
    
}


public struct DeleteMessagesJSON: Codable {
    
    private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "deleteMessagesJSON")

    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { DeleteMessagesJSON.makeError(message: message) }

    let groupV1Identifier: (groupUid: UID, groupOwner: ObvCryptoId)?
    let groupV2Identifier: Data?
    public let messagesToDelete: [MessageReferenceJSON]
    
    public var groupIdentifier: GroupIdentifier? {
        if let groupV1Identifier = groupV1Identifier {
            return .groupV1(groupV1Identifier: groupV1Identifier)
        } else if let groupV2Identifier = groupV2Identifier {
            return .groupV2(groupV2Identifier: groupV2Identifier)
        } else {
            return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case groupUid = "guid" // For group V1
        case groupOwner = "go" // For group V1
        case groupV2Identifier = "gid2" // For group V2
        case messagesToDelete = "refs"
    }
    
    public init(persistedMessagesToDelete: [PersistedMessage]) throws {
        
        guard !persistedMessagesToDelete.isEmpty else { throw DeleteMessagesJSON.makeError(message: "No message to delete") }
        
        let discussion: PersistedDiscussion
        do {
            let discussions = Set(persistedMessagesToDelete.map { $0.discussion })
            guard discussions.count == 1 else {
                throw DeleteMessagesJSON.makeError(message: "Could not construct DeleteMessagesJSON. Expecting one discussion, got \(discussions.count)")
            }
            discussion = discussions.first!
        }

        self.messagesToDelete = persistedMessagesToDelete.compactMap { $0.toMessageReferenceJSON() }
        switch try discussion.kind {
        case .oneToOne:
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        case .groupV1(withContactGroup: let contactGroup):
            guard let groupUid = contactGroup?.groupUid,
                  let groupOwnerIdentity = contactGroup?.ownerIdentity,
                  let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) else {
                throw DeleteMessagesJSON.makeError(message: "Could not determine group v1 id")
            }
            self.groupV1Identifier = (groupUid, groupOwner)
            self.groupV2Identifier = nil
        case .groupV2(withGroup: let group):
            guard let groupV2Identifier = group?.groupIdentifier else {
                throw DeleteMessagesJSON.makeError(message: "Could not determine group v2 id")
            }
            self.groupV1Identifier = nil
            self.groupV2Identifier = groupV2Identifier
        }
        
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let groupV1Identifier = groupV1Identifier {
            try container.encode(groupV1Identifier.groupUid.raw, forKey: .groupUid)
            try container.encode(groupV1Identifier.groupOwner.getIdentity(), forKey: .groupOwner)
        }
        if let groupV2Identifier = groupV2Identifier {
            try container.encode(groupV2Identifier, forKey: .groupV2Identifier)
        }
        try container.encode(messagesToDelete, forKey: .messagesToDelete)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        let groupUidRaw = try values.decodeIfPresent(Data.self, forKey: .groupUid)
        let groupOwnerIdentity = try values.decodeIfPresent(Data.self, forKey: .groupOwner)
        
        let groupV2Identifier = try values.decodeIfPresent(Data.self, forKey: .groupV2Identifier)
        
        if let groupUidRaw = groupUidRaw,
            let groupOwnerIdentity = groupOwnerIdentity,
            let groupUid = UID(uid: groupUidRaw),
            let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) {
            self.groupV1Identifier = (groupUid, groupOwner)
            self.groupV2Identifier = nil
        } else if let groupV2Identifier = groupV2Identifier {
            self.groupV1Identifier = nil
            self.groupV2Identifier = groupV2Identifier
        } else {
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        }

        self.messagesToDelete = try values.decode([MessageReferenceJSON].self, forKey: .messagesToDelete)
        
    }

}


public struct DeleteDiscussionJSON: Codable {
    
    private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "DeleteDiscussionJSON")

    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { DeleteDiscussionJSON.makeError(message: message) }

    let groupV1Identifier: (groupUid: UID, groupOwner: ObvCryptoId)?
    let groupV2Identifier: Data?

    public var groupIdentifier: GroupIdentifier? {
        if let groupV1Identifier = groupV1Identifier {
            return .groupV1(groupV1Identifier: groupV1Identifier)
        } else if let groupV2Identifier = groupV2Identifier {
            return .groupV2(groupV2Identifier: groupV2Identifier)
        } else {
            return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case groupUid = "guid" // For group V1
        case groupOwner = "go" // For group V1
        case groupV2Identifier = "gid2"
    }
    
    public init(persistedDiscussionToDelete discussion: PersistedDiscussion) throws {
        switch try discussion.kind {
        case .oneToOne:
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        case .groupV1(withContactGroup: let contactGroup):
            guard let groupUid = contactGroup?.groupUid,
                  let groupOwnerIdentity = contactGroup?.ownerIdentity,
                  let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) else {
                throw DeleteDiscussionJSON.makeError(message: "Could not determine group v1 id")
            }
            self.groupV1Identifier = (groupUid, groupOwner)
            self.groupV2Identifier = nil
        case .groupV2(withGroup: let group):
            guard let groupV2Identifier = group?.groupIdentifier else {
                throw DeleteDiscussionJSON.makeError(message: "Could not determine group v2 id")
            }
            self.groupV1Identifier = nil
            self.groupV2Identifier = groupV2Identifier
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let groupV1Identifier = groupV1Identifier {
            try container.encode(groupV1Identifier.groupUid.raw, forKey: .groupUid)
            try container.encode(groupV1Identifier.groupOwner.getIdentity(), forKey: .groupOwner)
        }
        if let groupV2Identifier = groupV2Identifier {
            try container.encode(groupV2Identifier, forKey: .groupV2Identifier)
        }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        let groupUidRaw = try values.decodeIfPresent(Data.self, forKey: .groupUid)
        let groupOwnerIdentity = try values.decodeIfPresent(Data.self, forKey: .groupOwner)
        
        let groupV2Identifier = try values.decodeIfPresent(Data.self, forKey: .groupV2Identifier)
        
        if let groupUidRaw = groupUidRaw,
            let groupOwnerIdentity = groupOwnerIdentity,
            let groupUid = UID(uid: groupUidRaw),
            let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) {
            self.groupV1Identifier = (groupUid, groupOwner)
            self.groupV2Identifier = nil
        } else if let groupV2Identifier = groupV2Identifier {
            self.groupV1Identifier = nil
            self.groupV2Identifier = groupV2Identifier
        } else {
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        }

    }

}


public struct QuerySharedSettingsJSON: Codable, ObvErrorMaker {
    
    public static let errorDomain = "QuerySharedSettingsJSON"

    public let groupV2Identifier: Data
    public let knownSharedSettingsVersion: Int?
    public let knownSharedExpiration: ExpirationJSON?

    public init(groupV2Identifier: Data, knownSharedSettingsVersion: Int?, knownSharedExpiration: ExpirationJSON?) {
        self.groupV2Identifier = groupV2Identifier
        self.knownSharedSettingsVersion = knownSharedSettingsVersion
        self.knownSharedExpiration = knownSharedExpiration
    }
    
    enum CodingKeys: String, CodingKey {
        case groupV2Identifier = "gid2"
        case knownSharedSettingsVersion = "ksv"
        case knownSharedExpiration = "exp"
    }
    
}


public struct UpdateMessageJSON: Codable {
    
    private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "UpdateMessageJSON")

    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { UpdateMessageJSON.makeError(message: message) }

    public let messageToEdit: MessageReferenceJSON
    let groupV1Identifier: (groupUid: UID, groupOwner: ObvCryptoId)?
    let groupV2Identifier: Data?
    public let newTextBody: String?
    public let userMentions: [MessageJSON.UserMention]

    public var groupIdentifier: GroupIdentifier? {
        if let groupV1Identifier = groupV1Identifier {
            return .groupV1(groupV1Identifier: groupV1Identifier)
        } else if let groupV2Identifier = groupV2Identifier {
            return .groupV2(groupV2Identifier: groupV2Identifier)
        } else {
            return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case groupUid = "guid" // For group V1
        case groupOwner = "go" // For group V1
        case groupV2Identifier = "gid2"
        case body = "body"
        case messageToEdit = "ref"
        case userMentions = "um"
    }
    
    public init(persistedMessageSentToEdit msg: PersistedMessageSent, newTextBody: String?, userMentions: [MessageJSON.UserMention]) throws {
        self.newTextBody = newTextBody
        guard let msgRef = msg.toMessageReferenceJSON() else {
            throw UpdateMessageJSON.makeError(message: "Could not create MessageReferenceJSON")
        }
        self.messageToEdit = msgRef
        switch try msg.discussion.kind {
        case .oneToOne:
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        case .groupV1(withContactGroup: let contactGroup):
            guard let groupUid = contactGroup?.groupUid,
                  let groupOwnerIdentity = contactGroup?.ownerIdentity,
                  let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) else {
                throw UpdateMessageJSON.makeError(message: "Could not determine group v1 uid")
            }
            self.groupV1Identifier = (groupUid, groupOwner)
            self.groupV2Identifier = nil
        case .groupV2(withGroup: let group):
            guard let groupV2Identifier = group?.groupIdentifier else {
                throw UpdateMessageJSON.makeError(message: "Could not determine group v2 uid")
            }
            self.groupV1Identifier = nil
            self.groupV2Identifier = groupV2Identifier
        }
        self.userMentions = userMentions
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let groupV1Identifier = groupV1Identifier {
            try container.encode(groupV1Identifier.groupUid.raw, forKey: .groupUid)
            try container.encode(groupV1Identifier.groupOwner.getIdentity(), forKey: .groupOwner)
        }
        if let groupV2Identifier = groupV2Identifier {
            try container.encode(groupV2Identifier, forKey: .groupV2Identifier)
        }
        if let newTextBody = newTextBody {
            try container.encode(newTextBody, forKey: .body)
        }
        try container.encode(messageToEdit, forKey: .messageToEdit)

        if let newTextBody,
            userMentions.isEmpty == false {
            if #available(iOS 15, *) {
                let configuration = MessageJSON.UserMention.Configuration(message: newTextBody)

                try container.encode(userMentions, forKey: .userMentions, configuration: configuration)
            } else {
                let encoder = container.superEncoder(forKey: .userMentions)

                var _innerContainer = encoder.unkeyedContainer()

                for aMention in userMentions {
                    let _currentDecoder = _innerContainer.superEncoder()

                    try aMention.encode(to: _currentDecoder, messageBody: newTextBody)
                }
            }
        }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        let groupUidRaw = try values.decodeIfPresent(Data.self, forKey: .groupUid)
        let groupOwnerIdentity = try values.decodeIfPresent(Data.self, forKey: .groupOwner)
        
        let groupV2Identifier = try values.decodeIfPresent(Data.self, forKey: .groupV2Identifier)
        
        if let groupUidRaw = groupUidRaw,
            let groupOwnerIdentity = groupOwnerIdentity,
            let groupUid = UID(uid: groupUidRaw),
            let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) {
            self.groupV1Identifier = (groupUid, groupOwner)
            self.groupV2Identifier = nil
        } else if let groupV2Identifier = groupV2Identifier {
            self.groupV1Identifier = nil
            self.groupV2Identifier = groupV2Identifier
        } else {
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        }

        let newTextBody = try values.decodeIfPresent(String.self, forKey: .body)
        self.newTextBody = newTextBody
        self.messageToEdit = try values.decode(MessageReferenceJSON.self, forKey: .messageToEdit)

        if let newTextBody,
           values.contains(.userMentions),
           try values.decodeNil(forKey: .userMentions) == false {
            let decodingBlock: (Decoder) throws -> MessageJSON.UserMention?

            if #available(iOS 15, *) {
                let configuration = MessageJSON.UserMention.Configuration(message: newTextBody)

                decodingBlock = { decoder -> MessageJSON.UserMention? in
                    do {
                        return try MessageJSON.UserMention(from: decoder, configuration: configuration)
                    } catch let error as MessageJSON.UserMention.MentionError.DecodingError {
                        assert(false, "failed to decode with error: \(error)") //used for debugging
                        return nil
                    }
                }
            } else {
                decodingBlock = { decoder -> MessageJSON.UserMention? in
                    do {
                        return try MessageJSON.UserMention(from: decoder, messageBody: newTextBody)
                    } catch let error as MessageJSON.UserMention.MentionError.DecodingError {
                        assert(false, "failed to decode with error: \(error)") //used for debugging
                        return nil
                    }
                }
            }

            var _storage: [MessageJSON.UserMention] = []

            var container = try values.nestedUnkeyedContainer(forKey: .userMentions)

            while !container.isAtEnd {
                if let decodedMention = try decodingBlock(container.superDecoder()) {
                    _storage.append(decodedMention)
                }
            }

            userMentions = _storage
        } else {
            userMentions = []
        }
    }

}

public struct ReactionJSON: Codable {

    private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "ReactionJSON")

    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { ReactionJSON.makeError(message: message) }

    public let messageReference: MessageReferenceJSON
    public let groupV1Identifier: (groupUid: UID, groupOwner: ObvCryptoId)?
    public let groupV2Identifier: Data?
    public let emoji: String?

    public var groupIdentifier: GroupIdentifier? {
        if let groupV1Identifier = groupV1Identifier {
            return .groupV1(groupV1Identifier: groupV1Identifier)
        } else if let groupV2Identifier = groupV2Identifier {
            return .groupV2(groupV2Identifier: groupV2Identifier)
        } else {
            return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case groupUid = "guid" // For group V1
        case groupOwner = "go" // For group V1
        case groupV2Identifier = "gid2"
        case emoji = "reac"
        case messageReference = "ref"
    }

    public init(persistedMessageToReact msg: PersistedMessage, emoji: String?) throws {
        self.emoji = emoji
        guard let msgRef = msg.toMessageReferenceJSON() else {
            throw ReactionJSON.makeError(message: "Could not create MessageReferenceJSON")
        }
        self.messageReference = msgRef
        switch try msg.discussion.kind {
        case .oneToOne:
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        case .groupV1(withContactGroup: let contactGroup):
            guard let groupUid = contactGroup?.groupUid,
                  let groupOwnerIdentity = contactGroup?.ownerIdentity,
                  let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) else {
                      throw ReactionJSON.makeError(message: "Could not determine group v1 uid")
                  }
            self.groupV1Identifier = (groupUid, groupOwner)
            self.groupV2Identifier = nil
        case .groupV2(withGroup: let group):
            guard let groupV2Identifier = group?.groupIdentifier else {
                throw ReactionJSON.makeError(message: "Could not determine group v2 uid")
            }
            self.groupV1Identifier = nil
            self.groupV2Identifier = groupV2Identifier
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let groupV1Identifier = groupV1Identifier {
            try container.encode(groupV1Identifier.groupUid.raw, forKey: .groupUid)
            try container.encode(groupV1Identifier.groupOwner.getIdentity(), forKey: .groupOwner)
        }
        if let groupV2Identifier = groupV2Identifier {
            try container.encode(groupV2Identifier, forKey: .groupV2Identifier)
        }
        try container.encodeIfPresent(emoji, forKey: .emoji)
        try container.encode(messageReference, forKey: .messageReference)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        let groupUidRaw = try values.decodeIfPresent(Data.self, forKey: .groupUid)
        let groupOwnerIdentity = try values.decodeIfPresent(Data.self, forKey: .groupOwner)

        let groupV2Identifier = try values.decodeIfPresent(Data.self, forKey: .groupV2Identifier)
        
        if let groupUidRaw = groupUidRaw,
            let groupOwnerIdentity = groupOwnerIdentity,
            let groupUid = UID(uid: groupUidRaw),
            let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) {
            self.groupV1Identifier = (groupUid, groupOwner)
            self.groupV2Identifier = nil
        } else if let groupV2Identifier = groupV2Identifier {
            self.groupV1Identifier = nil
            self.groupV2Identifier = groupV2Identifier
        } else {
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        }

        self.emoji = try values.decodeIfPresent(String.self, forKey: .emoji)
        self.messageReference = try values.decode(MessageReferenceJSON.self, forKey: .messageReference)
    }

}


public struct ScreenCaptureDetectionJSON: Codable, ObvErrorMaker {
    
    private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "DiscussionSharedConfigurationJSON")
    public static let errorDomain = "ScreenCaptureDetectionJSON"

    let groupV1Identifier: (groupUid: UID, groupOwner: ObvCryptoId)?
    let groupV2Identifier: Data?

    public var groupIdentifier: GroupIdentifier? {
        if let groupV1Identifier = groupV1Identifier {
            return .groupV1(groupV1Identifier: groupV1Identifier)
        } else if let groupV2Identifier = groupV2Identifier {
            return .groupV2(groupV2Identifier: groupV2Identifier)
        } else {
            return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case groupUid = "guid" // For group V1
        case groupOwner = "go" // For group V1
        case groupV2Identifier = "gid2"
    }

    public init() {
        self.groupV1Identifier = nil
        self.groupV2Identifier = nil
    }

    public init(groupV1Identifier: (groupUid: UID, groupOwner: ObvCryptoId)) {
        self.groupV1Identifier = groupV1Identifier
        self.groupV2Identifier = nil
    }

    public init(groupV2Identifier: Data) {
        self.groupV1Identifier = nil
        self.groupV2Identifier = groupV2Identifier
    }

    func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    static func jsonDecode(_ data: Data) throws -> ScreenCaptureDetectionJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(ScreenCaptureDetectionJSON.self, from: data)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let groupV1Identifier = groupV1Identifier {
            try container.encode(groupV1Identifier.groupUid.raw, forKey: .groupUid)
            try container.encode(groupV1Identifier.groupOwner.getIdentity(), forKey: .groupOwner)
        }
        if let groupV2Identifier = groupV2Identifier {
            try container.encode(groupV2Identifier, forKey: .groupV2Identifier)
        }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        let groupUidRaw = try values.decodeIfPresent(Data.self, forKey: .groupUid)
        let groupOwnerIdentity = try values.decodeIfPresent(Data.self, forKey: .groupOwner)
        
        let groupV2Identifier = try values.decodeIfPresent(Data.self, forKey: .groupV2Identifier)
        
        if let groupUidRaw = groupUidRaw,
            let groupOwnerIdentity = groupOwnerIdentity,
            let groupUid = UID(uid: groupUidRaw),
            let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) {
            self.groupV1Identifier = (groupUid, groupOwner)
            self.groupV2Identifier = nil
        } else if let groupV2Identifier = groupV2Identifier {
            self.groupV1Identifier = nil
            self.groupV2Identifier = groupV2Identifier
        } else {
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        }
    }

}