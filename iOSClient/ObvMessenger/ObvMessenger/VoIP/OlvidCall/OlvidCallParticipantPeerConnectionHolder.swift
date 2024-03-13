/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import WebRTC
import ObvSettings


protocol OlvidCallParticipantPeerConnectionHolderDelegate: AnyObject {
    
    func peerConnectionStateDidChange(newState: RTCIceConnectionState) async
    func dataChannel(of peerConnectionHolder: OlvidCallParticipantPeerConnectionHolder, didReceiveMessage message: WebRTCDataChannelMessageJSON) async
    func dataChannel(of peerConnectionHolder: OlvidCallParticipantPeerConnectionHolder, didChangeState state: RTCDataChannelState) async
    func peerConnectionHolder(_ peerConnectionHolder: OlvidCallParticipantPeerConnectionHolder, didAddLocalVideoTrack videoTrack: RTCVideoTrack) async
    func peerConnectionHolder(_ peerConnectionHolder: OlvidCallParticipantPeerConnectionHolder, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) async

    func sendNewIceCandidateMessage(candidate: RTCIceCandidate) async throws
    func sendRemoveIceCandidatesMessages(candidates: [RTCIceCandidate]) async throws

    func sendLocalDescription(sessionDescription: RTCSessionDescription, reconnectCounter: Int, peerReconnectCounterToOverride: Int) async
    
}


actor OlvidCallParticipantPeerConnectionHolder {
    
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "OlvidCallParticipantPeerConnectionHolder")

    /// Serial queue shared among all `OlvidCallParticipantPeerConnectionHolder`, among all calls.
    private let rtcPeerConnectionQueue: OperationQueue
    
    private let factory: ObvPeerConnectionFactory
    
    private(set) var turnCredentials: TurnCredentials?
    private(set) var gatheringPolicy: OlvidCallGatheringPolicy

    weak var delegate: OlvidCallParticipantPeerConnectionHolderDelegate?

    /// Used to save the remote session description obtained when receiving an incoming call.
    /// Since we do not create the underlying peer connection until the local user accepts (picks up) the call,
    /// We need to store the session description until she does so. If she does pick up the call, we create the
    /// Underlying peer connection and immediately set its session description using the value saved here.
    private var remoteSessionDescription: RTCSessionDescription?

    private var peerConnection: ObvPeerConnection?
    private var pendingRemoteIceCandidates = [RTCIceCandidate]()
    private var iceCandidatesGeneratedLocally = [RTCIceCandidate]() // Legacy, used when gatheringPolicy == gatherOnce
    private var reconnectOfferCounter: Int = 0 // Counter of the last reconnect offer we sent
    private var reconnectAnswerCounter: Int = 0 // Counter of the last reconnect offer from the peer for which we sent an answer
    private var iceGatheringCompletedWasCalled = false
    private let shouldISendTheOfferToCallParticipant: Bool
    /// ICE candidates can be processed after an SDP was set on the peer connection.
    private var readyToProcessPeerIceCandidates = false {
        didSet {
            guard self.readyToProcessPeerIceCandidates else { return }
            Task { await drainRemoteIceCandidates() }
        }
    }
    /// Allows the user to mute self before the peer connection is created (e.g., before answering the call)
    private var audioTrackIsEnabledOnCreation = true

    
    // Remark: we do not test whether self.rtcPeerConnection == peerConnection as it happens that self.rtcPeerConnection == nil
    // at this point. This happens as the rtcPeerConnection is created in an operation and only set after the operation finishes.
    // This callback is typically called because of the creation of the peer connection in the operation, reason why
    // we may have self.rtcPeerConnection == nil. But this is not an issue as we can use the peerConnection received as a parameter.
    
    /// Creating the peer connection is done by means of executing a ``CreatePeerConnectionOperation``. Once the operation finishes, we set ``self.rtcPeerConnection``
    /// to the value created by the operation. Yet, the sole fact to create this peer connection triggers calls to several ``RTCPeerConnectionDelegateWrapperDelegate`` delegate
    /// methods. These methods may be called before we have time to set ``self.rtcPeerConnection`` after the operation finishes. We made the choice to also set
    /// ``self.rtcPeerConnection`` from these delegate methods. We do so by always calling this function for setting ``self.rtcPeerConnection``.
    private func setRTCPeerConnectionIfRequired(_ newPeerConnection: ObvPeerConnection) {
        if let peerConnection {
            assert(peerConnection == newPeerConnection)
        } else {
            self.peerConnection = newPeerConnection
        }
    }


    /// Used when receiving an incoming call (the delegate shall be set immediately)
    init(startCallMessage: StartCallMessageJSON, shouldISendTheOfferToCallParticipant: Bool, rtcPeerConnectionQueue: OperationQueue, factory: ObvPeerConnectionFactory) {
        self.turnCredentials = startCallMessage.turnCredentials
        self.shouldISendTheOfferToCallParticipant = shouldISendTheOfferToCallParticipant
        self.remoteSessionDescription = RTCSessionDescription(type: startCallMessage.sessionDescriptionType,
                                                              sdp: startCallMessage.sessionDescription)
        self.gatheringPolicy = startCallMessage.gatheringPolicy ?? .gatherOnce
        self.rtcPeerConnectionQueue = rtcPeerConnectionQueue
        self.factory = factory
        // We do *not* create the peer connection now, we wait until the user explicitely accepts the incoming call
    }

    
    /// Used during the init of an outgoing call. Also used during a multi-call, when we are a recipient and need to create a peer connection holder with another participant.
    /// When calling this initalizer, one should immediately call ``setDelegate(to:)``.
    init(gatheringPolicy: OlvidCallGatheringPolicy, shouldISendTheOfferToCallParticipant: Bool, rtcPeerConnectionQueue: OperationQueue, factory: ObvPeerConnectionFactory) {
        self.gatheringPolicy = gatheringPolicy
        self.shouldISendTheOfferToCallParticipant = shouldISendTheOfferToCallParticipant
        self.remoteSessionDescription = nil
        self.rtcPeerConnectionQueue = rtcPeerConnectionQueue
        self.factory = factory
    }
    
    
    deinit {
        os_log("☎️ OlvidCallParticipantPeerConnectionHolder deinit", log: Self.log, type: .debug)
    }
    
    
    func setDelegate(to newDelegate: OlvidCallParticipantPeerConnectionHolderDelegate) {
        assert(self.delegate == nil)
        self.delegate = newDelegate
    }
    
}


