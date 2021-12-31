/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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


struct PersistedItemJSON: Codable {
    
    let message: MessageJSON?
    let returnReceipt: ReturnReceiptJSON?
    let webrtcMessage: WebRTCMessageJSON?
    let discussionSharedConfiguration: DiscussionSharedConfigurationJSON?
    let deleteMessagesJSON: DeleteMessagesJSON?
    let deleteDiscussionJSON: DeleteDiscussionJSON?
    let updateMessageJSON: UpdateMessageJSON?
    let reactionJSON: ReactionJSON?

    enum CodingKeys: String, CodingKey {
        case message = "message"
        case returnReceipt = "rr"
        case webrtcMessage = "rtc"
        case discussionSharedConfiguration = "settings"
        case deleteMessagesJSON = "delm"
        case deleteDiscussionJSON = "deld"
        case updateMessageJSON = "upm"
        case reactionJSON = "reacm"
    }
    
    init(messageJSON: MessageJSON) {
        self.message = messageJSON
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
    }
    
    init(returnReceiptJSON: ReturnReceiptJSON) {
        self.message = nil
        self.returnReceipt = returnReceiptJSON
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
    }
    
    init(messageJSON: MessageJSON, returnReceiptJSON: ReturnReceiptJSON) {
        self.message = messageJSON
        self.returnReceipt = returnReceiptJSON
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
    }
    
    init(webrtcMessage: WebRTCMessageJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = webrtcMessage
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
    }
    
    init(discussionSharedConfiguration: DiscussionSharedConfigurationJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = discussionSharedConfiguration
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
    }
    
    init(deleteMessagesJSON: DeleteMessagesJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = deleteMessagesJSON
        self.deleteDiscussionJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
    }

    init(deleteDiscussionJSON: DeleteDiscussionJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = deleteDiscussionJSON
        self.updateMessageJSON = nil
        self.reactionJSON = nil
    }

    init(updateMessageJSON: UpdateMessageJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.updateMessageJSON = updateMessageJSON
        self.reactionJSON = nil
    }

    init(reactionJSON: ReactionJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = reactionJSON
    }

    
    func encode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> PersistedItemJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(PersistedItemJSON.self, from: data)
    }

}


struct DiscussionSharedConfigurationJSON: Codable {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "DiscussionSharedConfigurationJSON")
    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { DiscussionSharedConfigurationJSON.makeError(message: message) }

    let version: Int
    let expiration: ExpirationJSON
    let groupId: (groupUid: UID, groupOwner: ObvCryptoId)?

    enum CodingKeys: String, CodingKey {
        case version = "version"
        case expiration = "exp"
        case groupUid = "guid"
        case groupOwner = "go"
    }

    init(version: Int, expiration: ExpirationJSON, groupId: (groupUid: UID, groupOwner: ObvCryptoId)?) {
        self.version = version
        self.expiration = expiration
        self.groupId = groupId
    }
    
    func encode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> DiscussionSharedConfigurationJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(DiscussionSharedConfigurationJSON.self, from: data)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let groupId = groupId {
            try container.encode(groupId.groupUid.raw, forKey: .groupUid)
            try container.encode(groupId.groupOwner.getIdentity(), forKey: .groupOwner)
        }
        try container.encode(version, forKey: .version)
        try container.encode(expiration, forKey: .expiration)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try values.decode(Int.self, forKey: .version)
        if let expiration = try values.decodeIfPresent(ExpirationJSON.self, forKey: .expiration) {
            self.expiration = expiration
        } else {
            self.expiration = ExpirationJSON(readOnce: false, visibilityDuration: nil, existenceDuration: nil)
        }
        
        let groupUidRaw = try values.decodeIfPresent(Data.self, forKey: .groupUid)
        let groupOwnerIdentity = try values.decodeIfPresent(Data.self, forKey: .groupOwner)
        
        if groupUidRaw == nil && groupOwnerIdentity == nil {
            self.groupId = nil
        } else if let groupUidRaw = groupUidRaw,
            let groupOwnerIdentity = groupOwnerIdentity,
            let groupUid = UID(uid: groupUidRaw),
            let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) {
            self.groupId = (groupUid, groupOwner)
        } else {
            os_log("Could determine if the message is part of a group or not. Discarding the message.", log: log, type: .error)
            throw DiscussionSharedConfigurationJSON.makeError(message: "Could determine if the message is part of a group or not. Discarding the message.")
        }
    }

}


