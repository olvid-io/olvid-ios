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
import OlvidUtils
import ObvEngine
import os.log
import ObvTypes
import WebRTC
import ObvCrypto


actor Call: GenericCall, ObvErrorMaker {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: Call.self))
    static let errorDomain = "Call"

    let uuid: UUID // Corresponds to the UUID for CallKit when using it
    let usesCallKit: Bool
    let direction: CallDirection

    let uuidForWebRTC: UUID
    let groupId: GroupIdentifierBasedOnObjectID?
    let ownedIdentity: ObvCryptoId
    /// Used for an outgoing call. If the owned identity making the call is allowed to do so, this is set to this owned identity. If she is not, this is set to some other owned identity on this device that is allowed to make calls.
    /// This makes it possible to make secure outgoing calls available to all profiles on this device as soon as one profile is allowed to make secure outgoing calls.
    let ownedIdentityForRequestingTurnCredentials: ObvCryptoId
    private var callParticipants = Set<HashableCallParticipant>()

    private var tokens: [NSObjectProtocol] = []

    weak var delegate: CallDelegate?
    
    private func setDelegate(to delegate: CallDelegate) {
        self.delegate = delegate
    }

    private var pendingIceCandidates = [OlvidUserId: [IceCandidateJSON]]()
    
    /// If we are a call participant, we might receive relayed WebRTC messages from the caller (in the case another participant is not "known" to us, i.e., we have not secure channel with her).
    /// We may receive those messages before we are aware of this participant. When this happens, we add those messages to `pendingReceivedRelayedMessages`.
    /// These messages will be used as soon as we are aware of this participant.
    private var pendingReceivedRelayedMessages = [ObvCryptoId: [(messageType: WebRTCMessageJSON.MessageType, messagePayload: String)]]()
    
    private let queueForPostingNotifications: DispatchQueue

    /// This Boolean is set to `true` when entering a method that could end up modifying the set of call participants.
    /// It is set back to `false` whenever this method is done.
    /// It allows to implement a mechanism preventing two distinct methods to interfere when both can end up modifying the set of call participants.
    private var aTaskIsCurrentlyModifyingCallParticipants = false {
        didSet {
            guard !aTaskIsCurrentlyModifyingCallParticipants else { return }
            oneOfTheTaskCurrentlyModifyingCallParticipantsIsDone()
        }
    }
    
    /// See the comment about ``aTaskIsCurrentlyModifyingCallParticipants``.
    private var continuationsOfTaskWaitingUntilTheyCanModifyCallParticipants = [CheckedContinuation<Void, Never>]()
    
    // Specific to incoming calls
    
    let messageIdentifierFromEngine: Data? // Non-nil for an incoming call, nil for an outgoing call
    private let messageUploadTimestampFromServer: Date? // Should not be nil for an incoming call
    let initialParticipantCount: Int
    let turnCredentialsReceivedFromCaller: TurnCredentials?
    private var userAnsweredIncomingCall = false
    private(set) var receivedOfferMessages: [OlvidUserId: (Date, NewParticipantOfferMessageJSON)] = [:]
    private var ringingMessageHasBeenSent = false // For incoming calls
    
    private var pushKitNotificationWasReceived = false

    // Specific to outgoing calls
    
    private var obvTurnCredentials: ObvTurnCredentials?

    // Common methods

    private func addParticipant(callParticipant: CallParticipantImpl, report: Bool) async {
        await callParticipant.setDelegate(to: self)
        assert(callParticipants.firstIndex(of: HashableCallParticipant(callParticipant)) == nil, "The participant already exists in the set, we should never happen since we have an anti-race mechanism")
        callParticipants.insert(HashableCallParticipant(callParticipant))
        if report {
            VoIPNotification.callHasBeenUpdated(callUUID: self.uuid, updateKind: .callParticipantChange)
                .postOnDispatchQueue(queueForPostingNotifications)
        }
        for iceCandidate in pendingIceCandidates[callParticipant.userId] ?? [] {
            try? await callParticipant.processIceCandidatesJSON(message: iceCandidate)
        }
        // Process the relayed messages from this participant that were received before we were aware of this participant.
        if let relayedMessagesToProcess = pendingReceivedRelayedMessages.removeValue(forKey: callParticipant.remoteCryptoId) {
            for relayedMsg in relayedMessagesToProcess {
                os_log("☎️ Processing a relayed message received while we were not aware of this call participant", log: log, type: .info)
                await receivedRelayedMessage(from: callParticipant.remoteCryptoId, messageType: relayedMsg.messageType, messagePayload: relayedMsg.messagePayload)
            }
        }
        pendingIceCandidates[callParticipant.userId] = nil
    }

    
    private func removeParticipant(callParticipant: CallParticipantImpl) async {
        callParticipants.remove(HashableCallParticipant(callParticipant))
        if callParticipants.isEmpty {
            await endCallAsAllOtherParticipantsLeft()
        }
        VoIPNotification.callHasBeenUpdated(callUUID: self.uuid, updateKind: .callParticipantChange)
            .postOnDispatchQueue(queueForPostingNotifications)
        
        // If we are the caller (i.e., if this is an outgoing call) and if the call is not over, we send an updated list of participants to the remaining participants
        
        if direction == .outgoing && !internalState.isFinalState {
            let otherParticipants = callParticipants.map({ $0.callParticipant })
            let message: WebRTCDataChannelMessageJSON
            do {
                message = try await UpdateParticipantsMessageJSON(callParticipants: otherParticipants).embedInWebRTCDataChannelMessageJSON()
            } catch {
                os_log("☎️ Could not send UpdateParticipantsMessageJSON: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
            for otherParticipant in otherParticipants {
                try? await otherParticipant.sendDataChannelMessage(message)
            }
        }

    }

    
    func getParticipant(remoteCryptoId: ObvCryptoId) -> CallParticipantImpl? {
        return callParticipants.first(where: { $0.remoteCryptoId == remoteCryptoId })?.callParticipant
    }
    
    func getCallParticipants() async -> [CallParticipant] {
        callParticipants.map({ $0.callParticipant })
    }
    
    func userDidAnsweredIncomingCall() async -> Bool {
        userAnsweredIncomingCall
    }
    
    func getStateDates() async -> [CallState: Date] {
        stateDate
    }

    // MARK: State management

    private var internalState: CallState = .initial
    private var stateDate = [CallState: Date]()

    static let acceptableTimeIntervalForStartCallMessages: TimeInterval = 30.0 // 30 seconds
    private static let ringingTimeoutInterval = 60 // 60 seconds

    private var currentAudioInput: (label: String, activate: () -> Void)?

    var state: CallState {
        get async {
            internalState
        }
    }
    

    private func setCallState(to newState: CallState) async {
        
        guard !internalState.isFinalState else { return }
        let previousState = internalState
        if previousState == .callInProgress && newState == .ringing { return }
        if previousState == newState { return }
        
        os_log("☎️ WebRTCCall will change state: %{public}@ --> %{public}@", log: log, type: .info, internalState.debugDescription, newState.debugDescription)
        
        internalState = newState
        
        // Play sounds
        
        switch self.direction {
        case .outgoing:
            if internalState == .ringing {
                await CallSounds.shared.play(sound: .ringing, category: nil)
            } else if internalState == .callInProgress && previousState != .callInProgress {
                await CallSounds.shared.play(sound: .connect, category: nil)
            } else if internalState.isFinalState && previousState == .callInProgress {
                await CallSounds.shared.play(sound: .disconnect, category: nil)
            } else {
                await CallSounds.shared.stopCurrentSound()
            }
        case .incoming:
            if internalState == .callInProgress && previousState != .callInProgress {
                await CallSounds.shared.play(sound: .connect, category: nil)
            } else if internalState.isFinalState && previousState == .callInProgress {
                await CallSounds.shared.play(sound: .disconnect, category: nil)
            } else {
                await CallSounds.shared.stopCurrentSound()
            }
        }
        
        if !stateDate.keys.contains(internalState) {
            stateDate[internalState] = Date()
        }
        
        VoIPNotification.callHasBeenUpdated(callUUID: self.uuid, updateKind: .state(newState: newState))
            .postOnDispatchQueue(queueForPostingNotifications)

        // Notify of the fact that the incoming call is initializing (this is used to show the call view and the call toggle view)
        
        if self.direction == .incoming && newState == .initializingCall {
            VoIPNotification.anIncomingCallShouldBeShownToUser(newIncomingCall: self)
                .postOnDispatchQueue(queueForPostingNotifications)
        }
        
        if internalState.isFinalState {

            // Close all connections
            
            let callParticipants = self.callParticipants.map({ $0.callParticipant })
            for participant in callParticipants {
                do {
                    try await participant.closeConnection()
                } catch {
                    os_log("Failed to close a connection with a participant while ending WebRTC call: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure() // Continue anyway
                }
            }

            // Notify our delegate
            
            await delegate?.callReachedFinalState(call: self)
        }
        
        if direction == .outgoing && internalState == .callInProgress {
            await delegate?.outgoingCallReachedReachedInProgressState(call: self)
        }
        
    }

    
    private func updateStateFromPeerStates() async {
        let callParticipants = self.callParticipants.map({ $0.callParticipant })
        for callParticipant in callParticipants {
            guard await callParticipant.getPeerState().isFinalState else { return }
        }
        // If we reach this point, all call participants are in a final state, we can end the call.
        await endCallAsAllOtherParticipantsLeft()
    }

    
    private init(direction: CallDirection, uuid: UUID, usesCallKit: Bool, uuidForWebRTC: UUID?, groupId: GroupIdentifierBasedOnObjectID?, ownedIdentity: ObvCryptoId, ownedIdentityForRequestingTurnCredentials: ObvCryptoId?, messageIdentifierFromEngine: Data?, messageUploadTimestampFromServer: Date?, initialParticipantCount: Int, turnCredentialsReceivedFromCaller: TurnCredentials?, obvTurnCredentials: ObvTurnCredentials?, queueForPostingNotifications: DispatchQueue) {
        
        self.uuid = uuid
        self.usesCallKit = usesCallKit
        self.direction = direction
        self.uuidForWebRTC = uuidForWebRTC ?? uuid
        self.groupId = groupId
        self.ownedIdentity = ownedIdentity
        self.ownedIdentityForRequestingTurnCredentials = ownedIdentityForRequestingTurnCredentials ?? ownedIdentity
        self.queueForPostingNotifications = queueForPostingNotifications

        // Specific to incoming calls
        
        self.messageIdentifierFromEngine = messageIdentifierFromEngine
        self.messageUploadTimestampFromServer = messageUploadTimestampFromServer
        self.initialParticipantCount = initialParticipantCount
        self.turnCredentialsReceivedFromCaller = turnCredentialsReceivedFromCaller

        // Specific to outgoing calls
        
        self.obvTurnCredentials = obvTurnCredentials

    }


    // MARK: Creating an incoming call

    static func createIncomingCall(uuid: UUID, startCallMessage: StartCallMessageJSON, contactId: OlvidUserId, uuidForWebRTC: UUID, messageIdentifierFromEngine: Data, messageUploadTimestampFromServer: Date, delegate: IncomingCallDelegate, useCallKit: Bool, queueForPostingNotifications: DispatchQueue) async -> Call {
        
        let callParticipant = await CallParticipantImpl.createCaller(startCallMessage: startCallMessage, contactId: contactId)

        var groupId: GroupIdentifierBasedOnObjectID?
        switch startCallMessage.groupIdentifier {
        case .none:
            groupId = nil
        case .groupV1(groupV1Identifier: let groupV1Identifier):
            ObvStack.shared.performBackgroundTaskAndWait { context in
                if let persistedGroup = try? PersistedContactGroup.getContactGroup(groupId: groupV1Identifier, ownedCryptoId: callParticipant.ownedIdentity, within: context) {
                    groupId = .groupV1(persistedGroup.typedObjectID)
                }
            }
        case .groupV2(groupV2Identifier: let groupV2Identifier):
            ObvStack.shared.performBackgroundTaskAndWait { context in
                if let group = try? PersistedGroupV2.get(ownIdentity: callParticipant.ownedIdentity, appGroupIdentifier: groupV2Identifier, within: context) {
                    groupId = .groupV2(group.typedObjectID)
                }
            }
        }
        
        let call = Call(direction: .incoming,
                        uuid: uuid,
                        usesCallKit: useCallKit,
                        uuidForWebRTC: uuidForWebRTC,
                        groupId: groupId,
                        ownedIdentity: callParticipant.ownedIdentity,
                        ownedIdentityForRequestingTurnCredentials: nil,
                        messageIdentifierFromEngine: messageIdentifierFromEngine,
                        messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                        initialParticipantCount: startCallMessage.participantCount,
                        turnCredentialsReceivedFromCaller: startCallMessage.turnCredentials,
                        obvTurnCredentials: nil,
                        queueForPostingNotifications: queueForPostingNotifications)
        
        await call.setDelegate(to: delegate)
        
        await call.addParticipant(callParticipant: callParticipant, report: false)
     
        await call.observeAudioInputHasBeenActivatedNotifications()
        
        return call

    }
    
    
    // MARK: Creating an outgoing call

    static func createOutgoingCall(contactIds: [OlvidUserId], ownedIdentityForRequestingTurnCredentials: ObvCryptoId, delegate: OutgoingCallDelegate, usesCallKit: Bool, groupId: GroupIdentifierBasedOnObjectID?, queueForPostingNotifications: DispatchQueue) async throws -> Call {

        var callParticipants = [CallParticipantImpl]()
        for contactId in contactIds {
            let participant = await Self.createRecipient(contactId: contactId)
            callParticipants.append(participant)
        }
        
        guard let participant = contactIds.first else {
            throw Self.makeError(message: "Cannot create an outgoing call with no participant")
        }
        
        let call = Call(direction: .outgoing,
                        uuid: UUID(),
                        usesCallKit: usesCallKit,
                        uuidForWebRTC: nil,
                        groupId: groupId,
                        ownedIdentity: participant.ownCryptoId,
                        ownedIdentityForRequestingTurnCredentials: ownedIdentityForRequestingTurnCredentials,
                        messageIdentifierFromEngine: nil,
                        messageUploadTimestampFromServer: nil,
                        initialParticipantCount: callParticipants.count,
                        turnCredentialsReceivedFromCaller: nil,
                        obvTurnCredentials: nil,
                        queueForPostingNotifications: queueForPostingNotifications)
        
        await call.setDelegate(to: delegate)

        for callParticipant in callParticipants {
            await call.addParticipant(callParticipant: callParticipant, report: false)
        }
        
        await call.observeAudioInputHasBeenActivatedNotifications()

        return call
        
    }

    
    // MARK: - For any kind of call
    
    
    private func observeAudioInputHasBeenActivatedNotifications() {
        self.tokens.append(ObvMessengerInternalNotification.observeAudioInputHasBeenActivated { label, activate in
            Task { [weak self] in await self?.processAudioInputHasBeenActivatedNotification(label: label, activate: activate) }
        })
    }

    
    func processAudioInputHasBeenActivatedNotification(label: String, activate: @escaping () -> Void) {
        guard isOutgoingCall else { return }
        guard currentAudioInput?.label != label else { return }
        /// Keep a trace of audio input during ringing state to restore it when the call become inProgress
        os_log("☎️🎵 Call stores %{public}@ as audio input", log: log, type: .info, label)
        currentAudioInput = (label: label, activate: activate)
    }

    
    var isMuted: Bool {
        get async {
            // We return true only if audio is disabled for everyone
            let callParticipants = self.callParticipants.map({ $0.callParticipant })
            for callParticipant in callParticipants {
                if await !callParticipant.isMuted {
                    return false
                }
            }
            return true
        }
    }
    
    
    /// Called from the Olvid UI when the user taps on the mute button
    func userRequestedToToggleAudio() async {
        do {
            if await self.isMuted {
                try await callManager.requestUnmuteCallAction(call: self)
            } else {
                try await callManager.requestMuteCallAction(call: self)
            }
        } catch {
            os_log("☎️ Failed to toggle audio: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }


    /// This method is *not* called from the UI but from the coordinator, as a response to our request made in
    /// ``func userRequestedToToggleAudio() async``
    func muteSelfForOtherParticipants() async {
        let callParticipants = self.callParticipants.map({ $0.callParticipant })
        for participant in callParticipants {
            guard await !participant.isMuted else { continue }
            await participant.mute()
        }
        VoIPNotification.callHasBeenUpdated(callUUID: self.uuid, updateKind: .mute)
            .postOnDispatchQueue(queueForPostingNotifications)
    }

    
    /// This method is *not* called from the UI but from the coordinator, as a response to our request made in
    /// ``func userRequestedToToggleAudio() async``
    func unmuteSelfForOtherParticipants() async {
        let callParticipants = self.callParticipants.map({ $0.callParticipant })
        for participant in callParticipants {
            guard await participant.isMuted else { continue }
            await participant.unmute()
        }
        VoIPNotification.callHasBeenUpdated(callUUID: self.uuid, updateKind: .mute)
            .postOnDispatchQueue(queueForPostingNotifications)
    }
    
    
    func callParticipantDidHangUp(participantId: OlvidUserId) async throws {
        guard let participant = getParticipant(remoteCryptoId: participantId.remoteCryptoId) else { return }
        try await participant.setPeerState(to: .hangedUp)
        let newParticipantState = await participant.getPeerState()
        assert(newParticipantState.isFinalState)
        await updateStateFromPeerStates()
    }
    
    // - MARK: Restarting a call

    /// Called when a network connection status changed
    func restartIceIfAppropriate() async throws {
        guard internalState == .callInProgress else { return }
        let log = self.log
        let callParticipants = self.callParticipants.map({ $0.callParticipant })
        for callParticipant in callParticipants {
            do {
                try await callParticipant.restartIceIfAppropriate()
            } catch {
                os_log("☎️ Could not restart ICE: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
        }
    }

    
    func handleReconnectCallMessage(callParticipant: CallParticipantImpl, _ reconnectCallMessage: ReconnectCallMessageJSON) async throws {
        let sessionDescription = RTCSessionDescription(type: reconnectCallMessage.sessionDescriptionType, sdp: reconnectCallMessage.sessionDescription)
        try await callParticipant.handleReceivedRestartSdp(
            sessionDescription: sessionDescription,
            reconnectCounter: reconnectCallMessage.reconnectCounter ?? 0,
            peerReconnectCounterToOverride: reconnectCallMessage.peerReconnectCounterToOverride ?? 0)
    }

    
    private var callManager: ObvCallManager { usesCallKit ? CXCallManager() : NCXCallManager() }

}


// MARK: - Implementing CallParticipantDelegate

extension Call: CallParticipantDelegate {

    nonisolated var isOutgoingCall: Bool { self.direction == .outgoing }

    func participantWasUpdated(callParticipant: CallParticipantImpl, updateKind: CallParticipantUpdateKind) async {

        guard callParticipants.contains(HashableCallParticipant(callParticipant)) else { return }
        VoIPNotification.callParticipantHasBeenUpdated(callParticipant: callParticipant, updateKind: updateKind)
            .postOnDispatchQueue(queueForPostingNotifications)

        switch updateKind {
        case .state(newState: let newState):
            switch newState {
            case .initial:
                break
            case .startCallMessageSent:
                break
            case .ringing:
                guard self.direction == .outgoing else { return }
                guard [CallState.initializingCall, .gettingTurnCredentials, .initial].contains(internalState) else { return }
                await setCallState(to: .ringing)
            case .busy:
                await removeParticipant(callParticipant: callParticipant)
            case .connectingToPeer:
                guard internalState == .userAnsweredIncomingCall else { return }
                await setCallState(to: .initializingCall)
            case .connected:
                guard internalState != .callInProgress else { return }
                await setCallState(to: .callInProgress)
                if let currentAudioInput = currentAudioInput {
                    os_log("☎️🎵 Connected call restores %{public}@ as audio input ", log: log, type: .info, currentAudioInput.label)
                    currentAudioInput.activate()
                }
            case .reconnecting, .callRejected, .hangedUp, .kicked, .failed:
                break
            }
        case .contactID:
            break
        case .contactMuted:
            break
        }
    }

    
    nonisolated func connectionIsChecking(for callParticipant: CallParticipant) {
        Task { await CallSounds.shared.prepareFeedback() }
    }

    
    func connectionIsConnected(for callParticipant: CallParticipant, oldParticipantState: PeerState) async {
        
        let callParticipants = self.callParticipants.map({ $0.callParticipant })

        do {
            if self.direction == .outgoing && oldParticipantState != .connected && oldParticipantState != .reconnecting {
                let message = try await UpdateParticipantsMessageJSON(callParticipants: callParticipants).embedInWebRTCDataChannelMessageJSON()
                let callParticipantsToNotify = self.callParticipants.filter({ $0.callParticipant.uuid != callParticipant.uuid }).map({ $0.callParticipant })
                for callParticipant in callParticipantsToNotify {
                    try await callParticipant.sendDataChannelMessage(message)
                }
            }
        } catch {
            os_log("We failed to notify the other participants about the new participants list: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
            // Continue anywait
        }
        
        // If the current state is not already "callInProgress", it means that the first participant
        // Just joined to call. We want to change the state to "callInProgress" (which will play the
        // Appropriate sounds, etc.).
        
        guard internalState != .callInProgress else { return }
        await setCallState(to: .callInProgress)
    }
    

    func connectionWasClosed(for callParticipant: CallParticipantImpl) async {
        await removeParticipant(callParticipant: callParticipant)
        await updateStateFromPeerStates()
    }

    func dataChannelIsOpened(for callParticipant: CallParticipant) async {
        guard self.direction == .outgoing else { return }
        guard callParticipant.role == .recipient else { assertionFailure(); return }
        let callParticipants = self.callParticipants.map({ $0.callParticipant })
        try? await callParticipant.sendUpdateParticipantsMessageJSON(callParticipants: callParticipants)
    }

    nonisolated func shouldISendTheOfferToCallParticipant(cryptoId: ObvCryptoId) -> Bool {
        /// REMARK it should be the same as io.olvid.messenger.webrtc.WebrtcCallService#shouldISendTheOfferToCallParticipant in java
        return ownedIdentity > cryptoId
    }

    
    func updateParticipants(with allCallParticipants: [ContactBytesAndNameJSON]) async throws {
        
        os_log("☎️ Entering updateParticipant(newCallParticipants: [ContactBytesAndNameJSON])", log: log, type: .info)
        os_log("☎️ The latest list of call participants contains %d participant(s)", log: log, type: .info, allCallParticipants.count)
        os_log("☎️ Before processing this list, we consider there are %d participant(s) in this call", log: log, type: .info, callParticipants.count)
        
        // In case of large group calls, we can encounter race conditions. We prevent that by waiting until it is safe to process the new participants list

        await waitUntilItIsSafeToModifyParticipants()
        
        // Now that it is our turn to potentially modify the participants set, we must make sure no other task will interfere.
        // The mechanism allowing to do so requires to set the following Boolean to true now, and to false when we are done.
        
        aTaskIsCurrentlyModifyingCallParticipants = true
        defer { aTaskIsCurrentlyModifyingCallParticipants = false }

        // We can proceed
        
        guard direction == .incoming else {
            assertionFailure()
            throw Self.makeError(message: "self is not an incoming call")
        }
        guard let turnCredentials = self.turnCredentialsReceivedFromCaller else {
            assertionFailure()
            throw Self.makeError(message: "No turn credentials found")
        }
        
        let callIsMuted = await self.isMuted

        // Remove our own identity from the list of call participants.
        
        let allCallParticipants = allCallParticipants.filter({ $0.byteContactIdentity != ownedIdentity.getIdentity() })

        // Determine the CryptoIds of the local list of participants and of the reveived version of the list
        
        let currentIdsOfParticipants = Set(callParticipants.compactMap({ $0.callParticipant.userId }))
        let updatedIdsOfParticipants = Set(allCallParticipants.compactMap({ try? getOlvidUserIdFor(contactInfos: $0) }))
        
        // Determine the participants to add to the local list, and those that should be removed
        
        let idsOfParticipantsToAdd = updatedIdsOfParticipants.subtracting(currentIdsOfParticipants)
        let idsOfParticipantsToRemove = currentIdsOfParticipants.subtracting(updatedIdsOfParticipants)

        // Perform the necessary steps to add the participants

        os_log("☎️ We have %d participant(s) to add", log: log, type: .info, idsOfParticipantsToAdd.count)
        
        for userId in idsOfParticipantsToAdd {
            
            let gatheringPolicy = allCallParticipants
                .first(where: { $0.byteContactIdentity == userId.remoteCryptoId.getIdentity() })
                .map({ $0.gatheringPolicy ?? .gatherOnce }) ?? .gatherOnce
                        
            let callParticipant = await CallParticipantImpl.createRecipientForIncomingCall(contactId: userId, gatheringPolicy: gatheringPolicy)
            await addParticipant(callParticipant: callParticipant, report: true)
            await delegate?.newParticipantWasAdded(call: self, callParticipant: callParticipant)

            if shouldISendTheOfferToCallParticipant(cryptoId: userId.remoteCryptoId) {
                os_log("☎️ Will set credentials for offer to a call participant", log: log, type: .info)
                try await callParticipant.setTurnCredentialsAndCreateUnderlyingPeerConnection(turnCredentials: turnCredentials)
            } else {
                os_log("☎️ No need to send offer to the call participant", log: log, type: .info)
                /// check if we already received the offer the CallParticipant is supposed to send us
                if let (date, newParticipantOfferMessage) = self.receivedOfferMessages.removeValue(forKey: userId) {
                    try await delegate?.processNewParticipantOfferMessageJSON(newParticipantOfferMessage,
                                                                              uuidForWebRTC: uuidForWebRTC,
                                                                              contact: userId,
                                                                              messageUploadTimestampFromServer: date)
                }
            }

        }

        // If we were muted, we must make sure we stay muted for all participant, including the new ones
        
        if callIsMuted {
            await muteSelfForOtherParticipants()
        }

        // Perform the necessary steps to remove the participants.
        // Note that we know the caller is among the participants and we do not want to remove her here.

        os_log("☎️ We have %d participant(s) to remove (unless one if the caller)", log: log, type: .info, idsOfParticipantsToRemove.count)

        for userId in idsOfParticipantsToRemove {
            guard let participant = getParticipant(remoteCryptoId: userId.remoteCryptoId) else { assertionFailure(); continue }
            guard participant.role != .caller else { continue }
            try await participant.closeConnection()
            await removeParticipant(callParticipant: participant)
        }

    }
    
    
    /// This method allows to make sure we are not risking race conditions when updating the list of participants.
    private func waitUntilItIsSafeToModifyParticipants() async {
        guard aTaskIsCurrentlyModifyingCallParticipants else { return }
        os_log("☎️ Since we are already currently modifying call participants, we must wait", log: log, type: .info)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            guard aTaskIsCurrentlyModifyingCallParticipants else { continuation.resume(); return }
            continuationsOfTaskWaitingUntilTheyCanModifyCallParticipants.insert(continuation, at: 0) // first in, first out
        }
    }
    
    
    private func oneOfTheTaskCurrentlyModifyingCallParticipantsIsDone() {
        assert(!aTaskIsCurrentlyModifyingCallParticipants)
        guard !continuationsOfTaskWaitingUntilTheyCanModifyCallParticipants.isEmpty else { return }
        os_log("☎️ Since a task potentially modifying the set of call participants is done, we can proceed with the next one", log: log, type: .info)
        guard let continuation = continuationsOfTaskWaitingUntilTheyCanModifyCallParticipants.popLast() else { return }
        aTaskIsCurrentlyModifyingCallParticipants = true
        continuation.resume()
    }


    // MARK: - Post office service

    func relay(from: ObvCryptoId, to: ObvCryptoId, messageType: WebRTCMessageJSON.MessageType, messagePayload: String) async {

        guard messageType.isAllowedToBeRelayed else { assertionFailure(); return }

        guard let participant = getParticipant(remoteCryptoId: to) else { return }
        let message: WebRTCDataChannelMessageJSON
        do {
            message = try RelayedMessageJSON(from: from.getIdentity(), relayedMessageType: messageType.rawValue, serializedMessagePayload: messagePayload).embedInWebRTCDataChannelMessageJSON()
        } catch {
            os_log("☎️ Could not send UpdateParticipantsMessageJSON: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }
        do {
            try await participant.sendDataChannelMessage(message)
        } catch {
            os_log("☎️ Could not send data channel message: %{public}@", log: log, type: .fault, error.localizedDescription)
            return
        }
    }
    
    
    func receivedRelayedMessage(from: ObvCryptoId, messageType: WebRTCMessageJSON.MessageType, messagePayload: String) async {
        os_log("☎️ Call to receivedRelayedMessage", log: log, type: .info)
        guard let callParticipant = callParticipants.first(where: { $0.remoteCryptoId == from })?.callParticipant else {
            os_log("☎️ Could not find the call participant in receivedRelayedMessage. We store the relayed message for later", log: log, type: .info)
            if var previous = pendingReceivedRelayedMessages[from] {
                previous.append((messageType, messagePayload))
                pendingReceivedRelayedMessages[from] = previous
            } else {
                pendingReceivedRelayedMessages[from] = [(messageType, messagePayload)]
            }
            return
        }
        let contactId = callParticipant.userId
        await delegate?.processReceivedWebRTCMessage(messageType: messageType,
                                                     serializedMessagePayload: messagePayload,
                                                     callIdentifier: uuidForWebRTC,
                                                     contact: contactId,
                                                     messageUploadTimestampFromServer: Date(),
                                                     messageIdentifierFromEngine: nil)
    }
    

    private func sendLocalUserHangedUpMessageToAllParticipants() async {
        let hangedUpMessage = HangedUpMessageJSON()
        for participant in self.callParticipants {
            do {
                try await sendWebRTCMessage(to: participant.callParticipant, innerMessage: hangedUpMessage, forStartingCall: false)
            } catch {
                os_log("Failed to send a HangedUpMessageJSON to a participant: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure() // Continue anyway
            }
        }
    }

    
    private func sendRejectIncomingCallToCaller() async {
        assert(direction == .incoming)
        guard let caller = self.callerCallParticipant else {
            os_log("Could not find caller", log: log, type: .fault)
            assertionFailure()
            return
        }
        let rejectedMessage = RejectCallMessageJSON()
        do {
            try await sendWebRTCMessage(to: caller, innerMessage: rejectedMessage, forStartingCall: false)
        } catch {
            os_log("Failed to send a RejectCallMessageJSON to the caller: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure() // Continue anyway
        }
    }
    
    
    private func sendBusyMessageToCaller() async {
        assert(direction == .incoming)
        guard let caller = self.callerCallParticipant else {
            os_log("Could not find caller", log: log, type: .fault)
            assertionFailure()
            return
        }
        let rejectedMessage = BusyMessageJSON()
        do {
            try await sendWebRTCMessage(to: caller, innerMessage: rejectedMessage, forStartingCall: false)
        } catch {
            os_log("Failed to send a BusyMessageJSON to the caller: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure() // Continue anyway
        }
    }
    
    
    func sendRingingMessageToCaller() async {
        assert(direction == .incoming)
        guard !ringingMessageHasBeenSent else { return }
        ringingMessageHasBeenSent = true
        guard let caller = self.callerCallParticipant else {
            os_log("Could not find caller", log: log, type: .fault)
            assertionFailure()
            return
        }
        let rejectedMessage = RingingMessageJSON()
        do {
            try await sendWebRTCMessage(to: caller, innerMessage: rejectedMessage, forStartingCall: false)
        } catch {
            os_log("Failed to send a RejectCallMessageJSON to the caller: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure() // Continue anyway
        }
        await scheduleRingingIncomingCallTimeout()
    }
    
    
    func sendWebRTCMessage(to: CallParticipant, innerMessage: WebRTCInnerMessageJSON, forStartingCall: Bool) async throws {
        let message = try innerMessage.embedInWebRTCMessageJSON(callIdentifier: uuidForWebRTC)
        if case .hangedUp = message.messageType {
            // Also send message on the data channel, if the caller is gone
            do {
                let hangedUpDataChannel = try HangedUpDataChannelMessageJSON().embedInWebRTCDataChannelMessageJSON()
                try await to.sendDataChannelMessage(hangedUpDataChannel)
            } catch {
                os_log("☎️ Could not send HangedUpDataChannelMessageJSON: %{public}@", log: log, type: .fault, error.localizedDescription)
                // Continue anyway
            }
        }
        switch to.userId {
        case .known(contactObjectID: let contactObjectID, ownCryptoId: _, remoteCryptoId: _, displayName: _):
            os_log("☎️ Posting a newWebRTCMessageToSend", log: log, type: .info)
            ObvMessengerInternalNotification.newWebRTCMessageToSend(webrtcMessage: message, contactID: contactObjectID, forStartingCall: forStartingCall)
                .postOnDispatchQueue(queueForPostingNotifications)
        case .unknown(ownCryptoId: _, remoteCryptoId: let remoteCryptoId, displayName: _):
            guard message.messageType.isAllowedToBeRelayed else { assertionFailure(); return }
            guard self.direction == .incoming else { assertionFailure(); return }
            guard let caller = self.callerCallParticipant else { return }
            let toContactIdentity = remoteCryptoId.getIdentity()

            do {
                let dataChannelMessage = try RelayMessageJSON(to: toContactIdentity, relayedMessageType: message.messageType.rawValue, serializedMessagePayload: message.serializedMessagePayload).embedInWebRTCDataChannelMessageJSON()
                try await caller.sendDataChannelMessage(dataChannelMessage)
            } catch {
                os_log("☎️ Could not send RelayMessageJSON: %{public}@", log: log, type: .fault, error.localizedDescription)
                return
            }
        }
    }
    
    
    func sendStartCallMessage(to callParticipant: CallParticipant, sessionDescription: RTCSessionDescription, turnCredentials: TurnCredentials) async throws {

        guard let gatheringPolicy = await callParticipant.gatheringPolicy else {
            assertionFailure()
            throw Self.makeError(message: "The gathering policy is not specified, which is unexpected at this point")
        }
        
        guard let turnServers = turnCredentials.turnServers else {
            assertionFailure()
            throw Self.makeError(message: "The turn servers are not set, which is unexpected at this point")
        }

        var filteredGroupId: GroupIdentifier?
        switch groupId {
        case .groupV1(let objectID):
            let participantIdentity = callParticipant.remoteCryptoId
            ObvStack.shared.performBackgroundTaskAndWait { context in
                guard let contactGroup = try? PersistedContactGroup.get(objectID: objectID.objectID, within: context) else {
                    os_log("Could not find contactGroup", log: log, type: .fault)
                    return
                }
                let groupMembers = Set(contactGroup.contactIdentities.map { $0.cryptoId })
                if groupMembers.contains(participantIdentity), let groupV1Identifier = try? contactGroup.getGroupId() {
                    filteredGroupId = .groupV1(groupV1Identifier: groupV1Identifier)
                }
            }
        case .groupV2(let objectID):
            let participantIdentity = callParticipant.remoteCryptoId
            ObvStack.shared.performBackgroundTaskAndWait { context in
                guard let group = try? PersistedGroupV2.get(objectID: objectID, within: context) else {
                    os_log("Could not find PersistedGroupV2", log: log, type: .fault)
                    return
                }
                let groupMembers = Set(group.otherMembers.compactMap({ $0.cryptoId }))
                if groupMembers.contains(participantIdentity) {
                    filteredGroupId = .groupV2(groupV2Identifier: group.groupIdentifier)
                }
            }
        case .none:
            filteredGroupId = nil
        }
    
        let message = try StartCallMessageJSON(
            sessionDescriptionType: RTCSessionDescription.string(for: sessionDescription.type),
            sessionDescription: sessionDescription.sdp,
            turnUserName: turnCredentials.turnUserName,
            turnPassword: turnCredentials.turnPassword,
            turnServers: turnServers,
            participantCount: callParticipants.count,
            groupIdentifier: filteredGroupId,
            gatheringPolicy: gatheringPolicy)
        
        try await sendWebRTCMessage(to: callParticipant, innerMessage: message, forStartingCall: true)
        
    }
    
    
    func sendAnswerCallMessage(to callParticipant: CallParticipant, sessionDescription: RTCSessionDescription) async throws {
        
        let message: WebRTCInnerMessageJSON
        let messageDescripton = callParticipant.role == .caller ? "AnswerIncomingCall" : "NewParticipantAnswerMessage"
        do {
            if callParticipant.role == .caller {
                message = try AnswerCallJSON(sessionDescriptionType: RTCSessionDescription.string(for: sessionDescription.type), sessionDescription: sessionDescription.sdp)
            } else {
                message = try NewParticipantAnswerMessageJSON(sessionDescriptionType: RTCSessionDescription.string(for: sessionDescription.type), sessionDescription: sessionDescription.sdp)
            }
        } catch {
            os_log("Could not create and send %{public}@: %{public}@", log: log, type: .fault, messageDescripton, error.localizedDescription)
            assertionFailure()
            throw error
        }
        try await sendWebRTCMessage(to: callParticipant, innerMessage: message, forStartingCall: false)
    }

    
    func sendNewParticipantOfferMessage(to callParticipant: CallParticipant, sessionDescription: RTCSessionDescription) async throws {
        let message = try await NewParticipantOfferMessageJSON(
            sessionDescriptionType: RTCSessionDescription.string(for: sessionDescription.type),
            sessionDescription: sessionDescription.sdp,
            gatheringPolicy: callParticipant.gatheringPolicy ?? .gatherContinually)
        try await sendWebRTCMessage(to: callParticipant, innerMessage: message, forStartingCall: false)
    }
    
    
    func sendNewParticipantAnswerMessage(to callParticipant: CallParticipant, sessionDescription: RTCSessionDescription) async throws {
        let message = try NewParticipantAnswerMessageJSON(
            sessionDescriptionType: RTCSessionDescription.string(for: sessionDescription.type),
            sessionDescription: sessionDescription.sdp)
        try await sendWebRTCMessage(to: callParticipant, innerMessage: message, forStartingCall: false)
    }
    
    
    func sendReconnectCallMessage(to callParticipant: CallParticipant, sessionDescription: RTCSessionDescription, reconnectCounter: Int, peerReconnectCounterToOverride: Int) async throws {
        let message = try ReconnectCallMessageJSON(
            sessionDescriptionType: RTCSessionDescription.string(for: sessionDescription.type),
            sessionDescription: sessionDescription.sdp,
            reconnectCounter: reconnectCounter,
            peerReconnectCounterToOverride: peerReconnectCounterToOverride)
        try await sendWebRTCMessage(to: callParticipant, innerMessage: message, forStartingCall: false)
    }
    
    
    func sendNewIceCandidateMessage(to callParticipant: CallParticipant, iceCandidate: RTCIceCandidate) async throws {
        let message = IceCandidateJSON(sdp: iceCandidate.sdp, sdpMLineIndex: iceCandidate.sdpMLineIndex, sdpMid: iceCandidate.sdpMid)
        try await sendWebRTCMessage(to: callParticipant, innerMessage: message, forStartingCall: false)
    }
    
    
    func sendRemoveIceCandidatesMessages(to callParticipant: CallParticipant, candidates: [RTCIceCandidate]) async throws {
        let message = RemoveIceCandidatesMessageJSON(candidates: candidates.map({ IceCandidateJSON(sdp: $0.sdp, sdpMLineIndex: $0.sdpMLineIndex, sdpMid: $0.sdpMid) }))
        try await sendWebRTCMessage(to: callParticipant, innerMessage: message, forStartingCall: false)
    }

    
    func processIceCandidatesJSON(iceCandidate: IceCandidateJSON, participantId: OlvidUserId) async throws {
        
        if let callParticipant = callParticipants.first(where: { $0.callParticipant.userId == participantId })?.callParticipant {
            try await callParticipant.processIceCandidatesJSON(message: iceCandidate)
        } else {
            if var previousCandidates = pendingIceCandidates[participantId] {
                previousCandidates.append(iceCandidate)
                pendingIceCandidates[participantId] = previousCandidates
            } else {
                pendingIceCandidates[participantId] = [iceCandidate]
            }
        }

    }
    
    
    func removeIceCandidatesJSON(removeIceCandidatesJSON: RemoveIceCandidatesMessageJSON, participantId: OlvidUserId) async throws {
        if let callParticipant = callParticipants.first(where: { $0.callParticipant.userId == participantId })?.callParticipant {
            await callParticipant.processRemoveIceCandidatesMessageJSON(message: removeIceCandidatesJSON)
        } else {
            if var candidates = pendingIceCandidates[participantId] {
                candidates.removeAll(where: { removeIceCandidatesJSON.candidates.contains($0) })
                pendingIceCandidates[participantId] = candidates
            }
        }
    }
    
}


// MARK: - Ending a call

extension Call {
    
    /// This is the method call by the Olvid UI when a the user taps on the hangup button.
    /// It simply creates an end call action that it passed to the system. Eventually, the
    /// ``func provider(perform action: ObvEndCallAction) async throws``
    /// delegate method of the call coordinator will be called after dismissing the CallKit UI (when using it).
    /// This delegate method will call us back so that we can properly end this WebRTC call.
    nonisolated func userRequestedToEndCall() {
        Task {
            do {
                try await callManager.requestEndCallAction(call: self)
            } catch {
                os_log("Failed to request an end call action: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
        }
    }
    
    
    /// When the user requests to end the call, the
    /// ``func userRequestedToEndCall()``
    /// the call coordinator
    /// ``func provider(perform action: ObvEndCallAction) async throws``
    /// delegate is called. After fullfilling the action, it calls this method.
    /// We can not properly end the WebRTC call.
    func userRequestedToEndCallWasFulfilled() async {
        await endWebRTCCall(reason: .localUserRequest)
    }
    
    
    func endCallAsInitiationNotSupported() async {
        assert(direction == .outgoing)
        await endWebRTCCall(reason: .callInitiationNotSupported)
    }

    
    func endCallAsLocalUserGotKicked() async {
        assert(direction == .incoming)
        await endWebRTCCall(reason: .kicked)
    }
    
    
    func endCallAsPermissionWasDeniedByServer() async {
        assert(direction == .outgoing)
        await endWebRTCCall(reason: .permissionDeniedByServer)
    }
    
    
    func endCallAsReportingAnIncomingCallFailed(error: ObvErrorCodeIncomingCallError) async {
        assert(direction == .incoming)
        await endWebRTCCall(reason: .reportIncomingCallFailed(error: error))
    }
    
    
    func endCallAsAllOtherParticipantsLeft() async {
        await endWebRTCCall(reason: .allOtherParticipantsLeft)
    }
    
    
    func endCallAsOutgoingCallInitializationFailed() async {
        assert(direction == .outgoing)
        await endWebRTCCall(reason: .outgoingCallInitializationFailed)
    }
    
    
    func endCallBecauseOfMissingRecordPermission() async {
        await endWebRTCCall(reason: .missingRecordPermission)
    }
    
    
    private func endCallBecauseOfTimeout() async {
        await endWebRTCCall(reason: .callTimedOut)
    }
    
    /// This method is eventually called when ending a call, either because the local user requested to end the call, or the remote user hanged up,
    /// Or because some error occured, etc. It perfoms final important steps before settting the call into an appropriate final state.
    /// This is the only method that actually sets the call state to a final state.
    private func endWebRTCCall(reason: EndCallReason) async {
        
        guard !internalState.isFinalState else { return }
        
        let callParticipants = self.callParticipants.map({ $0.callParticipant })

        // Potentially send a hangup/reject call message to the other participants or the to the caller
        
        switch reason {

        case .callTimedOut:
            await sendLocalUserHangedUpMessageToAllParticipants()
            
        case .localUserRequest:
            switch direction {
            case .outgoing:
                await sendLocalUserHangedUpMessageToAllParticipants()
            case .incoming:
                switch internalState {
                case .initial, .ringing, .initializingCall:
                    await sendRejectIncomingCallToCaller()
                case .userAnsweredIncomingCall, .callInProgress:
                    await sendLocalUserHangedUpMessageToAllParticipants()
                case .gettingTurnCredentials, .hangedUp, .kicked, .callRejected, .permissionDeniedByServer, .unanswered, .callInitiationNotSupported, .failed:
                    assertionFailure()
                    await sendRejectIncomingCallToCaller()
                }
            }
            
        case .callInitiationNotSupported:
            assert(direction == .outgoing) // No need to send reject/hangup message

        case .kicked:
            assert(direction == .incoming) // No need to send reject/hangup message

        case .permissionDeniedByServer:
            assert(direction == .outgoing) // No need to send reject/hangup message

        case .allOtherParticipantsLeft:
            break // No need to send reject/hangup message

        case .reportIncomingCallFailed(error: let error):
            assert(direction == .incoming)
            switch error {
            case .unknown, .unentitled, .callUUIDAlreadyExists, .filteredByDoNotDisturb, .filteredByBlockList:
                await sendRejectIncomingCallToCaller()
            case .maximumCallGroupsReached:
                await sendBusyMessageToCaller()
            }

        case .outgoingCallInitializationFailed:
            assert(direction == .outgoing) // No need to send reject/hangup message

        case .missingRecordPermission:
            await sendRejectIncomingCallToCaller()
            // No need to send reject/hangup message

        }
                
        // In the end, we might have to report to our delegate

        var callReport: CallReport?

        // Set the call in an appropriate final state and perform final steps

        switch reason {

        case .callTimedOut:
            await setCallState(to: .unanswered)
            switch direction {
            case .incoming:
                callReport = .missedIncomingCall(caller: callerCallParticipant?.info,
                                                 participantCount: initialParticipantCount)
            case .outgoing:
                callReport = .unansweredOutgoingCall(with: callParticipants.map({ $0.info }))
            }
            await delegate?.callOutOfBoundEnded(call: self, reason: .unanswered)
            
        case .localUserRequest:
            switch direction {
            case .outgoing:
                await setCallState(to: .hangedUp)
            case .incoming:
                switch internalState {
                case .initial, .ringing, .initializingCall:
                    await setCallState(to: .callRejected)
                    if let caller = callerCallParticipant?.info {
                        callReport = .rejectedIncomingCall(caller: caller, participantCount: initialParticipantCount)
                    }
                case .userAnsweredIncomingCall, .callInProgress:
                    await setCallState(to: .hangedUp)
                case .gettingTurnCredentials, .hangedUp, .kicked, .callRejected, .permissionDeniedByServer, .unanswered, .callInitiationNotSupported, .failed:
                    assertionFailure()
                    await setCallState(to: .callRejected)
                    if let caller = callerCallParticipant?.info {
                        callReport = .rejectedIncomingCall(caller: caller, participantCount: initialParticipantCount)
                    }
                }
            }
            
        case .callInitiationNotSupported:
            assert(direction == .outgoing)
            await setCallState(to: .callInitiationNotSupported)
            await delegate?.callOutOfBoundEnded(call: self, reason: .failed)
            callReport = .uncompletedOutgoingCall(with: callParticipants.map({ $0.info }))

        case .kicked:
            assert(direction == .incoming)
            await setCallState(to: .kicked)
            await delegate?.callOutOfBoundEnded(call: self, reason: .remoteEnded)

        case .permissionDeniedByServer:
            assert(direction == .outgoing)
            await setCallState(to: .permissionDeniedByServer)
            await delegate?.callOutOfBoundEnded(call: self, reason: .failed)
            callReport = .uncompletedOutgoingCall(with: callParticipants.map({ $0.info }))

        case .allOtherParticipantsLeft:
            if internalState == .initial {
                await setCallState(to: .unanswered)
                await delegate?.callOutOfBoundEnded(call: self, reason: .unanswered)
            } else {
                await setCallState(to: .hangedUp)
                await delegate?.callOutOfBoundEnded(call: self, reason: .remoteEnded)
            }
            
        case .reportIncomingCallFailed(error: let error):
            assert(direction == .incoming)
            switch error {
            case .unknown, .unentitled, .callUUIDAlreadyExists:
                await setCallState(to: .failed)
                if let caller = callerCallParticipant?.info {
                    callReport = .rejectedIncomingCall(caller: caller, participantCount: initialParticipantCount)
                }
            case .filteredByDoNotDisturb, .filteredByBlockList:
                await setCallState(to: .unanswered)
                if let caller = callerCallParticipant?.info {
                    callReport = .filteredIncomingCall(caller: caller, participantCount: initialParticipantCount)
                }
                if let caller = callerCallParticipant?.info {
                    callReport = .rejectedIncomingCall(caller: caller, participantCount: initialParticipantCount)
                }

            case .maximumCallGroupsReached:
                await setCallState(to: .unanswered)
            }

        case .outgoingCallInitializationFailed:
            assert(direction == .outgoing)
            await setCallState(to: .failed)
            callReport = .uncompletedOutgoingCall(with: callParticipants.map({ $0.info }))
                

        case .missingRecordPermission:
            await setCallState(to: .failed)
            await delegate?.callOutOfBoundEnded(call: self, reason: .failed)
            if direction == .incoming, let caller = callerCallParticipant?.info {
                callReport = .rejectedIncomingCallBecauseOfDeniedRecordPermission(caller: caller, participantCount: initialParticipantCount)
            }

        }
        
        assert(internalState.isFinalState)
        
        // If we have a call report, transmit it to our delegate
        
        if let callReport = callReport {
            if let delegate = delegate {
                type(of: delegate).report(call: self, report: callReport)
            } else {
                assertionFailure()
            }
        }
        
    }
    
    
    enum EndCallReason {
        case callTimedOut
        case localUserRequest
        case callInitiationNotSupported
        case kicked // incoming call only
        case permissionDeniedByServer // outgoing call only
        case allOtherParticipantsLeft
        case reportIncomingCallFailed(error: ObvErrorCodeIncomingCallError)
        case outgoingCallInitializationFailed
        case missingRecordPermission
    }
}


// MARK: - Incoming calls

extension Call {
    
    var callerCallParticipant: CallParticipant? {
        guard direction == .incoming else { assertionFailure(); return nil }
        return callParticipants.first(where: { $0.callParticipant.role == .caller })?.callParticipant
    }
    
    
    func addPendingOffer(_ receivedOfferMessage: (Date, NewParticipantOfferMessageJSON), from userId: OlvidUserId) {
        assert(receivedOfferMessages[userId] == nil)
        receivedOfferMessages[userId] = receivedOfferMessage
    }
    
        
    func isReady() -> Bool {
        assert(direction == .incoming)
        let pushKitIsEitherDisabledOrReady = !ObvMessengerSettings.VoIP.isCallKitEnabled || pushKitNotificationWasReceived
        return pushKitIsEitherDisabledOrReady
    }

    
    /// This method is called after when the local user answers an incoming call
    func answerWebRTCCall() async throws {
        assert(direction == .incoming)
        userAnsweredIncomingCall = true
        await setCallState(to: .userAnsweredIncomingCall)
        try await answerIfRequestedAndIfPossible()
    }


    private func answerIfRequestedAndIfPossible() async throws {
        assert(direction == .incoming)
        guard let caller = callerCallParticipant else { return }
        guard userAnsweredIncomingCall else { return }
        try await caller.localUserAcceptedIncomingCallFromThisCallParticipant()
    }

    
    /// Called when the user taps on the ansert button on the Olvid UI
    func userRequestedToAnswerCall() async {
        guard direction == .incoming else {
            os_log("Can only answer an incoming call", log: log, type: .fault)
            assertionFailure()
            return
        }
        if internalState == .initial || internalState == .ringing {
            do {
                try await callManager.requestAnswerCallAction(incomingCall: self)
            } catch {
                os_log("Failed to answer incoming call: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
        } else {
            os_log("To answer an incoming call, we must be either in the initial or ringing state. But we are in the %{public}@ state", log: log, type: .fault, internalState.debugDescription)
            assertionFailure()
        }
    }

    

    
    /// When receiving an incoming call, we heventully arrive in the ringing state. We do not want the phone to ring forever. We thus schedule a timeout using this method.
    private func scheduleRingingIncomingCallTimeout() async {
        let log = self.log
        guard direction == .incoming else { assertionFailure(); return }
        os_log("☎️ Scheduling a ringing timeout for this incoming call", log: log, type: .info)
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(Call.ringingTimeoutInterval)) {
            Task { [weak self] in await self?.ringingTimerForIncomingCallFired() }
        }
    }
    
    
    /// This method is *always* called after the `ringingTimeoutInterval`. For this reason, we *do* check whether it is appropriate to end the call
    private func ringingTimerForIncomingCallFired() async {
        guard direction == .incoming else { assertionFailure(); return }
        guard internalState == .initial else {
            os_log("☎️ We prevent the ringing timer from firing since we are not in a ringing state anymore", log: log, type: .info)
            return
        }
        os_log("☎️ The incoming call did ring for too long, we timeout it now", log: log, type: .info)
        await endCallBecauseOfTimeout()
    }

}


// MARK: - Outgoing calls

extension Call {

    var outgoingCallDelegate: OutgoingCallDelegate? {
        assert(direction == .outgoing)
        return delegate as? OutgoingCallDelegate
    }

    
    var turnCredentialsForRecipient: TurnCredentials? {
        assert(direction == .outgoing)
        return obvTurnCredentials?.turnCredentialsForRecipient
    }

    
    var turnCredentialsForCaller: TurnCredentials? {
        assert(direction == .outgoing)
        return obvTurnCredentials?.turnCredentialsForCaller
    }

    
    private static func createRecipient(contactId: OlvidUserId) async -> CallParticipantImpl {
        var contactInfo: ContactInfo?
        if let contactObjectID = contactId.contactObjectID {
            contactInfo = CallHelper.getContactInfo(contactObjectID)
        }
        return await CallParticipantImpl.createRecipientForOutgoingCall(contactId: contactId, gatheringPolicy: contactInfo?.gatheringPolicy ?? .gatherOnce)
    }

    
    // MARK: Starting an outgoing call

    func startCall() async throws {
        assert(direction == .outgoing)
        guard internalState == .initial else {
            os_log("☎️ Trying to start this call although it is not initial", log: log, type: .fault)
            assertionFailure()
            throw Self.makeError(message: "Trying to start this call although it is not initial")
        }
        await setCallState(to: .gettingTurnCredentials)
        assert(outgoingCallDelegate != nil)
        await outgoingCallDelegate?.turnCredentialsRequiredByOutgoingCall(outgoingCallUuidForWebRTC: uuidForWebRTC, forOwnedIdentity: ownedIdentityForRequestingTurnCredentials)
    }

    
    func setTurnCredentials(_ obvTurnCredentials: ObvTurnCredentials) async {
        assert(direction == .outgoing)
        let log = self.log
        guard self.obvTurnCredentials == nil else { assertionFailure(); return }
        self.obvTurnCredentials = obvTurnCredentials

        let callParticipants = self.callParticipants.map({ $0.callParticipant })
        
        for callParticipant in callParticipants {
            do {
                try await callParticipant.setTurnCredentialsAndCreateUnderlyingPeerConnection(turnCredentials: obvTurnCredentials.turnCredentialsForRecipient)
            } catch {
                os_log("☎️ We failed to set the turn credentials for one of the call participants: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure() // Continue anyway
            }
            usleep(300_000) // 300 ms, dirty trick, required to prevent a deadlock of the WebRTC library
        }
        await setCallState(to: .initializingCall)
    }

    
    func processAnswerCallJSON(callParticipant: CallParticipantImpl, _ answerCallMessage: AnswerCallJSON) async throws {
        assert(direction == .outgoing)
        let sessionDescription = RTCSessionDescription(type: answerCallMessage.sessionDescriptionType, sdp: answerCallMessage.sessionDescription)
        try await callParticipant.setRemoteDescription(sessionDescription: sessionDescription)
    }

    
    /// This method gets called when the local user (as the caller) wants to add more participants in an ongoing outgoing call.
    func processUserWantsToAddParticipants(contactIds: [OlvidUserId]) async throws {
        
        assert(direction == .outgoing)

        guard let turnCredentialsForRecipient = self.turnCredentialsForRecipient else {
            throw Self.makeError(message: "No turn credentials for recipient")
        }
        
        guard !contactIds.isEmpty else { return }

        let callIsMuted = await self.isMuted

        let contactIdsToAdd = contactIds
            .filter({ $0.ownCryptoId == ownedIdentity })
            .filter({ getParticipant(remoteCryptoId: $0.remoteCryptoId) == nil }) // Remove contacts that are already in the call
        
        var callParticipantsToAdd = [CallParticipantImpl]()
        for contactId in contactIdsToAdd {
            let participant = await Self.createRecipient(contactId: contactId)
            callParticipantsToAdd.append(participant)
        }
        
        guard !callParticipantsToAdd.isEmpty else { return }

        let log = self.log
        
        for newCallParticipant in callParticipantsToAdd {
            os_log("☎️ Adding a new participant", log: log, type: .info)
            await addParticipant(callParticipant: newCallParticipant, report: true)
            try? await newCallParticipant.setTurnCredentialsAndCreateUnderlyingPeerConnection(turnCredentials: turnCredentialsForRecipient)
            if callIsMuted {
                await newCallParticipant.mute()
            }
        }

    }
    
    
    /// This method is called by the coordinator when receiving the notification that the caller wants to kick a participant of the call
    func processUserWantsToKickParticipant(callParticipant: CallParticipant) async throws {
        
        assert(direction == .outgoing)

        guard let participant = callParticipants.first(where: { $0.remoteCryptoId == callParticipant.remoteCryptoId })?.callParticipant else { return }
        
        guard participant.role != .caller else { assertionFailure(); return }

        try await participant.setPeerState(to: .kicked)

        // Close the Connection
        
        do {
            try await participant.closeConnection()
        } catch {
            os_log("☎️ Could not close connection with kicked participant: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
            // Continue anyway
        }

        // Send kick to the kicked participant
        
        let kickMessage = KickMessageJSON()
        do {
            try await sendWebRTCMessage(to: participant, innerMessage: kickMessage, forStartingCall: false)
        } catch {
            os_log("☎️ Could not send KickMessageJSON to kicked contact: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
            // Continue anyway
        }

    }
    

    func initializeCall(contactIdentifier: String, handleValue: String) async throws {
        assert(direction == .outgoing)
        try await callManager.requestStartCallAction(call: self, contactIdentifier: contactIdentifier, handleValue: handleValue)
    }

}


extension Call {
    
    private func getOlvidUserIdFor(contactInfos: ContactBytesAndNameJSON) throws -> OlvidUserId {
        let remoteCryptoId = try ObvCryptoId(identity: contactInfos.byteContactIdentity)
        var contactId: OlvidUserId!
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            do {
                if let identity = try PersistedObvContactIdentity.get(contactCryptoId: remoteCryptoId, ownedIdentityCryptoId: ownedIdentity, whereOneToOneStatusIs: .any, within: context), let ownedIdentity = identity.ownedIdentity, !identity.devices.isEmpty {
                    contactId = .known(contactObjectID: identity.typedObjectID, ownCryptoId: ownedIdentity.cryptoId, remoteCryptoId: identity.cryptoId, displayName: identity.fullDisplayName)
                }
            } catch {
                assertionFailure() // Continue anyway
            }
        }
        if let contactId = contactId {
            return contactId
        } else {
            return .unknown(ownCryptoId: ownedIdentity, remoteCryptoId: remoteCryptoId, displayName: contactInfos.displayName)
        }
    }
    
}



private struct HashableCallParticipant: Hashable {

    let remoteCryptoId: ObvCryptoId
    let callParticipant: CallParticipantImpl
    
    init(_ callParticipant: CallParticipantImpl) {
        self.remoteCryptoId = callParticipant.remoteCryptoId
        self.callParticipant = callParticipant
    }
    
    static func == (lhs: HashableCallParticipant, rhs: HashableCallParticipant) -> Bool {
        lhs.remoteCryptoId == rhs.remoteCryptoId
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(remoteCryptoId)
    }
    
}
