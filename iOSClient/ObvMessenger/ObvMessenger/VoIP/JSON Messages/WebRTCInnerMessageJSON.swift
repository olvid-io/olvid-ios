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
import ObvEngine
import ObvTypes

protocol WebRTCInnerMessageJSON: Codable {

    var messageType: WebRTCMessageJSON.MessageType { get }

}

extension WebRTCInnerMessageJSON {

    static var errorDomain: String { String(describing: Self.self) }
    static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: Self.errorDomain, code: 0, userInfo: userInfo)
    }

    func encode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    static func decode(serializedMessagePayload: String) throws -> Self {
        guard let data = serializedMessagePayload.data(using: .utf8) else {
            throw Self.makeError(message: "Could not turn serialized message payload into data")
        }
        let decoder = JSONDecoder()
        return try decoder.decode(Self.self, from: data)
    }

    func embedInWebRTCMessageJSON(callIdentifier: UUID) throws -> WebRTCMessageJSON {
        let serializedMessagePayloadAsData = try self.encode()
        guard let serializedMessagePayload = String(data: serializedMessagePayloadAsData, encoding: .utf8) else {
            throw Self.makeError(message: "Could not serialize message")
        }
        return WebRTCMessageJSON(callIdentifier: callIdentifier,
                                 messageType: messageType,
                                 serializedMessagePayload: serializedMessagePayload)
    }
}

struct IncomingCallMessageJSON: WebRTCInnerMessageJSON {

    var messageType: WebRTCMessageJSON.MessageType { .startCall }

    let sessionDescriptionType: String
    let sessionDescription: String
    let turnUserName: String
    let turnPassword: String
    let turnServers: [String]? /// REMARK Can be optional to be compatible with previous version where the server urls was hardcoded
    let participantCount: Int
    let groupId: (groupUid: UID, groupOwner: ObvCryptoId)?
    private let compressedSessionDescription: Data
    private let rawGatheringPolicy: Int? /// REMARK Can be optional to be compatible with previous version where gathering policy was hardcoded

    enum CodingKeys: String, CodingKey {
        case sessionDescriptionType = "sdt"
        case compressedSessionDescription = "sd"
        case turnUserName = "tu"
        case turnPassword = "tp"
        case turnServers = "ts"
        case participantCount = "c"
        case groupUid = "gi"
        case groupOwner = "go"
        case rawGatheringPolicy = "gp"
    }

    func encode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionDescriptionType, forKey: .sessionDescriptionType)
        try container.encode(compressedSessionDescription, forKey: .compressedSessionDescription)
        try container.encode(turnUserName, forKey: .turnUserName)
        try container.encode(turnPassword, forKey: .turnPassword)
        try container.encode(turnServers, forKey: .turnServers)
        try container.encode(participantCount, forKey: .participantCount)
        try container.encode(rawGatheringPolicy, forKey: .rawGatheringPolicy)
        if let groupId = groupId {
            try container.encode(groupId.groupUid.raw, forKey: .groupUid)
            try container.encode(groupId.groupOwner.getIdentity(), forKey: .groupOwner)
        }
    }

    init(sessionDescriptionType: String, sessionDescription: String, turnUserName: String, turnPassword: String, turnServers: [String], participantCount: Int, groupId: (groupUid: UID, groupOwner: ObvCryptoId)?, gatheringPolicy: GatheringPolicy) throws {
        self.sessionDescriptionType = sessionDescriptionType
        self.sessionDescription = sessionDescription
        self.turnUserName = turnUserName
        self.turnPassword = turnPassword
        self.turnServers = turnServers
        guard let data = sessionDescription.data(using: .utf8) else { throw Self.makeError(message: "Could not compress session description") }
        self.compressedSessionDescription = try ObvCompressor.compress(data)
        self.participantCount = participantCount
        self.groupId = groupId
        self.rawGatheringPolicy = gatheringPolicy.rawValue
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.sessionDescriptionType = try values.decode(String.self, forKey: .sessionDescriptionType)
        self.compressedSessionDescription = try values.decode(Data.self, forKey: .compressedSessionDescription)
        self.turnUserName = try values.decode(String.self, forKey: .turnUserName)
        self.turnPassword = try values.decode(String.self, forKey: .turnPassword)
        self.turnServers = try values.decodeIfPresent([String].self, forKey: .turnServers)
        self.participantCount = try values.decodeIfPresent(Int.self, forKey: .participantCount) ?? 1
        let data = try ObvCompressor.decompress(self.compressedSessionDescription)
        guard let sessionDescription = String(data: data, encoding: .utf8) else { throw Self.makeError(message: "Could not decompress session description") }
        self.sessionDescription = sessionDescription
        self.rawGatheringPolicy = try values.decodeIfPresent(Int.self, forKey: .rawGatheringPolicy)

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
            throw Self.makeError(message: "Could determine if the message is part of a group or not. Discarding the message.")
        }
    }

    var gatheringPolicy: GatheringPolicy? {
        guard let rawGatheringPolicy = rawGatheringPolicy else { return nil }
        return GatheringPolicy(rawValue: rawGatheringPolicy)
    }

}

