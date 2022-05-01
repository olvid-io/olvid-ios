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

struct WebRTCDataChannelMessageJSON: Codable {

    enum MessageType: Int, Codable, CustomStringConvertible {
        case muted = 0
        case updateParticipant = 1
        case relayMessage = 2
        case relayedMessage = 3
        case hangedUpMessage = 4

        var description: String {
            switch self {
            case .muted: return "muted"
            case .updateParticipant: return "updateParticipant"
            case .relayMessage: return "relayMessage"
            case .relayedMessage: return "relayedMessage"
            case .hangedUpMessage: return "hangedUpMessage"
            }
        }
    }

    let messageType: MessageType
    let serializedMessage: String

    enum CodingKeys: String, CodingKey {
        case messageType = "t"
        case serializedMessage = "m"
    }

    func encode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    static func decode(data: Data) throws -> Self {
        let decoder = JSONDecoder()
        return try decoder.decode(Self.self, from: data)
    }

}

protocol WebRTCDataChannelInnerMessageJSON: Codable {

    var messageType: WebRTCDataChannelMessageJSON.MessageType { get }

}

extension WebRTCDataChannelInnerMessageJSON {

    static func makeError(message: String) -> Error {
        NSError(domain: String(describing: Self.self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message])
    }

    func encode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    static func decode(serializedMessage: String) throws -> Self {
        guard let data = serializedMessage.data(using: .utf8) else {
            throw Self.makeError(message: "Could not turn serialized message into data")
        }
        let decoder = JSONDecoder()
        return try decoder.decode(Self.self, from: data)
    }

    func embedInWebRTCDataChannelMessageJSON() throws -> WebRTCDataChannelMessageJSON {
        let serializedMessageAsData = try self.encode()
        guard let serializedMessage = String(data: serializedMessageAsData, encoding: .utf8) else {
            throw Self.makeError(message: "Could not serialize message")
        }
        return WebRTCDataChannelMessageJSON(messageType: messageType,
                                            serializedMessage: serializedMessage)
    }

}

struct MutedMessageJSON: WebRTCDataChannelInnerMessageJSON {

    var messageType: WebRTCDataChannelMessageJSON.MessageType { .muted }

    let muted: Bool

}

struct ContactBytesAndNameJSON: Codable {

    let byteContactIdentity: Data
    let displayName: String
    private let rawGatheringPolicy: Int? // Optional to be compatible with previous versions where the gathering policy was hardcoded

    enum CodingKeys: String, CodingKey {
        case byteContactIdentity = "id"
        case displayName = "name"
        case rawGatheringPolicy = "gp"
    }

    init(byteContactIdentity: Data, displayName: String, gatheringPolicy: GatheringPolicy) {
        self.byteContactIdentity = byteContactIdentity
        self.displayName = displayName
        self.rawGatheringPolicy = gatheringPolicy.rawValue
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.byteContactIdentity = try values.decode(Data.self, forKey: .byteContactIdentity)
        self.displayName = try values.decode(String.self, forKey: .displayName)
        self.rawGatheringPolicy = try values.decodeIfPresent(Int.self, forKey: .rawGatheringPolicy)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(byteContactIdentity, forKey: .byteContactIdentity)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(rawGatheringPolicy, forKey: .rawGatheringPolicy)
    }

    var gatheringPolicy: GatheringPolicy? {
        guard let rawGatheringPolicy = rawGatheringPolicy else { return nil }
        return GatheringPolicy(rawValue: rawGatheringPolicy)
    }

}

struct UpdateParticipantsMessageJSON: WebRTCDataChannelInnerMessageJSON {

    var messageType: WebRTCDataChannelMessageJSON.MessageType { .updateParticipant }

    let callParticipants: [ContactBytesAndNameJSON]

    enum CodingKeys: String, CodingKey {
        case callParticipants = "cp"
    }

    init(callParticipants: [CallParticipant]) async {
        var callParticipants_: [ContactBytesAndNameJSON] = []
        for callParticipant in callParticipants {
            let callParticipantState = await callParticipant.getPeerState()
            guard callParticipantState == .connected || callParticipantState == .reconnecting else { continue }
            let remoteCryptoId = callParticipant.remoteCryptoId
            let displayName = callParticipant.fullDisplayName
            guard let gatheringPolicy = await callParticipant.gatheringPolicy else { continue }
            callParticipants_.append(ContactBytesAndNameJSON(byteContactIdentity: remoteCryptoId.getIdentity(), displayName: displayName, gatheringPolicy: gatheringPolicy))
        }
        self.callParticipants = callParticipants_
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.callParticipants = try values.decode([ContactBytesAndNameJSON].self, forKey: .callParticipants)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callParticipants, forKey: .callParticipants)
    }

}

struct RelayMessageJSON: WebRTCDataChannelInnerMessageJSON {

    var messageType: WebRTCDataChannelMessageJSON.MessageType { .relayMessage }

    var to: Data
    var relayedMessageType: Int
    var serializedMessagePayload: String

    enum CodingKeys: String, CodingKey {
        case to = "to"
        case relayedMessageType = "mt"
        case serializedMessagePayload = "smp"
    }

    init(to: Data, relayedMessageType: Int, serializedMessagePayload: String) {
        self.to = to
        self.relayedMessageType = relayedMessageType
        self.serializedMessagePayload = serializedMessagePayload
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.to = try values.decode(Data.self, forKey: .to)
        self.relayedMessageType = try values.decode(Int.self, forKey: .relayedMessageType)
        self.serializedMessagePayload = try values.decode(String.self, forKey: .serializedMessagePayload)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(to, forKey: .to)
        try container.encode(relayedMessageType, forKey: .relayedMessageType)
        try container.encode(serializedMessagePayload, forKey: .serializedMessagePayload)
    }

}

struct RelayedMessageJSON: WebRTCDataChannelInnerMessageJSON {

    var messageType: WebRTCDataChannelMessageJSON.MessageType { .relayedMessage }

    var from: Data
    var relayedMessageType: Int
    var serializedMessagePayload: String

    enum CodingKeys: String, CodingKey {
        case from = "from"
        case relayedMessageType = "mt"
        case serializedMessagePayload = "smp"
    }

    init(from: Data, relayedMessageType: Int, serializedMessagePayload: String) {
        self.from = from
        self.relayedMessageType = relayedMessageType
        self.serializedMessagePayload = serializedMessagePayload
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.from = try values.decode(Data.self, forKey: .from)
        self.relayedMessageType = try values.decode(Int.self, forKey: .relayedMessageType)
        self.serializedMessagePayload = try values.decode(String.self, forKey: .serializedMessagePayload)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(from, forKey: .from)
        try container.encode(relayedMessageType, forKey: .relayedMessageType)
        try container.encode(serializedMessagePayload, forKey: .serializedMessagePayload)
    }

}

struct HangedUpDataChannelMessageJSON: WebRTCDataChannelInnerMessageJSON {

    var messageType: WebRTCDataChannelMessageJSON.MessageType { .hangedUpMessage }

}