struct ReturnReceiptJSON: Codable {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "ReturnReceiptJSON")

    enum Status: Int {
        case delivered = 1
        case read = 2
    }
    
    let nonce: Data
    let key: Data
    
    var elements: (nonce: Data, key: Data) {
        return (nonce, key)
    }

    enum CodingKeys: String, CodingKey {
        case nonce = "nonce"
        case key = "key"
    }
    
    init(returnReceiptElements: (nonce: Data, key: Data)) {
        self.nonce = returnReceiptElements.nonce
        self.key = returnReceiptElements.key
    }
    
    init(nonce: Data, key: Data) {
        self.nonce = nonce
        self.key = key
    }
        
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.nonce = try values.decode(Data.self, forKey: .nonce)
        self.key = try values.decode(Data.self, forKey: .key)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nonce, forKey: .nonce)
        try container.encode(key, forKey: .key)
    }
    
    func encode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
    
    static func decode(_ data: Data) throws -> ReturnReceiptJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(ReturnReceiptJSON.self, from: data)
    }
}


struct ExpirationJSON: Codable {

    let readOnce: Bool
    let visibilityDuration: TimeInterval?
    let existenceDuration: TimeInterval?

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

    init(from decoder: Decoder) throws {
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

    func encode(to encoder: Encoder) throws {
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

    func encode() throws -> Data {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        return data
    }

    static func decode(_ data: Data) throws -> ExpirationJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(ExpirationJSON.self, from: data)
    }

}

struct MessageJSON: Codable {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "MessageJSON")
    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { MessageJSON.makeError(message: message) }

    let senderSequenceNumber: Int
    let senderThreadIdentifier: UUID
    let body: String?
    let groupId: (groupUid: UID, groupOwner: ObvCryptoId)?
    let replyTo: MessageReferenceJSON?
    let expiration: ExpirationJSON?

    enum CodingKeys: String, CodingKey {
        case senderSequenceNumber = "ssn"
        case senderThreadIdentifier = "sti"
        case groupUid = "guid"
        case groupOwner = "go"
        case body = "body"
        case replyTo = "re"
        case expiration = "exp"
    }
    
    init(senderSequenceNumber: Int, senderThreadIdentifier: UUID, body: String?, groupId: (groupUid: UID, groupOwner: ObvCryptoId)?, replyTo: MessageReferenceJSON?, expiration: ExpirationJSON?) {
        self.senderSequenceNumber = senderSequenceNumber
        self.senderThreadIdentifier = senderThreadIdentifier
        self.body = body
        self.groupId = groupId
        self.replyTo = replyTo
        self.expiration = expiration
    }
        
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.senderSequenceNumber = try values.decode(Int.self, forKey: .senderSequenceNumber)
        self.senderThreadIdentifier = try values.decode(UUID.self, forKey: .senderThreadIdentifier)
        self.body = try values.decodeIfPresent(String.self, forKey: .body)
        
        let groupUidRaw = try values.decodeIfPresent(Data.self, forKey: .groupUid)
        let groupOwnerIdentity = try values.decodeIfPresent(Data.self, forKey: .groupOwner)
        
        if groupUidRaw == nil && groupOwnerIdentity == nil {
            self.groupId = nil
        } else if let groupUidRaw = groupUidRaw,
            let groupOwnerIdentity = groupOwnerIdentity,
            let groupUid = UID(uid: groupUidRaw),
            let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) {
            self.groupId = (groupUid, groupOwner)
        } else {
            os_log("Could determine if the message is part of a group or not. Discarding the message.", log: log, type: .error)
            throw MessageJSON.makeError(message: "Could determine if the message is part of a group or not. Discarding the message.")
        }
        self.replyTo = try values.decodeIfPresent(MessageReferenceJSON.self, forKey: .replyTo)
        self.expiration = try values.decodeIfPresent(ExpirationJSON.self, forKey: .expiration)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let groupId = groupId {
            try container.encode(groupId.groupUid.raw, forKey: .groupUid)
            try container.encode(groupId.groupOwner.getIdentity(), forKey: .groupOwner)
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
    }
    
    func encode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
    
    static func decode(_ data: Data) throws -> MessageJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(MessageJSON.self, from: data)
    }
}


struct MessageReferenceJSON: Codable {
    
    let senderSequenceNumber: Int
    let senderThreadIdentifier: UUID
    let senderIdentifier: Data
    
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
    
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.senderSequenceNumber = try values.decode(Int.self, forKey: .senderSequenceNumber)
        self.senderThreadIdentifier = try values.decode(UUID.self, forKey: .senderThreadIdentifier)
        self.senderIdentifier = try values.decode(Data.self, forKey: .senderIdentifier)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(senderSequenceNumber, forKey: .senderSequenceNumber)
        try container.encode(senderThreadIdentifier, forKey: .senderThreadIdentifier)
        try container.encode(senderIdentifier, forKey: .senderIdentifier)
    }
    
}


