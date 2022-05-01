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
import WebRTC


protocol WebrtcPeerConnectionHolderDelegate: AnyObject {
    
    func peerConnectionStateDidChange(newState: RTCIceConnectionState) async
    func dataChannel(of peerConnectionHolder: WebrtcPeerConnectionHolder, didReceiveMessage message: WebRTCDataChannelMessageJSON) async
    func dataChannel(of peerConnectionHolder: WebrtcPeerConnectionHolder, didChangeState state: RTCDataChannelState) async
    func shouldISendTheOfferToCallParticipant() async -> Bool

    func sendNewIceCandidateMessage(candidate: RTCIceCandidate) async throws
    func sendRemoveIceCandidatesMessages(candidates: [RTCIceCandidate]) async throws

    func sendLocalDescription(sessionDescription: RTCSessionDescription, reconnectCounter: Int, peerReconnectCounterToOverride: Int) async

}