// MARK: - Dealing with incoming calls

extension OlvidCallParticipantPeerConnectionHolder {
    
    /// When receiving an incoming call, we quickly create this peer connection holder, but we do not create the underlying peer connection.
    /// For this, we want to wait until the user explictely accepts (picks up) the incoming call.
    /// This method is called when the local user does so.
    /// It creates the peer connection. This will eventually trigger a call to
    /// ``func peerConnectionShouldNegotiate(_ peerConnection: ObvPeerConnection) async``
    /// where the local description (answer) will be created.
    func createPeerConnectionIfRequiredAfterAcceptingAnIncomingCall(delegate: OlvidCallParticipantPeerConnectionHolderDelegate) async throws {
        assert(self.peerConnection == nil)
        assert(self.delegate == nil)
        self.delegate = delegate
        try await createPeerConnectionIfRequired()
    }

    
    /// Used for an incoming call that was already accepted, when the caller adds a participant to the call
    func setRemoteDescriptionAndTurnCredentialsThenCreateTheUnderlyingPeerConnectionIfRequired(newParticipantOfferMessage: NewParticipantOfferMessageJSON, turnCredentials: TurnCredentials) async throws {

        os_log("☎️ Setting remote description and turn credentials, then creating peer connection", log: Self.log, type: .info)
        
        assert(self.delegate != nil)

        self.turnCredentials = turnCredentials
        self.remoteSessionDescription = RTCSessionDescription(type: newParticipantOfferMessage.sessionDescriptionType,
                                                              sdp: newParticipantOfferMessage.sessionDescription)
        
        // We override the gathering policy we had (indicated by the caller for this participant) by the one sent the participant herself.
        self.gatheringPolicy = newParticipantOfferMessage.gatheringPolicy ?? .gatherOnce
        
        // Since the call was already accepted (we are only adding another participant here), we can safely create the peer connection immediately.
        // The situation here is different from the one encountered in the initializer executed when receiving an incoming call, where we had to wait
        // Until the local user explicitely accepted the call.
        
        try await createPeerConnectionIfRequired()
        
    }

}


// MARK: - Creating and closing the peer connection

extension OlvidCallParticipantPeerConnectionHolder {
    
    /// This method is two situations:
    /// - During an outgoing call, when setting the turn credential of a call participant.
    /// - During a multi-users incoming call, when we are in charge of sending the offer to another recipient (who isn't the caller).
    func setTurnCredentialsAndCreateUnderlyingPeerConnectionIfRequired(_ turnCredentials: TurnCredentials) async throws {
        assert(self.delegate != nil)
        guard self.turnCredentials == nil else {
            assertionFailure()
            throw ObvError.turnCredentialsAreSetAlready
        }
        self.turnCredentials = turnCredentials
        try await createPeerConnectionIfRequired()
    }


