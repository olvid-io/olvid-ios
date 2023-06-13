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
import os.log
import ObvTypes
import OlvidUtils
import WebRTC
import ObvUICoreData


// MARK: - CallParticipantImpl

actor CallParticipantImpl: CallParticipant, ObvErrorMaker {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: CallParticipantImpl.self))

    let uuid: UUID = UUID()
    let role: Role
    let ownRole: Role // Role of the owned identity
    let userId: OlvidUserId
    private var state: PeerState

    static let errorDomain = "CallParticipantImpl"

    private var contactIsMuted = false
        
    /// The only case where the `peerConnectionHolder` can be nil is when we receive pushkit notification for an incoming call
    /// And cannot immediately determine the caller.
    private var peerConnectionHolder: WebrtcPeerConnectionHolder?

    private var connectingTimeoutTimer: Timer?
    private static let connectingTimeoutInterval: TimeInterval = 15.0 // 15 seconds
    
    private func setPeerConnectionHolder(to peerConnectionHolder: WebrtcPeerConnectionHolder) async {
        assert(self.peerConnectionHolder == nil)
        self.peerConnectionHolder = peerConnectionHolder
    }
    
    
    var gatheringPolicy: GatheringPolicy? {
        get async {
            await peerConnectionHolder?.gatheringPolicy
        }
    }

    func getPeerState() async -> PeerState {
        return state
    }
    
    private weak var delegate: CallParticipantDelegate?
    
    
    func setDelegate(to delegate: CallParticipantDelegate) async {
        self.delegate = delegate
    }
    
    func getContactIsMuted() async -> Bool {
        return contactIsMuted
    }
    
    nonisolated var contactInfo: ContactInfo? {
        switch userId {
        case .known(let contactObjectID, _, _, _):
            return CallHelper.getContactInfo(contactObjectID)
        case .unknown:
            return nil
        }
    }

    
    nonisolated var ownedIdentity: ObvCryptoId {
        userId.ownCryptoId
    }

    
    nonisolated var remoteCryptoId: ObvCryptoId {
        userId.remoteCryptoId
    }

    
    nonisolated var fullDisplayName: String {
        switch userId {
        case .known(_, _, _, displayName: let displayName):
            return contactInfo?.fullDisplayName ?? displayName
        case .unknown(ownCryptoId: _, remoteCryptoId: _, displayName: let displayName):
            return displayName
        }
    }

    
    nonisolated var displayName: String {
        switch userId {
        case .known(contactObjectID: _, ownCryptoId: _, remoteCryptoId: _, displayName: let displayName):
            return contactInfo?.customDisplayName ?? contactInfo?.fullDisplayName ?? displayName
        case .unknown(ownCryptoId: _, remoteCryptoId: _, displayName: let displayName):
            return displayName
        }
    }

    
    nonisolated var photoURL: URL? { contactInfo?.photoURL }
    
    nonisolated var identityColors: (background: UIColor, text: UIColor)? { contactInfo?.identityColors }

    
    nonisolated var info: ParticipantInfo? {
        if let contactObjectID = userId.contactObjectID {
            return ParticipantInfo(contactObjectID: contactObjectID, isCaller: role == .caller)
        } else {
            return nil
        }
    }


    /// Create the `caller` participant for an incoming call when the contact ID of this caller is already known.
    static func createCaller(startCallMessage: StartCallMessageJSON, contactId: OlvidUserId) async -> Self {
        let callParticipant = self.init(role: .caller, ownRole: .recipient, userId: contactId)
        await callParticipant.setTurnCredentials(to: startCallMessage.turnCredentials)
        await callParticipant.setPeerConnectionHolder(to: WebrtcPeerConnectionHolder(startCallMessage: startCallMessage, delegate: callParticipant))
        return callParticipant
    }

    
    /// Create a `recipient` participant for an outgoing call
    static func createRecipientForOutgoingCall(contactId: OlvidUserId, gatheringPolicy: GatheringPolicy) async -> Self {
        let callParticipant = self.init(role: .recipient, ownRole: .caller, userId: contactId)
        await callParticipant.setPeerConnectionHolder(to: WebrtcPeerConnectionHolder(gatheringPolicy: gatheringPolicy, delegate: callParticipant))
        return callParticipant
    }

    
    /// Create a `recipient` participant for an incoming call
    static func createRecipientForIncomingCall(contactId: OlvidUserId, gatheringPolicy: GatheringPolicy) async -> Self {
        let callParticipant = self.init(role: .recipient, ownRole: .recipient, userId: contactId)
        await callParticipant.setPeerConnectionHolder(to: WebrtcPeerConnectionHolder(gatheringPolicy: gatheringPolicy, delegate: callParticipant))
        return callParticipant
    }

    
    /// Update a recipient in a multi-user incoming call where we also are a recipient (not the caller), and not in charge of the offer.
    func updateRecipient(newParticipantOfferMessage: NewParticipantOfferMessageJSON, turnCredentials: TurnCredentials) async throws {
        assert(role == .recipient)
        assert(self.peerConnectionHolder != nil)
        self.turnCredentials = turnCredentials
        try await self.peerConnectionHolder?.setRemoteDescriptionAndTurnCredentialsThenCreateTheUnderlyingPeerConnectionIfRequired(newParticipantOfferMessage: newParticipantOfferMessage, turnCredentials: turnCredentials)
    }

    
    private init(role: Role, ownRole: Role, userId: OlvidUserId) {
        self.role = role
        self.ownRole = ownRole
        self.userId = userId
        self.state = .initial
    }

    
    func setPeerState(to newState: PeerState) async throws {
        guard newState != self.state else { return }
        os_log("☎️ WebRTCCall participant will change state: %{public}@ --> %{public}@", log: log, type: .info, self.state.debugDescription, newState.debugDescription)
        self.state = newState
        
        invalidateConnectingTimeout()

        switch self.state {
        case .startCallMessageSent:
            break
        case .ringing:
            break
        case .connectingToPeer, .reconnecting:
            scheduleConnectingTimeout()
        case .connected:
            break
        case .busy, .callRejected, .hangedUp, .kicked, .failed, .initial:
            break
        }
        if self.state.isFinalState {
            try await closeConnection()
        }

        await delegate?.participantWasUpdated(callParticipant: self, updateKind: .state(newState: state))
    }

    func localUserAcceptedIncomingCallFromThisCallParticipant() async throws {
        assert(self.role == .caller)
        assert(self.ownRole == .recipient)
        guard let peerConnectionHolder = self.peerConnectionHolder else {
            assertionFailure()
            throw Self.makeError(message: "No peer connection holder")
        }
        try await peerConnectionHolder.createPeerConnectionIfRequiredAfterAcceptingAnIncomingCall()
    }

    
    /// This method is two situations:
    /// - During an outgoing call, when setting the turn credential of a call participant.
    /// - During a multi-users incoming call, when we are in charge of sending the offer to another recipient (who isn't the caller).
    func setTurnCredentialsAndCreateUnderlyingPeerConnection(turnCredentials: TurnCredentials) async throws {
        assert(role == .recipient)
        self.turnCredentials = turnCredentials
        assert(self.peerConnectionHolder != nil)
        try await self.peerConnectionHolder?.setTurnCredentialsAndCreateUnderlyingPeerConnectionIfRequired(turnCredentials)
    }
    

    func setRemoteDescription(sessionDescription: RTCSessionDescription) async throws {
        guard let peerConnectionHolder = self.peerConnectionHolder else {
            assertionFailure()
            throw Self.makeError(message: "Cannot set remote description, the peer connection holder is nil")
        }
        try await peerConnectionHolder.setRemoteDescription(sessionDescription)
    }
    
    
    func handleReceivedRestartSdp(sessionDescription: RTCSessionDescription, reconnectCounter: Int, peerReconnectCounterToOverride: Int) async throws {
        guard let peerConnectionHolder = self.peerConnectionHolder else {
            throw Self.makeError(message: "No peer connection holder")
        }
        try await peerConnectionHolder.handleReceivedRestartSdp(sessionDescription: sessionDescription,
                                                                reconnectCounter: reconnectCounter,
                                                                peerReconnectCounterToOverride: peerReconnectCounterToOverride)
    }
    
    
    func reconnectAfterConnectionLoss() async throws {
        guard [PeerState.connectingToPeer, .connected, .reconnecting].contains(self.state) else { return }
        try await setPeerState(to: .reconnecting)
        guard let peerConnectionHolder = self.peerConnectionHolder else {
            assertionFailure()
            throw Self.makeError(message: "No peer connection holder")
        }
        try await peerConnectionHolder.restartIce()
    }
    
    
    /// Called when a network connection status changed
    func restartIceIfAppropriate() async throws {
        guard let peerConnectionHolder = self.peerConnectionHolder else {
            throw Self.makeError(message: "No peer connection holder")
        }
        guard [.connected, .connectingToPeer, .reconnecting].contains(self.state) else { return }
        try await peerConnectionHolder.restartIce()
    }

    
    func closeConnection() async throws {
        guard let peerConnectionHolder = self.peerConnectionHolder else {
            os_log("☎️🛑 No need to close connection: peer connection holder is nil", log: log, type: .info)
            return
        }
        try await peerConnectionHolder.close()
    }
    

    var isMuted: Bool {
        get async {
            await peerConnectionHolder?.isAudioTrackMuted ?? false
        }
    }

    
    func mute() async {
        guard let peerConnectionHolder = peerConnectionHolder else { return }
        await peerConnectionHolder.muteAudioTracks()
        await sendMutedMessageJSON()
    }

    
    func unmute() async {
        guard let peerConnectionHolder = peerConnectionHolder else { return }
        await peerConnectionHolder.unmuteAudioTracks()
        await sendMutedMessageJSON()
    }

    
    private var turnCredentials: TurnCredentials?

    
    func setTurnCredentials(to turnCredentials: TurnCredentials) async {
        self.turnCredentials = turnCredentials
    }
    
    
    private func processMutedMessageJSON(message: MutedMessageJSON) async {
        guard contactIsMuted != message.muted else { return }
        contactIsMuted = message.muted
        await delegate?.participantWasUpdated(callParticipant: self, updateKind: .contactMuted)
    }

    
    private func processUpdateParticipantsMessageJSON(message: UpdateParticipantsMessageJSON) async throws {
       // Check that the participant list is indeed sent by the caller (and thus, not by a "simple" participant).
        guard role == .caller else {
            assertionFailure()
            return
        }
        try await delegate?.updateParticipants(with: message.callParticipants)
    }

    
    private func processRelayMessageJSON(message: RelayMessageJSON) async {
        guard role == .recipient else { return }

        do {
            let fromId = self.remoteCryptoId
            let toId = try ObvCryptoId(identity: message.to)
            guard let messageType = WebRTCMessageJSON.MessageType(rawValue: message.relayedMessageType) else { throw Self.makeError(message: "Could not parse WebRTCMessageJSON.MessageType") }
            let messagePayload = message.serializedMessagePayload
            await delegate?.relay(from: fromId, to: toId, messageType: messageType, messagePayload: messagePayload)
        } catch {
            os_log("☎️ Could not read received RelayMessageJSON: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }
    }

    
    private func processRelayedMessageJSON(message: RelayedMessageJSON) async throws {

        guard role == .caller else { return }

        do {
            let fromId = try ObvCryptoId(identity: message.from)
            guard let messageType = WebRTCMessageJSON.MessageType(rawValue: message.relayedMessageType) else {
                throw Self.makeError(message: "Could not compute message type")
            }
            let messagePayload = message.serializedMessagePayload
            await delegate?.receivedRelayedMessage(from: fromId, messageType: messageType, messagePayload: messagePayload)
        } catch {
            os_log("☎️ Could not read received RelayedMessageJSON: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }
    }

    
    private func processHangedUpMessage(message: HangedUpDataChannelMessageJSON) async throws {
        try await setPeerState(to: .hangedUp)
    }

    
    func sendDataChannelMessage(_ message: WebRTCDataChannelMessageJSON) async throws {
        guard let peerConnectionHolder = self.peerConnectionHolder else { assertionFailure(); return }
        try await peerConnectionHolder.sendDataChannelMessage(message)
    }

    
    func sendUpdateParticipantsMessageJSON(callParticipants: [CallParticipant]) async throws {
        let message = try await UpdateParticipantsMessageJSON(callParticipants: callParticipants).embedInWebRTCDataChannelMessageJSON()
        try await sendDataChannelMessage(message)
    }

    
    func processIceCandidatesJSON(message: IceCandidateJSON) async throws {
        guard let peerConnectionHolder = self.peerConnectionHolder else { assertionFailure(); return }
        try await peerConnectionHolder.addIceCandidate(iceCandidate: message.iceCandidate)
    }

    
    func processRemoveIceCandidatesMessageJSON(message: RemoveIceCandidatesMessageJSON) async {
        guard let peerConnectionHolder = self.peerConnectionHolder else { return }
        await peerConnectionHolder.removeIceCandidates(iceCandidates: message.iceCandidates)
    }

}


// MARK: - Timers

extension CallParticipantImpl {
    
    private func scheduleConnectingTimeout() {
        invalidateConnectingTimeout()
        let log = self.log
        os_log("☎️ Schedule connecting timeout timer", log: log, type: .info)
        let nextConnectingTimeoutInterval = CallParticipantImpl.connectingTimeoutInterval * Double.random(in: 1.0..<1.3) // Approx. between 15 and 20 seconds
        let timer = Timer.init(timeInterval: nextConnectingTimeoutInterval, repeats: false) { timer in
            guard timer.isValid else { return }
            Task { [weak self] in await self?.connectingTimeoutTimerFired() }
        }
        self.connectingTimeoutTimer = timer
        RunLoop.main.add(timer, forMode: .default)
    }
    
    
    private func invalidateConnectingTimeout() {
        if let timer = self.connectingTimeoutTimer {
            os_log("☎️ Invalidating connecting timeout timer", log: log, type: .info)
            timer.invalidate()
            self.connectingTimeoutTimer = nil
        }
    }
    
    
    private func connectingTimeoutTimerFired() async {
        guard [PeerState.connectingToPeer, .reconnecting].contains(self.state) else { return }
        os_log("☎️ Reconnection timer fired -> trying to reconnect after connection loss", log: log, type: .info)
        do {
            try await reconnectAfterConnectionLoss()
        } catch {
            os_log("☎️ Could not reconnect: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }
    
}


// MARK: - Implementing WebrtcPeerConnectionHolderDelegate

extension CallParticipantImpl: WebrtcPeerConnectionHolderDelegate {

    func shouldISendTheOfferToCallParticipant() async -> Bool {
        guard let delegate = delegate else { assertionFailure(); return false }
        return delegate.shouldISendTheOfferToCallParticipant(cryptoId: userId.remoteCryptoId)
    }

    
    func peerConnectionStateDidChange(newState: RTCIceConnectionState) async {
        switch newState {
        case .new: return
        case .checking:
            delegate?.connectionIsChecking(for: self)
        case .connected:
            let oldState = self.state
            try? await setPeerState(to: .connected)
            await delegate?.connectionIsConnected(for: self, oldParticipantState: oldState)
        case .failed, .disconnected:
            try? await reconnectAfterConnectionLoss()
        case .closed:
            await delegate?.connectionWasClosed(for: self)
        case .completed, .count:
            return
        @unknown default:
            assertionFailure()
        }
    }

    
    func dataChannel(of peerConnectionHolder: WebrtcPeerConnectionHolder, didReceiveMessage message: WebRTCDataChannelMessageJSON) async {
        do {
            switch message.messageType {
                
            case .muted:
                let mutedMessage = try MutedMessageJSON.jsonDecode(serializedMessage: message.serializedMessage)
                os_log("☎️ MutedMessageJSON received", log: log, type: .info)
                await processMutedMessageJSON(message: mutedMessage)
                
            case .updateParticipant:
                let updateParticipantsMessage = try UpdateParticipantsMessageJSON.jsonDecode(serializedMessage: message.serializedMessage)
                os_log("☎️ UpdateParticipantsMessageJSON received", log: log, type: .info)
                try await processUpdateParticipantsMessageJSON(message: updateParticipantsMessage)
                
            case .relayMessage:
                let relayMessage = try RelayMessageJSON.jsonDecode(serializedMessage: message.serializedMessage)
                os_log("☎️ RelayMessageJSON received", log: log, type: .info)
                await processRelayMessageJSON(message: relayMessage)
                
            case .relayedMessage:
                let relayedMessage = try RelayedMessageJSON.jsonDecode(serializedMessage: message.serializedMessage)
                os_log("☎️ RelayedMessageJSON received", log: log, type: .info)
                try await processRelayedMessageJSON(message: relayedMessage)
                
            case .hangedUpMessage:
                let hangedUpMessage = try HangedUpDataChannelMessageJSON.jsonDecode(serializedMessage: message.serializedMessage)
                os_log("☎️ HangedUpDataChannelMessageJSON received", log: log, type: .info)
                try await processHangedUpMessage(message: hangedUpMessage)
                
            }
        } catch {
            os_log("☎️ Failed to parse or process WebRTCDataChannelMessageJSON: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }
    

    func dataChannel(of peerConnectionHolder: WebrtcPeerConnectionHolder, didChangeState state: RTCDataChannelState) async {
        os_log("☎️ Data channel changed state. New state is %{public}@", log: log, type: .info, state.description)
        switch state {
        case .open:
            await delegate?.dataChannelIsOpened(for: self)
            await sendMutedMessageJSON()
        case .connecting, .closing, .closed:
            break
        @unknown default:
            assertionFailure()
        }
    }

    func sendMutedMessageJSON() async {
        let message: WebRTCDataChannelMessageJSON
        do {
            message = try await MutedMessageJSON(muted: isMuted).embedInWebRTCDataChannelMessageJSON()
        } catch {
            os_log("☎️ Could not send MutedMessageJSON: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }
        do {
            try await peerConnectionHolder?.sendDataChannelMessage(message)
        } catch {
            os_log("☎️ Could not send data channel message: %{public}@", log: log, type: .fault, error.localizedDescription)
            return
        }
    }


    func sendNewIceCandidateMessage(candidate: RTCIceCandidate) async throws {
        try await delegate?.sendNewIceCandidateMessage(to: self, iceCandidate: candidate)
    }


    func sendRemoveIceCandidatesMessages(candidates: [RTCIceCandidate]) async throws {
        try await delegate?.sendRemoveIceCandidatesMessages(to: self, candidates: candidates)
    }

    
     /// Send the local description to the call participant corresponding to `self`
    func sendLocalDescription(sessionDescription: RTCSessionDescription, reconnectCounter: Int, peerReconnectCounterToOverride: Int) async {
        
        os_log("☎️ Calling sendLocalDescription for a participant", log: log, type: .info)
        
        guard let delegate = self.delegate else { assertionFailure(); return }
        
        do {
            switch self.state {
            case .initial:
                os_log("☎️ Sending peer the following SDP: %{public}@", log: log, type: .info, sessionDescription.sdp)
                switch ownRole {
                case .caller:
                    guard let turnCredentials = self.turnCredentials else { assertionFailure(); throw Self.makeError(message: "Turn credentials are required") }
                    try await delegate.sendStartCallMessage(to: self, sessionDescription: sessionDescription, turnCredentials: turnCredentials)
                    try await setPeerState(to: .startCallMessageSent)
                case .recipient:
                    switch self.role {
                    case .caller:
                        try await delegate.sendAnswerCallMessage(to: self, sessionDescription: sessionDescription)
                        try await setPeerState(to: .connectingToPeer)
                    case .recipient:
                        if await shouldISendTheOfferToCallParticipant() {
                            try await delegate.sendNewParticipantOfferMessage(to: self, sessionDescription: sessionDescription)
                            try await self.setPeerState(to: .startCallMessageSent)
                        } else {
                            try await delegate.sendNewParticipantAnswerMessage(to: self, sessionDescription: sessionDescription)
                            try await self.setPeerState(to: .connectingToPeer)
                        }
                    case .none:
                        assertionFailure()
                        return
                    }
                case .none:
                    assertionFailure()
                }
            case .connected, .reconnecting:
                os_log("☎️ Sending peer the following restart SDP: %{public}@", log: log, type: .info, sessionDescription.sdp)
                try await delegate.sendReconnectCallMessage(to: self, sessionDescription: sessionDescription, reconnectCounter: reconnectCounter, peerReconnectCounterToOverride: peerReconnectCounterToOverride)
            case .startCallMessageSent, .ringing, .busy, .callRejected, .connectingToPeer, .hangedUp, .kicked, .failed:
                break // Do nothing
            }
        } catch {
            try? await self.setPeerState(to: .failed)
            assertionFailure()
            return
        }
        
    }

}


fileprivate extension IceCandidateJSON {
    var iceCandidate: RTCIceCandidate {
        RTCIceCandidate(sdp: sdp, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
    }
}

fileprivate extension RemoveIceCandidatesMessageJSON {
    var iceCandidates: [RTCIceCandidate] {
        candidates.map { $0.iceCandidate }
    }
}