struct AnswerIncomingCallJSON: WebRTCInnerMessageJSON {

    var messageType: WebRTCMessageJSON.MessageType { .answerCall }

    let sessionDescriptionType: String
    let sessionDescription: String
    private let compressedSessionDescription: Data

    enum CodingKeys: String, CodingKey {
        case sessionDescriptionType = "sdt"
        case compressedSessionDescription = "sd"
    }

    init(sessionDescriptionType: String, sessionDescription: String) throws {
        self.sessionDescriptionType = sessionDescriptionType
        self.sessionDescription = sessionDescription
        guard let data = sessionDescription.data(using: .utf8) else { throw Self.makeError(message: "Could not compress session description") }
        self.compressedSessionDescription = try ObvCompressor.compress(data)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.sessionDescriptionType = try values.decode(String.self, forKey: .sessionDescriptionType)
        self.compressedSessionDescription = try values.decode(Data.self, forKey: .compressedSessionDescription)
        let data = try ObvCompressor.decompress(self.compressedSessionDescription)
        guard let sessionDescription = String(data: data, encoding: .utf8) else { throw Self.makeError(message: "Could not decompress session description") }
        self.sessionDescription = sessionDescription
    }

}

struct ReconnectCallMessageJSON: WebRTCInnerMessageJSON {

    var messageType: WebRTCMessageJSON.MessageType { .reconnect }

    let sessionDescriptionType: String
    let sessionDescription: String
    private let compressedSessionDescription: Data
    let reconnectCounter: Int?
    let peerReconnectCounterToOverride: Int? /// when sending a restart OFFER, this is the counter for the latest ANSWER received

    enum CodingKeys: String, CodingKey {
        case sessionDescriptionType = "sdt"
        case compressedSessionDescription = "sd"
        case reconnectCounter = "rc"
        case peerReconnectCounterToOverride = "prco"
    }

    init(sessionDescriptionType: String, sessionDescription: String, reconnectCounter: Int, peerReconnectCounterToOverride: Int) throws {
        self.sessionDescriptionType = sessionDescriptionType
        self.sessionDescription = sessionDescription
        guard let data = sessionDescription.data(using: .utf8) else { throw Self.makeError(message: "Could not compress session description") }
        self.compressedSessionDescription = try ObvCompressor.compress(data)
        self.reconnectCounter = reconnectCounter
        self.peerReconnectCounterToOverride = peerReconnectCounterToOverride
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.sessionDescriptionType = try values.decode(String.self, forKey: .sessionDescriptionType)
        self.compressedSessionDescription = try values.decode(Data.self, forKey: .compressedSessionDescription)
        let data = try ObvCompressor.decompress(self.compressedSessionDescription)
        guard let sessionDescription = String(data: data, encoding: .utf8) else { throw Self.makeError(message: "Could not decompress session description") }
        self.sessionDescription = sessionDescription
        self.reconnectCounter = try values.decodeIfPresent(Int.self, forKey: .reconnectCounter)
        self.peerReconnectCounterToOverride = try values.decodeIfPresent(Int.self, forKey: .peerReconnectCounterToOverride)
    }

}

struct RejectCallMessageJSON: WebRTCInnerMessageJSON {

    var messageType: WebRTCMessageJSON.MessageType { .rejectCall }

}

struct HangedUpMessageJSON: WebRTCInnerMessageJSON {

    var messageType: WebRTCMessageJSON.MessageType { .hangedUp }

}

