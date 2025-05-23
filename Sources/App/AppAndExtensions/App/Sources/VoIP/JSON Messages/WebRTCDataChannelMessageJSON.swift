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
        case videoSupported = 5
        case videoCameraEnabled = 6
        case videoScreencastEnabled = 7

        var description: String {
            switch self {
            case .muted: return "muted"
            case .updateParticipant: return "updateParticipant"
            case .relayMessage: return "relayMessage"
            case .relayedMessage: return "relayedMessage"
            case .hangedUpMessage: return "hangedUpMessage"
            case .videoSupported: return "videoSupported"
            case .videoCameraEnabled: return "videoCameraEnabled"
            case .videoScreencastEnabled: return "videoScreencastEnabled"
            }
        }
    }

    let messageType: MessageType
    let serializedMessage: String

    enum CodingKeys: String, CodingKey {
        case messageType = "t"
        case serializedMessage = "m"
    }

    func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    static func jsonDecode(data: Data) throws -> Self {
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

    func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    static func jsonDecode(serializedMessage: String) throws -> Self {
        guard let data = serializedMessage.data(using: .utf8) else {
            throw Self.makeError(message: "Could not turn serialized message into data")
        }
        let decoder = JSONDecoder()
        return try decoder.decode(Self.self, from: data)
    }

    func embedInWebRTCDataChannelMessageJSON() throws -> WebRTCDataChannelMessageJSON {
        let serializedMessageAsData = try self.jsonEncode()
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


/// Sent to our contact  as soon as the data channel is available, to indicate that we support video calls.
struct VideoSupportedJSON: WebRTCDataChannelInnerMessageJSON {
    
    var messageType: WebRTCDataChannelMessageJSON.MessageType { .videoSupported }
    
    enum CodingKeys: String, CodingKey {
        case isVideoSupported = "videoSupported"
    }
    
    let isVideoSupported: Bool
    
}


struct VideoCameraEnabledJSON: WebRTCDataChannelInnerMessageJSON {
    
    var messageType: WebRTCDataChannelMessageJSON.MessageType { .videoCameraEnabled }
    
    enum CodingKeys: String, CodingKey {
        case isVideoCameraEnabled = "videoSharing"
    }

    let isVideoCameraEnabled: Bool
    
}


struct VideoScreencastEnabledJSON: WebRTCDataChannelInnerMessageJSON {
    
    var messageType: WebRTCDataChannelMessageJSON.MessageType { .videoScreencastEnabled }
    
    enum CodingKeys: String, CodingKey {
        case isVideoScreencastEnabled = "screenSharing"
    }

    let isVideoScreencastEnabled: Bool
    
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

    init(byteContactIdentity: Data, displayName: String, gatheringPolicy: OlvidCallGatheringPolicy) {
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

    var gatheringPolicy: OlvidCallGatheringPolicy? {
        guard let rawGatheringPolicy = rawGatheringPolicy else { return nil }
        return OlvidCallGatheringPolicy(rawValue: rawGatheringPolicy)
    }

}

struct UpdateParticipantsMessageJSON: WebRTCDataChannelInnerMessageJSON {

    var messageType: WebRTCDataChannelMessageJSON.MessageType { .updateParticipant }

    let callParticipants: [ContactBytesAndNameJSON]

    enum CodingKeys: String, CodingKey {
        case callParticipants = "cp"
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