struct DeleteMessagesJSON: Codable {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "deleteMessagesJSON")

    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { DeleteMessagesJSON.makeError(message: message) }

    let groupId: (groupUid: UID, groupOwner: ObvCryptoId)?
    let messagesToDelete: [MessageReferenceJSON]
    
    enum CodingKeys: String, CodingKey {
        case groupUid = "guid"
        case groupOwner = "go"
        case messagesToDelete = "refs"
    }
    
    init(persistedMessagesToDelete: [PersistedMessage]) throws {
        
        guard !persistedMessagesToDelete.isEmpty else { throw DeleteMessagesJSON.makeError(message: "No message to delete") }
        
        let discussion: PersistedDiscussion
        do {
            let discussions = Set(persistedMessagesToDelete.map { $0.discussion })
            guard discussions.count == 1 else {
                throw DeleteMessagesJSON.makeError(message: "Could not construct DeleteMessagesJSON. Expecting one discussion, got \(discussions.count)")
            }
            discussion = discussions.first!
        }

        self.messagesToDelete = persistedMessagesToDelete.compactMap { $0.toReplyToJSON() }
        if let groupDiscussion = discussion as? PersistedGroupDiscussion {
            guard let groupUid = groupDiscussion.contactGroup?.groupUid,
                  let groupOwnerIdentity = groupDiscussion.contactGroup?.ownerIdentity,
                  let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) else {
                throw DeleteMessagesJSON.makeError(message: "Could not determine group uid")
            }
            self.groupId = (groupUid, groupOwner)
        } else {
            self.groupId = nil
        }
        
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let groupId = groupId {
            try container.encode(groupId.groupUid.raw, forKey: .groupUid)
            try container.encode(groupId.groupOwner.getIdentity(), forKey: .groupOwner)
        }
        try container.encode(messagesToDelete, forKey: .messagesToDelete)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        let groupUidRaw = try values.decodeIfPresent(Data.self, forKey: .groupUid)
        let groupOwnerIdentity = try values.decodeIfPresent(Data.self, forKey: .groupOwner)
        
        if groupUidRaw == nil && groupOwnerIdentity == nil {
            self.groupId = nil
        } else if let groupUidRaw = groupUidRaw,
            let groupOwnerIdentity = groupOwnerIdentity,
            let groupUid = UID(uid: groupUidRaw),
            let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) {
            self.groupId = (groupUid, groupOwner)
        } else {
            os_log("Could determine if the message is part of a group or not. Discarding the message.", log: log, type: .error)
            throw DeleteMessagesJSON.makeError(message: "Could determine if the message is part of a group or not. Discarding the message.")
        }

        self.messagesToDelete = try values.decode([MessageReferenceJSON].self, forKey: .messagesToDelete)
        
    }

}


struct DeleteDiscussionJSON: Codable {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "DeleteDiscussionJSON")

    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { DeleteDiscussionJSON.makeError(message: message) }

    let groupId: (groupUid: UID, groupOwner: ObvCryptoId)?
    
    enum CodingKeys: String, CodingKey {
        case groupUid = "guid"
        case groupOwner = "go"
    }
    
    init(persistedDiscussionToDelete discussion: PersistedDiscussion) throws {
        if let groupDiscussion = discussion as? PersistedGroupDiscussion {
            guard let groupUid = groupDiscussion.contactGroup?.groupUid,
                  let groupOwnerIdentity = groupDiscussion.contactGroup?.ownerIdentity,
                  let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) else {
                throw DeleteDiscussionJSON.makeError(message: "Could not determine group uid")
            }
            self.groupId = (groupUid, groupOwner)
        } else {
            self.groupId = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let groupId = groupId {
            try container.encode(groupId.groupUid.raw, forKey: .groupUid)
            try container.encode(groupId.groupOwner.getIdentity(), forKey: .groupOwner)
        }
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        let groupUidRaw = try values.decodeIfPresent(Data.self, forKey: .groupUid)
        let groupOwnerIdentity = try values.decodeIfPresent(Data.self, forKey: .groupOwner)
        
        if groupUidRaw == nil && groupOwnerIdentity == nil {
            self.groupId = nil
        } else if let groupUidRaw = groupUidRaw,
            let groupOwnerIdentity = groupOwnerIdentity,
            let groupUid = UID(uid: groupUidRaw),
            let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) {
            self.groupId = (groupUid, groupOwner)
        } else {
            os_log("Could determine if the message is part of a group or not. Discarding the message.", log: log, type: .error)
            throw DeleteDiscussionJSON.makeError(message: "Could determine if the message is part of a group or not. Discarding the message.")
        }
    }

}


