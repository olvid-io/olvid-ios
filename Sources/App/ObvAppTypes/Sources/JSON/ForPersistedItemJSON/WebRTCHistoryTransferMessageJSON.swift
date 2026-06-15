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


public struct WebRTCHistoryTransferMessageJSON: Codable {
    
    enum CodingKeys: String, CodingKey {
        case transferId = "id"
        case iceCandidates = "ice"
        case sdp = "sdp"
    }

    public let transferId: String
    public let sdp: Sdp?
    public let iceCandidates: [IceCandidate]?
    
    public init(transferId: String, sdp: Sdp) {
        self.transferId = transferId
        self.sdp = sdp
        self.iceCandidates = nil
    }
    
    public init(transferId: String, iceCandidates: [IceCandidate]) {
        self.transferId = transferId
        self.sdp = nil
        self.iceCandidates = iceCandidates
    }
    
    public struct Sdp: Codable {
        public let type: String // "offer" or "answer"
        public let sdp: String
        public init(type: String, sdp: String) {
            self.type = type
            self.sdp = sdp
        }
        enum CodingKeys: String, CodingKey {
            case type = "t"
            case sdp = "sdp"
        }
    }
    
    public struct IceCandidate: Codable {
        public let sdp: String
        public let sdpMLineIndex: Int
        public let sdpMid: String?
        public init(sdp: String, sdpMLineIndex: Int, sdpMid: String?) {
            self.sdp = sdp
            self.sdpMLineIndex = sdpMLineIndex
            self.sdpMid = sdpMid
        }
        enum CodingKeys: String, CodingKey {
            case sdp = "sdp"
            case sdpMLineIndex = "mli"
            case sdpMid = "mid"
        }
    }
    
}