struct RingingMessageJSON: WebRTCInnerMessageJSON {

    var messageType: WebRTCMessageJSON.MessageType { .ringing }

}

struct BusyMessageJSON: WebRTCInnerMessageJSON {

    var messageType: WebRTCMessageJSON.MessageType { .busy }

}

struct NewParticipantOfferMessageJSON: WebRTCInnerMessageJSON {

    var messageType: WebRTCMessageJSON.MessageType { .newParticipantOffer }

    let sessionDescriptionType: String
    let sessionDescription: String
    private let compressedSessionDescription: Data
    private let rawGatheringPolicy: Int? /// REMARK Can be optional to be compatible with previous version where gathering policy was hardcoded

    enum CodingKeys: String, CodingKey {
        case sessionDescriptionType = "sdt"
        case compressedSessionDescription = "sd"
        case rawGatheringPolicy = "gp"
    }

    init(sessionDescriptionType: String, sessionDescription: String, gatheringPolicy: GatheringPolicy) throws {
        self.sessionDescriptionType = sessionDescriptionType
        self.sessionDescription = sessionDescription
        guard let data = sessionDescription.data(using: .utf8) else { throw Self.makeError(message: "Could not compress session description") }
        self.compressedSessionDescription = try ObvCompressor.compress(data)
        self.rawGatheringPolicy = gatheringPolicy.rawValue
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.sessionDescriptionType = try values.decode(String.self, forKey: .sessionDescriptionType)
        self.compressedSessionDescription = try values.decode(Data.self, forKey: .compressedSessionDescription)
        let data = try ObvCompressor.decompress(self.compressedSessionDescription)
        guard let sessionDescription = String(data: data, encoding: .utf8) else { throw Self.makeError(message: "Could not decompress session description") }
        self.sessionDescription = sessionDescription
        self.rawGatheringPolicy = try values.decodeIfPresent(Int.self, forKey: .rawGatheringPolicy)
    }

    var gatheringPolicy: GatheringPolicy? {
        guard let rawGatheringPolicy = rawGatheringPolicy else { return nil }
        return GatheringPolicy(rawValue: rawGatheringPolicy)
    }
}

struct NewParticipantAnswerMessageJSON: WebRTCInnerMessageJSON {

    var messageType: WebRTCMessageJSON.MessageType { .newParticipantAnswer }

    let sessionDescriptionType: String
    let sessionDescription: String
    private let compressedSessionDescription: Data

    enum CodingKeys: String, CodingKey {
        case sessionDescriptionType = "sdt"
        case compressedSessionDescription = "sd"
    }

    init(sessionDescriptionType: String, sessionDescription: String) throws {
        self.sessionDescriptionType = sessionDescriptionType
        self.sessionDescription = sessionDescription
        guard let data = sessionDescription.data(using: .utf8) else { throw Self.makeError(message: "Could not compress session description") }
        self.compressedSessionDescription = try ObvCompressor.compress(data)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.sessionDescriptionType = try values.decode(String.self, forKey: .sessionDescriptionType)
        self.compressedSessionDescription = try values.decode(Data.self, forKey: .compressedSessionDescription)
        let data = try ObvCompressor.decompress(self.compressedSessionDescription)
        guard let sessionDescription = String(data: data, encoding: .utf8) else { throw Self.makeError(message: "Could not decompress session description") }
        self.sessionDescription = sessionDescription
    }

}

struct KickMessageJSON: WebRTCInnerMessageJSON {

    var messageType: WebRTCMessageJSON.MessageType { .kick }

}

struct IceCandidateJSON: Codable, Equatable {

    var sdp: String
    var sdpMLineIndex: Int32
    var sdpMid: String?

    enum CodingKeys: String, CodingKey {
        case sdp = "sdp"
        case sdpMLineIndex = "li"
        case sdpMid = "id"
    }
}

extension IceCandidateJSON: WebRTCInnerMessageJSON {
    var messageType: WebRTCMessageJSON.MessageType { .newIceCandidate }
}


struct RemoveIceCandidatesMessageJSON: WebRTCInnerMessageJSON {

    var messageType: WebRTCMessageJSON.MessageType { .removeIceCandidates }

    var candidates: [IceCandidateJSON]

    enum CodingKeys: String, CodingKey {
        case candidates = "cs"
    }

}
