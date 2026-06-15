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
import WebRTC


/// Signaling messages exchanged between source and destination owned devices to establish a WebRTC connection for history transfer.
///
/// These messages are serialized to JSON and delivered out-of-band (via Olvid's regular messaging channel).
/// Both devices exchange SDPs (offer/answer) and ICE candidates to negotiate the peer connection.
public enum WebrtcHistoryTransferMessage: Sendable {
    
    case iceCandidates(transferId: String, iceCandidates: [ICECandidate])
    case sdp(transferId: String, sdp: Sdp)
    
    public struct ICECandidate: Sendable {
        public let sdp: String
        public let sdpMLineIndex: Int
        public let sdpMid: String?
        public init(sdp: String, sdpMLineIndex: Int, sdpMid: String?) {
            self.sdp = sdp
            self.sdpMLineIndex = sdpMLineIndex
            self.sdpMid = sdpMid
        }
    }
    
    public struct Sdp: Sendable {
        public let type: SdpType
        public let sdp: String
        public init(type: SdpType, sdp: String) {
            self.type = type
            self.sdp = sdp
        }
        public enum SdpType: String, Sendable {
            case offer = "offer"
            case answer = "answer"
        }
    }
    
    enum ObvError: Error {
        case unexpectedSdpType
    }
    
}


extension WebrtcHistoryTransferMessage.Sdp {
    
    init(sdp: RTCSessionDescription) throws {
        switch sdp.type {
        case .answer:
            self.init(type: .answer, sdp: sdp.sdp)
        case .offer:
            self.init(type: .offer, sdp: sdp.sdp)
        default:
            assertionFailure()
            throw WebrtcHistoryTransferMessage.ObvError.unexpectedSdpType
        }
    }
    
}