struct UpdateMessageJSON: Codable {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "UpdateMessageJSON")

    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { UpdateMessageJSON.makeError(message: message) }

    let messageToEdit: MessageReferenceJSON
    let groupId: (groupUid: UID, groupOwner: ObvCryptoId)?
    let newTextBody: String?

    enum CodingKeys: String, CodingKey {
        case groupUid = "guid"
        case groupOwner = "go"
        case body = "body"
        case messageToEdit = "ref"
    }
    
    init(persistedMessageSentToEdit msg: PersistedMessageSent, newTextBody: String?) throws {
        self.newTextBody = newTextBody
        guard let msgRef = msg.toReplyToJSON() else {
            throw UpdateMessageJSON.makeError(message: "Could not create MessageReferenceJSON")
        }
        self.messageToEdit = msgRef
        if let groupDiscussion = msg.discussion as? PersistedGroupDiscussion {
            guard let groupUid = groupDiscussion.contactGroup?.groupUid,
                  let groupOwnerIdentity = groupDiscussion.contactGroup?.ownerIdentity,
                  let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) else {
                throw UpdateMessageJSON.makeError(message: "Could not determine group uid")
            }
            self.groupId = (groupUid, groupOwner)
        } else {
            self.groupId = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let groupId = groupId {
            try container.encode(groupId.groupUid.raw, forKey: .groupUid)
            try container.encode(groupId.groupOwner.getIdentity(), forKey: .groupOwner)
        }
        if let newTextBody = newTextBody {
            try container.encode(newTextBody, forKey: .body)
        }
        try container.encode(messageToEdit, forKey: .messageToEdit)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        let groupUidRaw = try values.decodeIfPresent(Data.self, forKey: .groupUid)
        let groupOwnerIdentity = try values.decodeIfPresent(Data.self, forKey: .groupOwner)
        
        if groupUidRaw == nil && groupOwnerIdentity == nil {
            self.groupId = nil
        } else if let groupUidRaw = groupUidRaw,
            let groupOwnerIdentity = groupOwnerIdentity,
            let groupUid = UID(uid: groupUidRaw),
            let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) {
            self.groupId = (groupUid, groupOwner)
        } else {
            os_log("Could determine if the message is part of a group or not. Discarding the message.", log: log, type: .error)
            throw UpdateMessageJSON.makeError(message: "Could determine if the message is part of a group or not. Discarding the message.")
        }
        self.newTextBody = try values.decodeIfPresent(String.self, forKey: .body)
        self.messageToEdit = try values.decode(MessageReferenceJSON.self, forKey: .messageToEdit)
    }

}

struct ReactionJSON: Codable {

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "ReactionJSON")

    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { ReactionJSON.makeError(message: message) }

    let messageReference: MessageReferenceJSON
    let groupId: (groupUid: UID, groupOwner: ObvCryptoId)?
    let emoji: String?

    enum CodingKeys: String, CodingKey {
        case groupUid = "guid"
        case groupOwner = "go"
        case emoji = "reac"
        case messageReference = "ref"
    }

    init(persistedMessageToReact msg: PersistedMessage, emoji: String?) throws {
        self.emoji = emoji
        guard let msgRef = msg.toReplyToJSON() else {
            throw ReactionJSON.makeError(message: "Could not create MessageReferenceJSON")
        }
        self.messageReference = msgRef
        if let groupDiscussion = msg.discussion as? PersistedGroupDiscussion {
            guard let groupUid = groupDiscussion.contactGroup?.groupUid,
                  let groupOwnerIdentity = groupDiscussion.contactGroup?.ownerIdentity,
                  let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) else {
                      throw ReactionJSON.makeError(message: "Could not determine group uid")
                  }
            self.groupId = (groupUid, groupOwner)
        } else {
            self.groupId = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let groupId = groupId {
            try container.encode(groupId.groupUid.raw, forKey: .groupUid)
            try container.encode(groupId.groupOwner.getIdentity(), forKey: .groupOwner)
        }
        try container.encodeIfPresent(emoji, forKey: .emoji)
        try container.encode(messageReference, forKey: .messageReference)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        let groupUidRaw = try values.decodeIfPresent(Data.self, forKey: .groupUid)
        let groupOwnerIdentity = try values.decodeIfPresent(Data.self, forKey: .groupOwner)

        if groupUidRaw == nil && groupOwnerIdentity == nil {
            self.groupId = nil
        } else if let groupUidRaw = groupUidRaw,
                  let groupOwnerIdentity = groupOwnerIdentity,
                  let groupUid = UID(uid: groupUidRaw),
                  let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) {
            self.groupId = (groupUid, groupOwner)
        } else {
            os_log("Could determine if the message is part of a group or not. Discarding the message.", log: log, type: .error)
            throw ReactionJSON.makeError(message: "Could determine if the message is part of a group or not. Discarding the message.")
        }
        self.emoji = try values.decodeIfPresent(String.self, forKey: .emoji)
        self.messageReference = try values.decode(MessageReferenceJSON.self, forKey: .messageReference)
    }

}
