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
import WebRTC



// MARK: - CallParticipantDelegate

protocol CallParticipantDelegate: AnyObject {
    
    var isOutgoingCall: Bool { get }

    func participantWasUpdated(callParticipant: CallParticipantImpl, updateKind: CallParticipantUpdateKind) async

    func connectionIsChecking(for callParticipant: CallParticipant)
    func connectionIsConnected(for callParticipant: CallParticipant, oldParticipantState: PeerState) async
    func connectionWasClosed(for callParticipant: CallParticipantImpl) async

    func dataChannelIsOpened(for callParticipant: CallParticipant) async

    func updateParticipants(with newCallParticipants: [ContactBytesAndNameJSON]) async throws
    func relay(from: ObvCryptoId, to: ObvCryptoId, messageType: WebRTCMessageJSON.MessageType, messagePayload: String) async
    func receivedRelayedMessage(from: ObvCryptoId, messageType: WebRTCMessageJSON.MessageType, messagePayload: String) async

    func sendStartCallMessage(to callParticipant: CallParticipant, sessionDescription: RTCSessionDescription, turnCredentials: TurnCredentials) async throws
    func sendAnswerCallMessage(to callParticipant: CallParticipant, sessionDescription: RTCSessionDescription) async throws
    func sendNewParticipantOfferMessage(to callParticipant: CallParticipant, sessionDescription: RTCSessionDescription) async throws
    func sendNewParticipantAnswerMessage(to callParticipant: CallParticipant, sessionDescription: RTCSessionDescription) async throws
    func sendReconnectCallMessage(to callParticipant: CallParticipant, sessionDescription: RTCSessionDescription, reconnectCounter: Int, peerReconnectCounterToOverride: Int) async throws
    func sendNewIceCandidateMessage(to callParticipant: CallParticipant, iceCandidate: RTCIceCandidate) async throws
    func sendRemoveIceCandidatesMessages(to callParticipant: CallParticipant, candidates: [RTCIceCandidate]) async throws

    func shouldISendTheOfferToCallParticipant(cryptoId: ObvCryptoId) -> Bool
    
}
