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
import OlvidUtils
import os.log



final actor WebrtcPeerConnectionHolder: ObvPeerConnectionDelegate, CallDataChannelWorkerDelegate, ObvErrorMaker {

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: WebrtcPeerConnectionHolder.self))
    static let errorDomain = "WebrtcPeerConnectionHolder"

    private(set) var gatheringPolicy: GatheringPolicy

    private var iceCandidates = [RTCIceCandidate]()
    private var pendingRemoteIceCandidates = [RTCIceCandidate]()
    private var readyToProcessPeerIceCandidates = false {
        didSet {
            Task {
                guard readyToProcessPeerIceCandidates else { return }
                os_log("☎️❄️ Forwarding remote ICE candidates is ready", log: self.log, type: .info)
                await drainRemoteIceCandidates()
            }
        }
    }
    private var iceGatheringCompletedWasCalled = false
    private var reconnectOfferCounter: Int = 0 // Counter of the last reconnect offer we sent
    private var reconnectAnswerCounter: Int = 0 // Counter of the last reconnect offer from the peer for which we sent an answer

    private static let audioCodecs = Set(["opus", "PCMU", "PCMA", "telephone-event", "red"])

    private var dataChannelWorker: DataChannelWorker?
    weak var delegate: WebrtcPeerConnectionHolderDelegate?

    private(set) var turnCredentials: TurnCredentials?
    
    /// The ``createPeerConnection()`` method being highly asynchronous, it occurs that
    /// ``func peerConnectionShouldNegotiate(_ peerConnection: ObvPeerConnection) async``
    /// is called although we did not properly finish the creation of the peer connection (i.e., we did not had time to add tracks or
    /// To consider a potential received remote session description). This Boolean value is thus set to `true` when starting the
    /// Peer connection creation, and set back to false when its appropriate to do so. If the
    /// ``func peerConnectionShouldNegotiate(_ peerConnection: ObvPeerConnection) async``
    /// is called when this Boolean is `true`, we do **not ** negotiate immediately but wait until this value is reset to `false`
    /// to do so.
    private var currentlyCreatingPeerConnection = false {
        didSet {
            guard !currentlyCreatingPeerConnection else { return }
            noLongerCreatingPeerConnection()
        }
    }
    
    /// This continuation allows to implement the mechanism allowing to wait until ``currentlyCreatingPeerConnection``
    /// Is set back to false before proceeding with a negotiation.
    private var continuationToResumeWhenPeerConnectionIsCreated: CheckedContinuation<Void, Never>?

    /// This Boolean is set to `true` when entering a method that could end up setting a local/remote description.
    /// It is set back to `false` whenever this method is done.
    /// It allows to implement a mechanism preventing two distinct methods to interfere when both can end up setting a description.
    private var aTaskIsCurrentlySettingSomeDescription = false {
        didSet {
            guard !aTaskIsCurrentlySettingSomeDescription else { return }
            oneOfTheTaskCurrentlySettingSomeDescriptionIsDone()
        }
    }

    /// See the comment about ``anotherTaskIsCurrentlySettingSomeDescription``.
    private var continuationsOfTaskWaitingUntilTheyCanSetSomeDescription = [CheckedContinuation<Void, Never>]()
    
    /// Used to save the remote session description obtained when receiving an incoming call.
    /// Since we do not create the underlying peer connection until the local user accepts (picks up) the call,
    /// We need to store the session description until she does so. If she does pick up the call, we create the
    /// Underlying peer connection and immediately set its session description using the value saved here.
    private var remoteSessionDescription: RTCSessionDescription?

    private var peerConnection: ObvPeerConnection?
    private var connectionState: RTCPeerConnectionState = .new

    private var audioTrack: RTCAudioTrack? = nil
    private var isAudioEnabled: Bool = true

    enum CompletionKind {
        case answer
        case offer
        case restart
    }

    private let mediaConstraints = [kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                                    kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueFalse]

    /// Used when receiving an incoming call
    init(startCallMessage: StartCallMessageJSON, delegate: WebrtcPeerConnectionHolderDelegate) {
        self.delegate = delegate
        self.turnCredentials = startCallMessage.turnCredentials
        self.remoteSessionDescription = RTCSessionDescription(type: startCallMessage.sessionDescriptionType,
                                                              sdp: startCallMessage.sessionDescription)
        self.gatheringPolicy = startCallMessage.gatheringPolicy ?? .gatherOnce

        // We do *not* create the peer connection now, we wait until the user explicitely accepts the incoming call

    }

    /// Used for an incoming call that was already accepted, when the caller adds a participant to the call
    func setRemoteDescriptionAndTurnCredentialsThenCreateTheUnderlyingPeerConnectionIfRequired(newParticipantOfferMessage: NewParticipantOfferMessageJSON, turnCredentials: TurnCredentials) async throws {

        os_log("☎️ Setting remote description and turn credentials, then creating peer connection", log: log, type: .info)
        
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


    /// Used during the init of an outgoing call. Also used during a multi-call, when we are a recipient and need to create a peer connection holder with another participant.
    init(gatheringPolicy: GatheringPolicy, delegate: WebrtcPeerConnectionHolderDelegate) {
        self.delegate = delegate
        self.gatheringPolicy = gatheringPolicy
        self.remoteSessionDescription = nil
    }
    

    private var additionalOpusOptions: String {
        var options = [(name: String, value: String)]()
        options.append(("cbr", "1"))
        if let maxaveragebitrate = ObvMessengerSettings.VoIP.maxaveragebitrate {
            options.append(("maxaveragebitrate", "\(maxaveragebitrate)"))
        }
        let optionsAsString = options.reduce("") { $0.appending(";\($1.name)=\($1.value)") }
        debugPrint(optionsAsString)
        return optionsAsString
    }

    
    func setTurnCredentialsAndCreateUnderlyingPeerConnectionIfRequired(_ turnCredentials: TurnCredentials) async throws {
        assert(self.delegate != nil)
        guard self.turnCredentials == nil else {
            assertionFailure()
            throw Self.makeError(message: "Turn credentials already set")
        }
        self.turnCredentials = turnCredentials
        try await createPeerConnectionIfRequired()
    }

    
    /// This method creates the peer connection underlying this peer connection holder.
    ///
    /// This method is called in two situations :
    /// - For an outgoing call, it is called right after setting the credentials.
    /// - For an incoming call, it is not called when setting the credentials as we want to wait until the user explicitely accepts (picks up) the incoming call.
    ///   It called as soon as the user accepts the incoming call.
    private func createPeerConnectionIfRequired() async throws {

        os_log("☎️ Call to createPeerConnection", log: log, type: .info)

        guard peerConnection == nil else {
            os_log("☎️ No need to create the peer connection, it already exists", log: log, type: .info)
            assert(delegate != nil)
            return
        }
        
        if delegate == nil {
            os_log("☎️ The delegate is nil, which not expected", log: log, type: .fault)
            assertionFailure()
        }
                
        currentlyCreatingPeerConnection = true
        defer { currentlyCreatingPeerConnection = false }
        
        guard let turnCredentials = turnCredentials else {
            throw Self.makeError(message: "No turn credentials available")
        }
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
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil,
                                              optionalConstraints: nil)
        os_log("☎️❄️ Create Peer Connection with %{public}@ policy", log: log, type: .info, gatheringPolicy.localizedDescription)

        guard let peerConnection = await ObvPeerConnection(with: rtcConfiguration, constraints: constraints, delegate: self) else { assertionFailure(); return }
        self.peerConnection = peerConnection
        
        os_log("☎️ Add Olvid audio tracks", log: log, type: .info)
        self.audioTrack = try? await peerConnection.addOlvidTracks()
        setAudioTrack(isEnabled: isAudioEnabled) // Usefull when a participant was added to a group call while we were muted
        assert(self.audioTrack != nil)
        
        os_log("☎️ Create Data Channel", log: log, type: .info)
        try await createDataChannel(for: peerConnection)
        assert(self.dataChannelWorker != nil)
        
        // We might already have a session description available. This typically happens when receiving an incoming call:
        // We created the called and saved the session description for later, i.e., for the time the local user accepts the incoming call,
        // Which is what led us here.
        
        if let remoteSessionDescription = self.remoteSessionDescription {
            os_log("☎️ We just created the peer connection and have a remote description available. We set it now.", log: log, type: .info)
            self.remoteSessionDescription = nil
            try await peerConnection.setRemoteDescription(remoteSessionDescription)
            self.readyToProcessPeerIceCandidates = true
        }
        
    }

    
    func close() async throws {
        guard let peerConnection = self.peerConnection else {
            os_log("☎️🛑 Execute signaling state closed completion handler: peer connection is nil", log: log, type: .info)
            return
        }
        guard connectionState != .closed else {
            os_log("☎️🛑 Execute signaling state closed completion handler: signaling state is already closed", log: log, type: .info)
            return
        }
        os_log("☎️🛑 Closing peer connection. State before closing: %{public}@", log: log, type: .info, connectionState.debugDescription)
        await peerConnection.close()
    }

    
    func setRemoteDescription(_ sessionDescription: RTCSessionDescription) async throws {
        os_log("☎️ Setting a session description of type %{public}@", log: log, type: .info, sessionDescription.type.debugDescription)
        guard let peerConnection = peerConnection else {
            throw Self.makeError(message: "No peer connection available")
        }
        if try countSdpMedia(sessionDescription: sessionDescription.sdp) != 2 {
            assertionFailure()
            throw Self.makeError(message: "Unexpected number of media lines in session description")
        }
        
        // Since we will set a description, we must wait until it is our turn to do so.
        
        await waitUntilItIsSafeToSetSomeDescription()
        
        // Now that it is our turn to potentially set a description, we must make sure no other task will interfere.
        // The mechanism allowing to do so requires to set the following Boolean to true now, and to false when we are done.
        
        aTaskIsCurrentlySettingSomeDescription = true
        defer { aTaskIsCurrentlySettingSomeDescription = false }

        // Since we are setting a remote description, we expect to be either in the stable or haveLocalOffer states.
        // We do not test this though, as the following call will throw if we are not in one of these states.
        
        os_log("☎️ Will call setRemoteDescription on the ObvPeerConnection", log: log, type: .info)
        try await peerConnection.setRemoteDescription(sessionDescription)
        self.readyToProcessPeerIceCandidates = true
    }


    /// When receiving an incoming call, we quickly create this peer connection holder, but we do not create the underlying peer connection.
    /// For this, we want to wait until the user explictely accepts (picks up) the incoming call.
    /// This method is called when the local user does so.
    /// It creates the peer connection. This will eventually trigger a call to
    /// ``func peerConnectionShouldNegotiate(_ peerConnection: ObvPeerConnection) async``
    /// where the local description (answer) will be created.
    func createPeerConnectionIfRequiredAfterAcceptingAnIncomingCall() async throws {
        assert(peerConnection == nil)
        assert(delegate != nil)
        try await createPeerConnectionIfRequired()
    }

    
    private func rollback() async throws {
        assert(aTaskIsCurrentlySettingSomeDescription, "This method must exclusively be called from a method (belonging to this actor) that sets this Boolean to true")
        guard let peerConnection = peerConnection else { assertionFailure(); return }
        os_log("☎️ Rollback", log: log, type: .info)
        try await peerConnection.setLocalDescription(RTCSessionDescription(type: .rollback, sdp: ""))
        assert(self.dataChannelWorker != nil)
    }

    
    func restartIce() async throws {
        
        guard let peerConnection = peerConnection else { assertionFailure(); return }
        guard let delegate = delegate else { assertionFailure(); return }

        // Since we might set a description, we must wait until it is our turn to do so.
        
        await waitUntilItIsSafeToSetSomeDescription()
        
        // Now that it is our turn to potentially set a description, we must make sure no other task will interfere.
        // The mechanism allowing to do so requires to set the following Boolean to true now, and to false when we are done.
        
        aTaskIsCurrentlySettingSomeDescription = true
        defer { aTaskIsCurrentlySettingSomeDescription = false }

        switch peerConnection.signalingState {
        case .haveLocalOffer:
            // Rollback to a stable set before creating the new restart offer
            try await rollback()
        case .haveRemoteOffer:
            // We received a remote offer.
            // If we are the offer sender, rollback and send a new offer, otherwise juste wait for the answer process to finish
            if await delegate.shouldISendTheOfferToCallParticipant() {
                try await rollback()
            } else {
                return
            }
        default:
            break
        }

        await peerConnection.restartIce()
    }


    func handleReceivedRestartSdp(sessionDescription: RTCSessionDescription, reconnectCounter: Int, peerReconnectCounterToOverride: Int) async throws {
        
        guard let peerConnection = peerConnection else { assertionFailure(); return }
        guard let delegate = delegate else { assertionFailure(); return }

        os_log("☎️ Received restart SDP with reconnect counter: %{public}@", log: log, type: .info, String(reconnectCounter))

        // Since we might set a description, we must wait until it is our turn to do so.
        
        await waitUntilItIsSafeToSetSomeDescription()
        
        // Now that it is our turn to potentially set a description, we must make sure no other task will interfere.
        // The mechanism allowing to do so requires to set the following Boolean to true now, and to false when we are done.
        
        aTaskIsCurrentlySettingSomeDescription = true
        defer { aTaskIsCurrentlySettingSomeDescription = false }

        switch sessionDescription.type {
            
        case .offer:
            
            // If we receive an offer with a counter smaller than another offer we previously received, we can ignore it.
            guard reconnectCounter >= reconnectAnswerCounter else {
                os_log("☎️ Received restart offer with counter too low %{public}@ vs. %{public}@", log: log, type: .info, String(reconnectCounter), String(reconnectAnswerCounter))
                return
            }
            
            switch peerConnection.signalingState {
            case .haveRemoteOffer:
                os_log("☎️ Received restart offer while already having one --> rollback", log: log, type: .info)
                // Rollback to a stable set before handling the new restart offer
                try await rollback()
                
            case .haveLocalOffer:
                // We already sent an offer.
                // If we are the offer sender, do nothing, otherwise rollback and process the new offer
                if await delegate.shouldISendTheOfferToCallParticipant() {
                    if peerReconnectCounterToOverride == reconnectOfferCounter {
                        os_log("☎️ Received restart offer while already having created an offer. It specifies to override my current offer --> rollback", log: log, type: .info)
                        try await rollback()
                    } else {
                        os_log("☎️ Received restart offer while already having created an offer. I am the offerer --> ignore this new offer", log: log, type: .info)
                        return
                    }
                } else {
                    os_log("☎️ Received restart offer while already having created an offer. I am not the offerer --> rollback", log: log, type: .info)
                    try await rollback()
                }
                
            default:
                break
            }

            reconnectAnswerCounter = reconnectCounter
            os_log("☎️ Setting remote description (1)", log: log, type: .info)
            try await peerConnection.setRemoteDescription(sessionDescription)

            await peerConnection.restartIce()

        case .answer:
            guard reconnectCounter == reconnectOfferCounter else {
                os_log("☎️ Received restart answer with bad counter %{public}@ vs. %{public}@", log: log, type: .info, String(reconnectCounter), String(reconnectOfferCounter))
                return
            }

            guard peerConnection.signalingState == .haveLocalOffer else {
                os_log("☎️ Received restart answer while not in the haveLocalOffer state --> ignore this restart answer", log: log, type: .info)
                return
            }

            os_log("☎️ Applying received restart answer", log: log, type: .info)
            os_log("☎️ Setting remote description (2)", log: log, type: .info)
            try await peerConnection.setRemoteDescription(sessionDescription)

        default:
            return
        }

    }
    

    private func resetGatheringState() {
        guard case .gatherOnce = gatheringPolicy else { assertionFailure(); return }
        iceCandidates.removeAll()
        iceGatheringCompletedWasCalled = false
    }

    
    private func createDataChannel(for peerConnection: ObvPeerConnection) async throws {
        assert(dataChannelWorker == nil)
        self.dataChannelWorker = try await DataChannelWorker(with: peerConnection)
        self.dataChannelWorker?.delegate = self
    }

    
    func addIceCandidate(iceCandidate: RTCIceCandidate) async throws {
        os_log("☎️❄️ addIceCandidate called", log: self.log, type: .info)
        guard gatheringPolicy == .gatherContinually else { assertionFailure(); return }
        if readyToProcessPeerIceCandidates {
            guard let peerConnection = peerConnection else { assertionFailure(); return }
            try await peerConnection.addIceCandidate(iceCandidate)
        } else {
            os_log("☎️❄️ Not ready to forward remote ICE candidates, add candidate to pending list (count %{public}@)", log: self.log, type: .info, String(pendingRemoteIceCandidates.count))
            pendingRemoteIceCandidates.append(iceCandidate)
        }
    }
    

    func removeIceCandidates(iceCandidates: [RTCIceCandidate]) async {
        os_log("☎️❄️ removeIceCandidates called", log: self.log, type: .info)
        if readyToProcessPeerIceCandidates {
            guard let peerConnection = peerConnection else { assertionFailure(); return }
            await peerConnection.removeIceCandidates(iceCandidates)
        } else {
            os_log("☎️❄️ Not ready to forward remote ICE candidates, remove candidates from pending list (count %{public}@)", log: self.log, type: .info, String(pendingRemoteIceCandidates.count))
            pendingRemoteIceCandidates.removeAll { iceCandidates.contains($0) }
        }
    }

    
    private func createLocalDescriptionIfAppropriateForCurrentSignalingState(for peerConnection: ObvPeerConnection) async throws -> RTCSessionDescription? {
        os_log("☎️ Calling Create Local Description if appropriate for the current signaling state", log: self.log, type: .info)
        assert(self.peerConnection == peerConnection)
        let rtcSessionDescription: RTCSessionDescription?
        switch peerConnection.signalingState {
        case .stable:
            os_log("☎️ We are in a stable state --> create offer", log: self.log, type: .info)
            reconnectOfferCounter += 1
            rtcSessionDescription = try await peerConnection.offer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        case .haveRemoteOffer:
            os_log("☎️ We are in a haveRemoteOffer state --> create answer", log: self.log, type: .info)
            rtcSessionDescription = try await peerConnection.answer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        case .haveLocalOffer, .haveLocalPrAnswer, .haveRemotePrAnswer, .closed:
            os_log("☎️ We are neither in a stable or a haveRemoteOffer state, we do not create any offer", log: self.log, type: .info)
            rtcSessionDescription = nil
        @unknown default:
            assertionFailure()
            rtcSessionDescription = nil
        }
        return rtcSessionDescription
    }

    
    private func drainRemoteIceCandidates() async {
        let log = self.log
        guard case .gatherContinually = gatheringPolicy else { return }
        guard readyToProcessPeerIceCandidates else { return }
        guard !pendingRemoteIceCandidates.isEmpty else { return }
        os_log("☎️❄️ Drain remote %{public}@ ICE candidate(s)", log: self.log, type: .info, String(pendingRemoteIceCandidates.count))
        for iceCandidate in pendingRemoteIceCandidates {
            do {
                try await addIceCandidate(iceCandidate: iceCandidate)
            } catch {
                os_log("☎️ Could not drain one of the ice candidates: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure() // Continue anyway
            }
        }
        pendingRemoteIceCandidates.removeAll()
    }

    
    private func iceGatheringCompleted() async throws {

        guard !iceGatheringCompletedWasCalled else { return }
        iceGatheringCompletedWasCalled = true

        os_log("☎️ ICE gathering is completed", log: log, type: .info)

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

    
    // MARK: - Implementing ObvPeerConnectionDelegate
    
    /// According to https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API/Perfect_negotiation,
    /// This is the best place to get a local description and send it using the signaling channel to the remote peer.
    func peerConnectionShouldNegotiate(_ peerConnection: ObvPeerConnection) async {
                
        os_log("☎️ Peer Connection should negociate was called", log: log, type: .info)
        assert(self.peerConnection == peerConnection)
        
        await waitUntilNoLongerCreatingPeerConnection()
        assert(!currentlyCreatingPeerConnection)

        // Since we might set a description, we must wait until it is our turn to do so.
        
        await waitUntilItIsSafeToSetSomeDescription()
        
        // Now that it is our turn to potentially set a description, we must make sure no other task will interfere.
        // The mechanism allowing to do so requires to set the following Boolean to true now, and to false when we are done.
        
        aTaskIsCurrentlySettingSomeDescription = true
        defer { aTaskIsCurrentlySettingSomeDescription = false }

        // Check that the current state is not closed
        
        guard connectionState != .closed else {
            os_log("☎️ Since the peer connection is in a closed state, we do not negotiate", log: log, type: .info)
            return
        }

        do {
            guard let sessionDescription = try await createLocalDescriptionIfAppropriateForCurrentSignalingState(for: peerConnection) else { return }
            guard connectionState != .closed else { return } // The connection was closed during the creation of the local description
            try await onCreateSuccess(sessionDescription: sessionDescription, for: peerConnection)
        } catch {
            guard connectionState != .closed else { return } // The connection was closed during the call to onCreateSuccess
            os_log("☎️🛑 Could not negotiate: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }
    
    
    private func waitUntilNoLongerCreatingPeerConnection() async {
        guard currentlyCreatingPeerConnection else { return }
        os_log("☎️ Since we currently creating the peer connection (e.g., adding tracks), we wait until the creation is done before negotiating", log: log, type: .info)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            guard currentlyCreatingPeerConnection else { continuation.resume(); return }
            assert(continuationToResumeWhenPeerConnectionIsCreated == nil)
            continuationToResumeWhenPeerConnectionIsCreated = continuation
        }
    }
    
    
    private func noLongerCreatingPeerConnection() {
        assert(!currentlyCreatingPeerConnection)
        guard let continuation = continuationToResumeWhenPeerConnectionIsCreated else { return }
        os_log("☎️ Since the peer connection is now properly created (with tracks and all), we can proceed with the negotiation", log: log, type: .info)
        continuationToResumeWhenPeerConnectionIsCreated = nil
        continuation.resume()
    }
    
    
    private func waitUntilItIsSafeToSetSomeDescription() async {
        guard aTaskIsCurrentlySettingSomeDescription else { return }
        os_log("☎️ Since we are currently negotiating, we must wait", log: log, type: .info)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            guard aTaskIsCurrentlySettingSomeDescription else { continuation.resume(); return }
            continuationsOfTaskWaitingUntilTheyCanSetSomeDescription.insert(continuation, at: 0) // first in, first out
        }
    }

    
    private func oneOfTheTaskCurrentlySettingSomeDescriptionIsDone() {
        assert(!aTaskIsCurrentlySettingSomeDescription)
        guard !continuationsOfTaskWaitingUntilTheyCanSetSomeDescription.isEmpty else { return }
        os_log("☎️ Since a task potentially setting a description is done, we can proceed with the next one", log: log, type: .info)
        guard let continuation = continuationsOfTaskWaitingUntilTheyCanSetSomeDescription.popLast() else { return }
        aTaskIsCurrentlySettingSomeDescription = true
        continuation.resume()
    }
        
    
    private func onCreateSuccess(sessionDescription: RTCSessionDescription, for peerConnection: ObvPeerConnection) async throws {
        os_log("☎️ onCreateSuccess", log: log, type: .info)
        assert(self.peerConnection == peerConnection)
        
        guard let delegate = delegate else {
            os_log("☎️ The delegate is not set on holder", log: log, type: .fault)
            assertionFailure()
            return
        }

        // If we are not in stable or in a "have remote offer" state, we shouldn't be creating an offer nor an anser.
        // In that case, we return immediately.
        // Moreover, because the state might have changed since we created the session description, we check whether this description
        // Is still appropriate for the current signaling state.
        guard (peerConnection.signalingState, sessionDescription.type) == (.stable, .offer) ||
                (peerConnection.signalingState, sessionDescription.type) == (.haveRemoteOffer, .answer) else {
            return
        }

        os_log("☎️ Filtering SDP...", log: log, type: .info)
        let filteredSessionDescription = try self.filterSdpDescriptionCodec(rtcSessionDescription: sessionDescription)
        os_log("☎️ Filtered SDP: %{public}@", log: log, type: .info, filteredSessionDescription.sdp)

        os_log("☎️ Setting the local description in onCreateSuccess", log: log, type: .info)
        try await peerConnection.setLocalDescription(filteredSessionDescription)

        switch gatheringPolicy {
        case .gatherOnce:
            resetGatheringState()
        case .gatherContinually:
            switch filteredSessionDescription.type {
            case .offer:
                await delegate.sendLocalDescription(sessionDescription: filteredSessionDescription, reconnectCounter: reconnectOfferCounter, peerReconnectCounterToOverride: reconnectAnswerCounter)
            case .answer:
                await delegate.sendLocalDescription(sessionDescription: filteredSessionDescription, reconnectCounter: reconnectAnswerCounter, peerReconnectCounterToOverride: -1)
            case .prAnswer, .rollback:
                assertionFailure()
            @unknown default:
                assertionFailure()
            }
        }
    }


    func peerConnection(_ peerConnection: ObvPeerConnection, didChange stateChanged: RTCSignalingState) async {
        os_log("☎️ RTCPeerConnection didChange RTCSignalingState: %{public}@", log: log, type: .info, stateChanged.debugDescription)
        assert(self.peerConnection == peerConnection)
        Task {
            if stateChanged == .stable && peerConnection.iceConnectionState == .connected {
                await delegate?.peerConnectionStateDidChange(newState: .connected)
            }
            if stateChanged == .closed {
                os_log("☎️🛑 Signaling state is closed", log: log, type: .info)
            }
        }
    }


    func peerConnection(_ peerConnection: ObvPeerConnection, didChange newState: RTCPeerConnectionState) async {
        os_log("☎️ RTCPeerConnection didChange RTCPeerConnectionState: %{public}@", log: log, type: .info, newState.debugDescription)
        assert(self.peerConnection == peerConnection)
        self.connectionState = newState
    }

    
    func peerConnection(_ peerConnection: ObvPeerConnection, didChange newState: RTCIceConnectionState) async {
        os_log("☎️ RTCPeerConnection didChange RTCIceConnectionState: %{public}@", log: log, type: .info, newState.debugDescription)
        assert(self.peerConnection == peerConnection)
        await delegate?.peerConnectionStateDidChange(newState: newState)
    }
    

    func peerConnection(_ peerConnection: ObvPeerConnection, didChange newState: RTCIceGatheringState) async {
        os_log("☎️❄️ Peer Connection Ice Gathering State changed to: %{public}@", log: log, type: .info, newState.debugDescription)
        assert(self.peerConnection == peerConnection)
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
                if iceCandidates.isEmpty {
                    os_log("☎️❄️ No ICE candidates found", log: log, type: .info)
                } else {
                    // We have all we need to send the local description to the caller.
                    os_log("☎️❄️ Calls completed ICE Gathering with %{public}@ candidates", log: self.log, type: .info, String(self.iceCandidates.count))
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
        os_log("☎️❄️ Peer Connection didGenerate RTCIceCandidate", log: log, type: .info)
        assert(self.peerConnection == peerConnection)
        switch gatheringPolicy {
        case .gatherOnce:
            iceCandidates.append(candidate)
            if iceCandidates.count == 1 { /// At least one candidate, we wait one second and hope that the other candidate will be added.
                let queue = DispatchQueue(label: "Sleeping queue", qos: .userInitiated)
                queue.asyncAfter(deadline: .now() + .seconds(2)) { [weak self] in
                    guard let _self = self else { return }
                    Task {
                        try? await _self.iceGatheringCompleted()
                    }
                }
            }
        case .gatherContinually:
            Task {
                try? await delegate?.sendNewIceCandidateMessage(candidate: candidate)
            }
        }
    }
    

    func peerConnection(_ peerConnection: ObvPeerConnection, didRemove candidates: [RTCIceCandidate]) async {
        os_log("☎️❄️ Peer Connection didRemove RTCIceCandidate", log: log, type: .info)
        assert(self.peerConnection == peerConnection)
        switch gatheringPolicy {
        case .gatherOnce:
            iceCandidates.removeAll { candidates.contains($0) }
        case .gatherContinually:
            Task {
                try? await delegate?.sendRemoveIceCandidatesMessages(candidates: candidates)
            }
        }
    }

    
    func peerConnection(_ peerConnection: ObvPeerConnection, didOpen dataChannel: RTCDataChannel) async {
        os_log("☎️ Peer Connection didOpen RTCDataChannel", log: log, type: .info)
        assert(self.peerConnection == peerConnection)
    }


    // MARK: CallDataChannelWorkerDelegate and related methods

    func dataChannel(didReceiveMessage message: WebRTCDataChannelMessageJSON) async {
        await delegate?.dataChannel(of: self, didReceiveMessage: message)
    }

    func dataChannel(didChangeState state: RTCDataChannelState) async {
        await delegate?.dataChannel(of: self, didChangeState: state)
    }

    func sendDataChannelMessage(_ message: WebRTCDataChannelMessageJSON) throws {
        Task {
            try await dataChannelWorker?.sendDataChannelMessage(message)
        }
    }


}



// MARK: - Filtering session descriptions

extension WebrtcPeerConnectionHolder {
    
    
    private func countSdpMedia(sessionDescription: String) throws -> Int {
        var counter = 0
        let mediaStart = try NSRegularExpression(pattern: "^m=", options: .anchorsMatchLines)
        let lines = sessionDescription.split(whereSeparator: { $0.isNewline }).map({String($0)})
        for line in lines {
            let isFirstLineOfAnotherMediaSection = mediaStart.numberOfMatches(in: line, options: [], range: NSRange(location: 0, length: line.count)) > 0
            if isFirstLineOfAnotherMediaSection {
                counter += 1
            }
        }
        return counter
    }
    

    private func filterSdpDescriptionCodec(rtcSessionDescription: RTCSessionDescription) throws -> RTCSessionDescription {

        let sessionDescription = rtcSessionDescription.sdp
        
        let mediaStartAudio = try NSRegularExpression(pattern: "^m=audio\\s+", options: .anchorsMatchLines)
        let mediaStart = try NSRegularExpression(pattern: "^m=", options: .anchorsMatchLines)
        let lines = sessionDescription.split(whereSeparator: { $0.isNewline }).map({String($0)})
        var audioSectionStarted = false
        var audioLines = [String]()
        var filteredLines = [String]()
        for line in lines {
            if audioSectionStarted {
                let isFirstLineOfAnotherMediaSection = mediaStart.numberOfMatches(in: line, options: [], range: NSRange(location: 0, length: line.count)) > 0
                if isFirstLineOfAnotherMediaSection {
                    audioSectionStarted = false
                    // The audio section has ended, we can process all the audio lines with gathered
                    let filteredAudioLines = try processAudioLines(audioLines)
                    filteredLines.append(contentsOf: filteredAudioLines)
                    filteredLines.append(line)
                } else {
                    audioLines.append(line)
                }
            } else {
                let isFirstLineOfAudioSection = mediaStartAudio.numberOfMatches(in: line, options: [], range: NSRange(location: 0, length: line.count)) > 0
                if isFirstLineOfAudioSection {
                    audioSectionStarted = true
                    audioLines.append(line)
                } else {
                    filteredLines.append(line)
                }
            }
        }
        if audioSectionStarted {
            // In case the audio section was the last section of the session description
            audioSectionStarted = false
            let filteredAudioLines = try processAudioLines(audioLines)
            filteredLines.append(contentsOf: filteredAudioLines)
        }
        let filteredSessionDescription = filteredLines.joined(separator: "\r\n").appending("\r\n")
        return RTCSessionDescription(type: rtcSessionDescription.type, sdp: filteredSessionDescription)
    }


    private func processAudioLines(_ audioLines: [String]) throws -> [String] {

        let rtpmapPattern = try NSRegularExpression(pattern: "^a=rtpmap:([0-9]+)\\s+([^\\s/]+)", options: .anchorsMatchLines)

        // First pass
        var formatsToKeep = Set<String>()
        var opusFormat: String?
        for line in audioLines {
            guard let result = rtpmapPattern.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.count)) else { continue }
            let formatRange = result.range(at: 1)
            let codecRange = result.range(at: 2)
            let format = (line as NSString).substring(with: formatRange)
            let codec = (line as NSString).substring(with: codecRange)
            guard Self.audioCodecs.contains(codec) else { continue }
            formatsToKeep.insert(format)
            if codec == "opus" {
                opusFormat = format
            }
        }

        assert(opusFormat != nil)

        // Second pass
        // 1. Rewrite the first line (only keep the formats to keep)
        var processedAudioLines = [String]()
        do {
            let firstLine = try NSRegularExpression(pattern: "^(m=\\S+\\s+\\S+\\s+\\S+)\\s+(([0-9]+\\s*)+)$", options: .anchorsMatchLines)
            guard let result = firstLine.firstMatch(in: audioLines[0], options: [], range: NSRange(location: 0, length: audioLines[0].count)) else { throw NSError() }
            let processedFirstLine = (audioLines[0] as NSString)
                .substring(with: result.range(at: 1))
                .appending(" ")
                .appending(
                    (audioLines[0] as NSString)
                        .substring(with: result.range(at: 2))
                        .split(whereSeparator: { $0.isWhitespace })
                        .map({String($0)})
                        .filter({ formatsToKeep.contains($0) })
                        .joined(separator: " "))
            processedAudioLines.append(processedFirstLine)
        }
        // 2. Filter subsequent lines
        let rtpmapOrOptionPattern = try NSRegularExpression(pattern: "^a=(rtpmap|fmtp|rtcp-fb):([0-9]+)\\s+", options: .anchorsMatchLines)

        for i in 1..<audioLines.count {
            let line = audioLines[i]
            guard let result = rtpmapOrOptionPattern.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.count)) else {
                processedAudioLines.append(line)
                continue
            }
            let lineTypeRange = result.range(at: 1)
            let lineType = (line as NSString).substring(with: lineTypeRange)
            let formatRange = result.range(at: 2)
            let format = (line as NSString).substring(with: formatRange)
            guard formatsToKeep.contains(format) else { continue }
            if let opusFormat = opusFormat, format == opusFormat, "ftmp" == lineType {
                let modifiedLine = line.appending(self.additionalOpusOptions)
                processedAudioLines.append(modifiedLine)
            } else {
                processedAudioLines.append(line)
            }
        }
        return processedAudioLines
    }

}


// MARK: - Audio control

extension WebrtcPeerConnectionHolder {

    func muteAudioTracks() {
        setAudioTrack(isEnabled: false)
    }

    func unmuteAudioTracks() {
        setAudioTrack(isEnabled: true)
    }

    private func setAudioTrack(isEnabled: Bool) {
        audioTrack?.isEnabled = isEnabled
        isAudioEnabled = isEnabled
    }

    var isAudioTrackMuted: Bool {
        return !isAudioEnabled
    }
}
