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
import ObvCrypto


protocol WebRTCInnerMessageJSON: Codable {

    var messageType: WebRTCMessageJSON.MessageType { get }

}

extension WebRTCInnerMessageJSON {

    static var errorDomain: String { String(describing: Self.self) }
    static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: Self.errorDomain, code: 0, userInfo: userInfo)
    }

    func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    static func jsonDecode(serializedMessagePayload: String) throws -> Self {
        guard let data = serializedMessagePayload.data(using: .utf8) else {
            throw Self.makeError(message: "Could not turn serialized message payload into data")
        }
        let decoder = JSONDecoder()
        return try decoder.decode(Self.self, from: data)
    }

    func embedInWebRTCMessageJSON(callIdentifier: UUID) throws -> WebRTCMessageJSON {
        let serializedMessagePayloadAsData = try self.jsonEncode()
        guard let serializedMessagePayload = String(data: serializedMessagePayloadAsData, encoding: .utf8) else {
            throw Self.makeError(message: "Could not serialize message")
        }
        return WebRTCMessageJSON(callIdentifier: callIdentifier,
                                 messageType: messageType,
                                 serializedMessagePayload: serializedMessagePayload)
    }
}

struct StartCallMessageJSON: WebRTCInnerMessageJSON {

    var messageType: WebRTCMessageJSON.MessageType { .startCall }

    let sessionDescriptionType: String
    let sessionDescription: String
    let turnUserName: String
    let turnPassword: String
    let turnServers: [String]? /// REMARK Can be optional to be compatible with previous version where the server urls was hardcoded. 2022-03-11: we do not use this info anymore if we are a call participant, we discard it and use hardcoded servers (prevents an attack from caller).
    let participantCount: Int
    let groupIdentifier: GroupIdentifier?
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
        case groupV2Identifier = "gid2"
    }

    func jsonEncode() throws -> Data {
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
        switch groupIdentifier {
        case .groupV1(groupV1Identifier: let groupV1Identifier):
            try container.encode(groupV1Identifier.groupUid.raw, forKey: .groupUid)
            try container.encode(groupV1Identifier.groupOwner.getIdentity(), forKey: .groupOwner)
        case .groupV2(groupV2Identifier: let groupV2Identifier):
            try container.encode(groupV2Identifier, forKey: .groupV2Identifier)
        case .none:
            break
        }
    }

    init(sessionDescriptionType: String, sessionDescription: String, turnUserName: String, turnPassword: String, turnServers: [String], participantCount: Int, groupIdentifier: GroupIdentifier?, gatheringPolicy: GatheringPolicy) throws {
        self.sessionDescriptionType = sessionDescriptionType
        self.sessionDescription = sessionDescription
        self.turnUserName = turnUserName
        self.turnPassword = turnPassword
        self.turnServers = turnServers
        guard let data = sessionDescription.data(using: .utf8) else { throw Self.makeError(message: "Could not compress session description") }
        self.compressedSessionDescription = try ObvCompressor.compress(data)
        self.participantCount = participantCount
        self.groupIdentifier = groupIdentifier
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

        if let groupUidRaw = try values.decodeIfPresent(Data.self, forKey: .groupUid),
           let groupOwnerIdentity = try values.decodeIfPresent(Data.self, forKey: .groupOwner),
           let groupUid = UID(uid: groupUidRaw),
           let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) {
            self.groupIdentifier = .groupV1(groupV1Identifier: (groupUid, groupOwner))
        } else if let groupV2Identifier = try values.decodeIfPresent(Data.self, forKey: .groupV2Identifier) {
            self.groupIdentifier = .groupV2(groupV2Identifier: groupV2Identifier)
        } else {
            self.groupIdentifier = nil
        }
    }

    var gatheringPolicy: GatheringPolicy? {
        guard let rawGatheringPolicy = rawGatheringPolicy else { return nil }
        return GatheringPolicy(rawValue: rawGatheringPolicy)
    }

}


struct AnswerCallJSON: WebRTCInnerMessageJSON {

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
