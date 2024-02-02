/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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

public struct WebRTCMessageJSON: Codable {

    public enum MessageType: Int, Codable, CustomStringConvertible {
        case startCall = 0
        case answerCall = 1
        case rejectCall = 2
        case hangedUp = 3
        case ringing = 4
        case busy = 5
        case reconnect = 6
        case newParticipantOffer = 7
        case newParticipantAnswer = 8
        case kick = 9
        case newIceCandidate = 10
        case removeIceCandidates = 11
        case answeredOrRejectedOnOtherDevice = 12

        public var description: String {
            switch self {
            case .startCall: return "startCall"
            case .answerCall: return "answerCall"
            case .rejectCall: return "rejectCall"
            case .hangedUp: return "hangedUp"
            case .ringing: return "ringing"
            case .busy: return "busy"
            case .reconnect: return "reconnect"
            case .newParticipantOffer: return "newParticipantOffer"
            case .newParticipantAnswer: return "newParticipantAnswer"
            case .kick: return "kick"
            case .newIceCandidate: return "newIceCandidate"
            case .removeIceCandidates: return "removeIceCandidates"
            case .answeredOrRejectedOnOtherDevice: return "answeredOrRejectedOnOtherDevice"
            }
        }

        public var isAllowedToBeRelayed: Bool {
            switch self {
            case .startCall, .answerCall, .rejectCall, .ringing, .busy, .kick, .answeredOrRejectedOnOtherDevice:
                return false
            case .hangedUp, .reconnect, .newParticipantOffer, .newParticipantAnswer, .newIceCandidate, .removeIceCandidates:
                return true
            }
        }
    }

    public let callIdentifier: UUID
    public let messageType: MessageType
    public let serializedMessagePayload: String
    
    public init(callIdentifier: UUID, messageType: MessageType, serializedMessagePayload: String) {
        self.callIdentifier = callIdentifier
        self.messageType = messageType
        self.serializedMessagePayload = serializedMessagePayload
    }

    enum CodingKeys: String, CodingKey {
        case callIdentifier = "ci"
        case messageType = "mt"
        case serializedMessagePayload = "smp"
    }

    func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

}