    func close() async {
        guard let peerConnection else {
            os_log("☎️🛑 Execute signaling state closed completion handler: peer connection is nil", log: Self.log, type: .info)
            return
        }
        let op = ClosePeerConnectionOperation(peerConnection: peerConnection)
        os_log("☎️ Operations in the queue: %{public}@ before adding %{public}@", log: Self.log, type: .info, rtcPeerConnectionQueue.operations.debugDescription, op.debugDescription)
        await rtcPeerConnectionQueue.addAndAwaitOperation(op)
    }

    
    /// This method creates the peer connection underlying this peer connection holder.
    ///
    /// This method is called in two situations :
    /// - For an outgoing call, it is called right after setting the credentials.
    /// - For an incoming call, it is not called when setting the credentials as we want to wait until the user explicitely accepts (picks up) the incoming call.
    ///   It is called as soon as the user accepts the incoming call.
    private func createPeerConnectionIfRequired() async throws {

        os_log("☎️ Call to createPeerConnection", log: Self.log, type: .info)

        guard peerConnection == nil else {
            os_log("☎️ No need to create the peer connection, it already exists", log: Self.log, type: .info)
            assert(delegate != nil)
            return
        }
        
        guard delegate != nil else {
            os_log("☎️ The delegate is nil, which not expected", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.delegateIsNil
        }
        
        guard let turnCredentials else {
            os_log("☎️ No turn credentials availabe", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.noTurnCredentialsAvailable
        }

        // Create the peer connection and store it
        
        os_log("☎️ Creating the RTC peer connection", log: Self.log, type: .info)

        var operationsToQueue = [Operation]()
        
        let op1 = CreatePeerConnectionOperation(
            turnCredentials: turnCredentials,
            gatheringPolicy: gatheringPolicy, 
            isAudioTrackEnabled: audioTrackIsEnabledOnCreation,
            factory: factory,
            obvPeerConnectionDelegate: self,
            obvDataChannelDelegate: self)
        
        operationsToQueue.append(op1)
        
        // We might already have a session description available. This typically happens when receiving an incoming call:
        // We created the call and saved the session description for later, i.e., for the time the local user accepts the incoming call,
        // Which is what led us here.
        
        let shouldSetReadyToProcessPeerIceCandidates: Bool
        if let remoteSessionDescription {
            self.remoteSessionDescription = nil
            let op2 = SetRemoteDescriptionOperation(input: .createPeerConnectionOperation(operation: op1), remoteSessionDescription: remoteSessionDescription)
            op2.addDependency(op1)
            operationsToQueue.append(op2)
            shouldSetReadyToProcessPeerIceCandidates = true
        } else {
            shouldSetReadyToProcessPeerIceCandidates = false
        }
        
        os_log("☎️ Operations in the queue: %{public}@ before adding %{public}@", log: Self.log, type: .info, rtcPeerConnectionQueue.operations.debugDescription, operationsToQueue.debugDescription)
        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        await rtcPeerConnectionQueue.addAndAwaitOperations(operationsToQueue)
        
        guard let peerConnection = op1.peerConnection else {
            assertionFailure()
            throw ObvError.peerConnectionCreationFailed
        }
        
        setRTCPeerConnectionIfRequired(peerConnection)
        
        os_log("☎️ The RTC peer connection was created", log: Self.log, type: .info)
        
        if shouldSetReadyToProcessPeerIceCandidates {
            self.readyToProcessPeerIceCandidates = true
        }
        
    }

    
    private func createRTCConfiguration(turnCredentials: TurnCredentials) -> RTCConfiguration {
    
        // 2022-03-11, we used to use the servers indicated in the turn credentials.
        // We do not do that anymore and use the (user) preferred servers.
        let iceServer = WebRTC.RTCIceServer(urlStrings: ObvMessengerConstants.ICEServerURLs.preferred,
                                            username: turnCredentials.turnUserName,
                                            credential: turnCredentials.turnPassword,
                                            tlsCertPolicy: .insecureNoCheck)

        let rtcConfiguration = RTCConfiguration()
        rtcConfiguration.iceServers = [iceServer]
        rtcConfiguration.iceTransportPolicy = .relay
        rtcConfiguration.sdpSemantics = .unifiedPlan
        rtcConfiguration.continualGatheringPolicy = gatheringPolicy.rtcPolicy
        
        return rtcConfiguration
        
    }
    
    
}


// MARK: - Gathering ICE candidates

extension OlvidCallParticipantPeerConnectionHolder {
    
    private func drainRemoteIceCandidates() async {
        guard case .gatherContinually = gatheringPolicy else { return }
        guard readyToProcessPeerIceCandidates else { assertionFailure(); return }
        guard !pendingRemoteIceCandidates.isEmpty else { return }
        os_log("☎️❄️ Drain remote %{public}@ ICE candidate(s)", log: Self.log, type: .info, String(pendingRemoteIceCandidates.count))
        let pendingRemoteIceCandidates = self.pendingRemoteIceCandidates
        self.pendingRemoteIceCandidates.removeAll()
        for iceCandidate in pendingRemoteIceCandidates {
            do {
                try await addIceCandidate(iceCandidate: iceCandidate)
            } catch {
                os_log("☎️ Could not drain one of the ice candidates: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                assertionFailure() // Continue anyway
            }
        }
    }

    
    func addIceCandidate(iceCandidate: RTCIceCandidate) async throws {
        os_log("☎️❄️ addIceCandidate called", log: Self.log, type: .info)
        guard gatheringPolicy == .gatherContinually else { assertionFailure(); return }
        if readyToProcessPeerIceCandidates {
            os_log("☎️❄️ As we are ready to process ICE candidates, we will queue an AddIceCandidateOperation", log: Self.log, type: .info)
            guard let peerConnection else { assertionFailure("We expect rtcPeerConnection to exist when readyToProcessPeerIceCandidates is true"); return }
            let op = AddIceCandidateOperation(input: .peerConnection(peerConnection: peerConnection), iceCandidate: iceCandidate)
            os_log("☎️ Operations in the queue: %{public}@ before adding %{public}@", log: Self.log, type: .info, rtcPeerConnectionQueue.operations.debugDescription, op.debugDescription)
            await rtcPeerConnectionQueue.addAndAwaitOperation(op)
            guard !op.isCancelled else {
                assertionFailure()
                throw ObvError.addIceCandidateFailed(error: op.reasonForCancel)
            }
        } else {
            os_log("☎️❄️ Not ready to forward remote ICE candidates, add candidate to pending list (count %{public}@)", log: Self.log, type: .info, String(pendingRemoteIceCandidates.count))
            pendingRemoteIceCandidates.append(iceCandidate)
        }
    }


    func removeIceCandidates(iceCandidates: [RTCIceCandidate]) async {
        os_log("☎️❄️ removeIceCandidates called", log: Self.log, type: .info)
        if readyToProcessPeerIceCandidates {
            guard let peerConnection else { assertionFailure("We expect rtcPeerConnection to exist when readyToProcessPeerIceCandidates is true"); return }
            let op = RemoveIceCandidatesOperation(peerConnection: peerConnection, iceCandidates: iceCandidates)
            os_log("☎️ Operations in the queue: %{public}@ before adding %{public}@", log: Self.log, type: .info, rtcPeerConnectionQueue.operations.debugDescription, op.debugDescription)
            await rtcPeerConnectionQueue.addAndAwaitOperation(op)
        } else {
            os_log("☎️❄️ Not ready to forward remote ICE candidates, remove candidates from pending list (count %{public}@)", log: Self.log, type: .info, String(pendingRemoteIceCandidates.count))
            pendingRemoteIceCandidates.removeAll { iceCandidates.contains($0) }
        }
    }

    
    private func resetGatheringState() {
        guard case .gatherOnce = gatheringPolicy else { assertionFailure(); return }
        iceCandidatesGeneratedLocally.removeAll()
        iceGatheringCompletedWasCalled = false
    }

    
    /// Only used in the (rare) case where the gathering policy is `.gatherOnce`.
    private func iceGatheringCompleted() async throws {

        guard gatheringPolicy == .gatherOnce else { assertionFailure(); return }
        
        guard !iceGatheringCompletedWasCalled else { return }
        iceGatheringCompletedWasCalled = true

        os_log("☎️ ICE gathering is completed", log: Self.log, type: .info)

        guard let localDescription = await peerConnection?.localDescription else { assertionFailure(); return }
        guard let delegate = delegate else { assertionFailure(); return }
    
        switch localDescription.type {
        case .offer:
            await delegate.sendLocalDescription(sessionDescription: localDescription, reconnectCounter: reconnectOfferCounter, peerReconnectCounterToOverride: reconnectAnswerCounter)
        case .answer:
            await delegate.sendLocalDescription(sessionDescription: localDescription, reconnectCounter: reconnectAnswerCounter, peerReconnectCounterToOverride: -1)
        case .prAnswer, .rollback:
            assertionFailure() // Do nothing
        @unknown default:
            assertionFailure() // Do nothing
        }

    }

}


// MARK: - Implementing RTCDataChannelDelegateWrapperDelegate (wrapper around a RTCDataChannelDelegate) and other methods

extension OlvidCallParticipantPeerConnectionHolder: ObvDataChannelDelegate {
    
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) async {
        os_log("☎️ Data Channel %{public}@ has a new state: %{public}@", log: Self.log, type: .info, dataChannel.debugDescription, dataChannel.readyState.description)
        await delegate?.dataChannel(of: self, didChangeState: dataChannel.readyState)
    }
    
    
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) async {
        os_log("☎️ Data Channel %{public}@ did receive message with buffer", log: Self.log, type: .info, dataChannel.debugDescription)
        assert(!buffer.isBinary)
        let webRTCDataChannelMessageJSON: WebRTCDataChannelMessageJSON
        do {
            webRTCDataChannelMessageJSON = try WebRTCDataChannelMessageJSON.jsonDecode(data: buffer.data)
        } catch {
            os_log("☎️ Could not decode message received on the RTC data channel as a WebRTCMessageJSON: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            return
        }
        assert(delegate != nil)
        await delegate?.dataChannel(of: self, didReceiveMessage: webRTCDataChannelMessageJSON)
    }
    
    
    func sendDataChannelMessage(_ message: WebRTCDataChannelMessageJSON) async throws {
        guard let peerConnection else {
            throw ObvError.noPeerConnectionAvailable
        }
        let op = SendDataThroughPeerConnectionOperation(peerConnection: peerConnection, message: message)
        // Do not await the end of this operation, as it might take a long time
        os_log("☎️ Operations in the queue: %{public}@ before adding %{public}@", log: Self.log, type: .info, rtcPeerConnectionQueue.operations.debugDescription, op.debugDescription)
        rtcPeerConnectionQueue.addOperation(op)
    }

}


// MARK: - Implementing RTCPeerConnectionDelegateWrapperDelegate (wrapper around a RTCPeerConnectionDelegate)

extension OlvidCallParticipantPeerConnectionHolder: ObvPeerConnectionDelegate {
        
    /// According to https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API/Perfect_negotiation,
    /// This is the best place to get and set a local description and send it using the signaling channel to the remote peer.
    func peerConnectionShouldNegotiate(_ peerConnection: ObvPeerConnection) async {
        
        os_log("☎️ Peer Connection should negociate was called", log: Self.log, type: .info)
        setRTCPeerConnectionIfRequired(peerConnection)
        
        do {
            try await createAndSetLocalDescriptionIfAppropriate(peerConnection: peerConnection)
        } catch  {
            assertionFailure()
        }
        
    }
    
    
    /// Called in two situations:
    /// - When the peer connection should negociate
    /// - In certain cases, when handling a restart SDP
    private func createAndSetLocalDescriptionIfAppropriate(peerConnection: ObvPeerConnection) async throws {
        
        let op = CreateAndSetLocalDescriptionIfAppropriateOperation(
            peerConnection: peerConnection,
            gatheringPolicy: gatheringPolicy,
            maxaveragebitrate: ObvMessengerSettings.VoIP.maxaveragebitrate,
            delegate: self)

        os_log("☎️ Operations in the queue: %{public}@ before adding %{public}@", log: Self.log, type: .info, rtcPeerConnectionQueue.operations.debugDescription, op.debugDescription)

        await rtcPeerConnectionQueue.addAndAwaitOperation(op)

        guard op.isFinished && !op.isCancelled else {
            assertionFailure()
            throw ObvError.createAndSetLocalDescriptionIfAppropriateFailed(error: op.reasonForCancel)
        }

        if op.gaetheringStateNeedsToBeReset {
            resetGatheringState()
        }
        
        if let toSend = op.toSend {
            guard let delegate else { return }
            os_log("☎️ Sending the local description (%{public}@) we just created and set", log: Self.log, type: .info, toSend.filteredSessionDescription.type.debugDescription)
            await delegate.sendLocalDescription(sessionDescription: toSend.filteredSessionDescription, reconnectCounter: toSend.reconnectCounter, peerReconnectCounterToOverride: toSend.peerReconnectCounterToOverride)
        }
        
    }

    
    func peerConnection(_ peerConnection: ObvPeerConnection, didChange newState: RTCPeerConnectionState) async {
        os_log("☎️ RTCPeerConnection didChange RTCPeerConnectionState: %{public}@", log: Self.log, type: .info, newState.debugDescription)
    }


    func peerConnection(_ peerConnection: ObvPeerConnection, didChange stateChanged: RTCSignalingState) async {
        os_log("☎️ RTCPeerConnection didChange RTCSignalingState: %{public}@. Current ICE connection state is %{public}@", log: Self.log, type: .info, stateChanged.debugDescription, peerConnection.iceConnectionState.debugDescription)
        self.setRTCPeerConnectionIfRequired(peerConnection)
        if stateChanged == .stable && peerConnection.iceConnectionState == .connected {
            await delegate?.peerConnectionStateDidChange(newState: .connected)
        }
        if stateChanged == .closed {
            os_log("☎️🛑 Signaling state is closed", log: Self.log, type: .info)
        }
    }
    
    
    func peerConnection(_ peerConnection: ObvPeerConnection, didAdd stream: RTCMediaStream) async {
        os_log("☎️ RTCPeerConnection didAdd RTCMediaStream", log: Self.log, type: .info)
        setRTCPeerConnectionIfRequired(peerConnection)
    }
    
    
    func peerConnection(_ peerConnection: ObvPeerConnection, didRemove stream: RTCMediaStream) async {
        os_log("☎️ RTCPeerConnection didRemove RTCMediaStream", log: Self.log, type: .info)
        setRTCPeerConnectionIfRequired(peerConnection)
    }
    
    
    func peerConnection(_ peerConnection: ObvPeerConnection, didChange newState: RTCIceConnectionState) async {
        os_log("☎️ RTCPeerConnection didChange RTCIceConnectionState: %{public}@", log: Self.log, type: .info, newState.debugDescription)
        setRTCPeerConnectionIfRequired(peerConnection)
        await delegate?.peerConnectionStateDidChange(newState: newState)
    }
    
    
    func peerConnection(_ peerConnection: ObvPeerConnection, didChange newState: RTCIceGatheringState) async {
        os_log("☎️❄️ Peer Connection Ice Gathering State changed to: %{public}@", log: Self.log, type: .info, newState.debugDescription)
        setRTCPeerConnectionIfRequired(peerConnection)
        guard case .gatherOnce = gatheringPolicy else { return }
        switch newState {
        case .new:
            break
        case .gathering:
            // We start gathering --> clear the turnCandidates list
            resetGatheringState()
        case .complete:
            switch gatheringPolicy {
            case .gatherOnce:
                if iceCandidatesGeneratedLocally.isEmpty {
                    os_log("☎️❄️ No ICE candidates found", log: Self.log, type: .info)
                } else {
                    // We have all we need to send the local description to the caller.
                    os_log("☎️❄️ Calls completed ICE Gathering with %{public}@ candidates", log: Self.log, type: .info, String(self.iceCandidatesGeneratedLocally.count))
                    Task {
                        try? await iceGatheringCompleted()
                    }
                }
            case .gatherContinually:
                break // Do nothing
            }
        @unknown default:
            assertionFailure()
        }
    }
    
    
    func peerConnection(_ peerConnection: ObvPeerConnection, didGenerate candidate: RTCIceCandidate) async {
        os_log("☎️❄️ Peer Connection didGenerate RTCIceCandidate", log: Self.log, type: .info)
        setRTCPeerConnectionIfRequired(peerConnection)
        switch gatheringPolicy {
        case .gatherOnce:
            iceCandidatesGeneratedLocally.append(candidate)
            if iceCandidatesGeneratedLocally.count == 1 { /// At least one candidate, we wait one second and hope that the other candidate will be added.
                try? await Task.sleep(seconds: 2)
                try? await iceGatheringCompleted()
            }
        case .gatherContinually:
            Task {
                try? await delegate?.sendNewIceCandidateMessage(candidate: candidate)
            }
        }
    }
    
    
    func peerConnection(_ peerConnection: ObvPeerConnection, didRemove candidates: [RTCIceCandidate]) async {
        os_log("☎️❄️ Peer Connection didRemove RTCIceCandidate", log: Self.log, type: .info)
        assert(delegate != nil)
        setRTCPeerConnectionIfRequired(peerConnection)
        switch gatheringPolicy {
        case .gatherOnce:
            iceCandidatesGeneratedLocally.removeAll { candidates.contains($0) }
        case .gatherContinually:
            try? await delegate?.sendRemoveIceCandidatesMessages(candidates: candidates)
        }
    }

    
    func peerConnection(_ peerConnection: ObvPeerConnection, didOpen dataChannel: RTCDataChannel) async {
        os_log("☎️ Peer Connection didOpen RTCDataChannel", log: Self.log, type: .info)
        setRTCPeerConnectionIfRequired(peerConnection)
    }
    
    
    func peerConnection(_ peerConnection: ObvPeerConnection, didAddLocalVideoTrack videoTrack: RTCVideoTrack) async {
        guard let delegate else { return }
        await delegate.peerConnectionHolder(self, didAddLocalVideoTrack: videoTrack)
    }
 
    
    func peerConnection(_ peerConnection: ObvPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) async {
        guard let delegate else { return }
        await delegate.peerConnectionHolder(self, didAdd: rtpReceiver, streams: mediaStreams)
    }
    
}


// MARK: - Managing session descriptions

extension OlvidCallParticipantPeerConnectionHolder {
        
    func setRemoteDescription(_ sessionDescription: RTCSessionDescription) async throws {
        
        os_log("☎️ Setting a session description of type %{public}@", log: Self.log, type: .info, sessionDescription.type.debugDescription)
        
        guard let peerConnection else {
            assertionFailure()
            throw ObvError.noPeerConnectionAvailable
        }

        // Since we are setting a remote description, we expect to be either in the stable or haveLocalOffer states.
        // We do not test this though, as the following call will throw if we are not in one of these states.

        let op = SetRemoteDescriptionOperation(input: .peerConnection(peerConnection: peerConnection), remoteSessionDescription: sessionDescription)
        os_log("☎️ Operations in the queue: %{public}@ before adding %{public}@", log: Self.log, type: .info, rtcPeerConnectionQueue.operations.debugDescription, op.debugDescription)
        await rtcPeerConnectionQueue.addAndAwaitOperation(op)
        guard !op.isCancelled else {
            throw ObvError.setRemoteDescriptionFailed(error: op.reasonForCancel)
        }
        self.readyToProcessPeerIceCandidates = true
        
    }
    

    func handleReceivedRestartSdp(sessionDescription: RTCSessionDescription, reconnectCounter: Int, peerReconnectCounterToOverride: Int, shouldISendTheOfferToCallParticipant: Bool) async throws {
        
        guard let peerConnection else {
            assertionFailure("We expect rtcPeerConnection to exist at this point")
            throw ObvError.noPeerConnectionAvailable
        }
        
        let op = HandleReceivedRestartSdpOperation(
            peerConnection: peerConnection,
            sessionDescription: sessionDescription,
            receivedReconnectCounter: reconnectCounter, // ok
            receivedPeerReconnectCounterToOverride: peerReconnectCounterToOverride, //ok
            shouldISendTheOfferToCallParticipant: shouldISendTheOfferToCallParticipant,
            delegate: self)
        
        os_log("☎️ Operations in the queue: %{public}@ before adding %{public}@", log: Self.log, type: .info, rtcPeerConnectionQueue.operations.debugDescription, op.debugDescription)

        await rtcPeerConnectionQueue.addAndAwaitOperation(op)
        
        guard op.isFinished && !op.isCancelled else {
            assertionFailure()
            throw ObvError.handleReceivedRestartSdpFailed(error: op.reasonForCancel)
        }
        
        if op.shouldCreateAndSetLocalDescription {
            
            try await createAndSetLocalDescriptionIfAppropriate(peerConnection: peerConnection)

        }

    }

}


// MARK: - HandleReceivedRestartSdpOperationDelegate

extension OlvidCallParticipantPeerConnectionHolder: HandleReceivedRestartSdpOperationDelegate {
    
    /// This gets called during the execution of a ``HandleReceivedRestartSdpOperation``
    func setReconnectAnswerCounter(op: HandleReceivedRestartSdpOperation, newReconnectAnswerCounter: Int) async {
        os_log("☎️ Setting the reconnectAnswerCounter to %d", log: Self.log, type: .info, newReconnectAnswerCounter)
        self.reconnectAnswerCounter = newReconnectAnswerCounter
    }
 
    /// This gets called during the execution of a ``HandleReceivedRestartSdpOperation``
    func getReconnectOfferCounter(op: HandleReceivedRestartSdpOperation) async -> Int {
        return self.reconnectOfferCounter
    }
    
    /// This gets called during the execution of a ``HandleReceivedRestartSdpOperation``
    func getReconnectAnswerCounter(op: HandleReceivedRestartSdpOperation) async -> Int {
        return self.reconnectAnswerCounter
    }
    
}


// MARK: - CreateAndSetLocalDescriptionIfAppropriateOperationDelegate

extension OlvidCallParticipantPeerConnectionHolder: CreateAndSetLocalDescriptionIfAppropriateOperationDelegate {
    
    /// This gets called during the execution of a ``CreateAndSetLocalDescriptionIfAppropriateOperation``
    func getReconnectAnswerCounter(op: CreateAndSetLocalDescriptionIfAppropriateOperation) async -> Int {
        return self.reconnectAnswerCounter
    }
    
    /// This gets called during the execution of a ``CreateAndSetLocalDescriptionIfAppropriateOperation``
    func getReconnectOfferCounter(op: CreateAndSetLocalDescriptionIfAppropriateOperation) async -> Int {
        return self.reconnectOfferCounter
    }
    
    /// This gets called during the execution of a ``CreateAndSetLocalDescriptionIfAppropriateOperation``
    func incrementReconnectOfferCounter(op: CreateAndSetLocalDescriptionIfAppropriateOperation) async {
        self.reconnectOfferCounter += 1
    }
    
}


// MARK: - Video

extension OlvidCallParticipantPeerConnectionHolder {
    
    func createAndAddLocalVideoAndScreencastTracks() async throws {
        
        guard let peerConnection else {
            assertionFailure()
            throw ObvError.noPeerConnectionAvailable
        }
        
        await peerConnection.createAndAddLocalVideoAndScreencastTracks()

    }

    
    func setLocalVideoTrack(isEnabled: Bool) async throws {
        
        guard let peerConnection else {
            assertionFailure()
            throw ObvError.noPeerConnectionAvailable
        }

        await peerConnection.setLocalVideoTrack(isEnabled: isEnabled)
        
    }

}


// MARK: - Audio control

extension OlvidCallParticipantPeerConnectionHolder {

    func setAudioTrack(isEnabled: Bool) async throws {
        guard let peerConnection else {
            self.audioTrackIsEnabledOnCreation = isEnabled
            return
        }
        try await peerConnection.setAudioTrack(isEnabled: isEnabled)
    }

    var isAudioTrackEnabled: Bool {
        get throws {
            guard let peerConnection else {
                return audioTrackIsEnabledOnCreation
            }
            return try peerConnection.isAudioTrackEnabled
        }
    }
}


// MARK - Errors

extension OlvidCallParticipantPeerConnectionHolder {
    
    enum ObvError: Error, CustomStringConvertible {
        
        case noTurnCredentialsAvailable
        case couldNotFindExpectedMatchInSDP
        case turnCredentialsAreSetAlready
        case noPeerConnectionAvailable
        case unexpectedNumberOfMediaLinesInSessionDescription
        case delegateIsNil
        case peerConnectionCreationFailed
        case setRemoteDescriptionFailed(error: SetRemoteDescriptionOperation.ReasonForCancel?)
        case addIceCandidateFailed(error: AddIceCandidateOperation.ReasonForCancel?)
        case dataChannelIsNil
        case sendDataChannelMessage(error: SendDataThroughPeerConnectionOperation.ReasonForCancel?)
        case handleReceivedRestartSdpFailed(error: HandleReceivedRestartSdpOperation.ReasonForCancel?)
        case handleReceivedRestartSdpFailedAsLocalDescriptionCouldNotBeSet(error: CreateAndSetLocalDescriptionIfAppropriateOperation.ReasonForCancel?)
        case createAndSetLocalDescriptionIfAppropriateFailed(error: CreateAndSetLocalDescriptionIfAppropriateOperation.ReasonForCancel?)
        
        var description: String {
            switch self {
            case .noTurnCredentialsAvailable:
                return "No turn credentials available"
            case .couldNotFindExpectedMatchInSDP:
                return "Could not find expected match in SDP"
            case .turnCredentialsAreSetAlready:
                return "Turn credentials already set"
            case .noPeerConnectionAvailable:
                return "No peer connection available"
            case .unexpectedNumberOfMediaLinesInSessionDescription:
                return "Unexpected number of media lines in session description"
            case .delegateIsNil:
                return "Delegate is nil"
            case .peerConnectionCreationFailed:
                return "Peer connection creation failed"
            case .setRemoteDescriptionFailed(error: let error):
                return "Set remote description failed: \(error?.localizedDescription ?? "No reason specified")"
            case .addIceCandidateFailed(error: let error):
                return "Add ICE candidate failed: \(error?.localizedDescription ?? "No reason specified")"
            case .dataChannelIsNil:
                return "Data channel is nil"
            case .sendDataChannelMessage(error: let error):
                return "Send data channel message failed: \(error?.localizedDescription ?? "No reason specified")"
            case .handleReceivedRestartSdpFailed(error: let error):
                return "Handle received restart SDP failed: \(error?.localizedDescription ?? "No reason specified")"
            case .handleReceivedRestartSdpFailedAsLocalDescriptionCouldNotBeSet(error: let error):
                return "Handle received restart SDP failed (local description could not be set): \(error?.localizedDescription ?? "No reason specified")"
            case .createAndSetLocalDescriptionIfAppropriateFailed(error: let error):
                return "Create and set local description if appropriate failed: \(error?.localizedDescription ?? "No reason specified")"
            }
        }
        
    }
    
}
