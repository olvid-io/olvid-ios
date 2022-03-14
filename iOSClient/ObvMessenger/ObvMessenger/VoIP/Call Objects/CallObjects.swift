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
import CoreData
import os.log
import ObvEngine
import WebRTC
import CallKit
import ObvTypes

fileprivate extension Call {
    
    func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: "Call", code: 0, userInfo: userInfo)
    }

}

extension Call {
    var callManager: ObvCallManager { usesCallKit ? CXCallManager() : NCXCallManager() }

    func endCall(completion: ((ObvErrorCodeRequestTransactionError?) -> Void)? = nil) {
        guard !endCallActionWasRequested else { return }
        endCallActionWasRequested = true
        callManager.requestEndCallAction(call: self, completion: completion)
    }
    func mute(completion: ((ObvErrorCodeRequestTransactionError?) -> Void)? = nil) {
        callManager.requestMuteCallAction(call: self, completion: completion)
    }
    func unmute(completion: ((ObvErrorCodeRequestTransactionError?) -> Void)? = nil) {
        callManager.requestUnmuteCallAction(call: self, completion: completion)
    }
}
extension IncomingCall {
    func answerCall(completion: ((ObvErrorCodeRequestTransactionError?) -> Void)? = nil) { callManager.requestAnswerCallAction(call: self, completion: completion) }
}
extension OutgoingCall {
    func startCall(contactIdentifier: String, handleValue: String,
                   completion: ((ObvErrorCodeRequestTransactionError?) -> Void)? = nil) {
        callManager.requestStartCallAction(call: self, contactIdentifier: contactIdentifier, handleValue: handleValue, completion: completion)
    }
}

// MARK: - WebRTCCallDelegate

protocol WebRTCCallDelegate: AnyObject {
    func processReceivedWebRTCMessage(messageType: WebRTCMessageJSON.MessageType, serializedMessagePayload: String, callIdentifier: UUID, contact: ParticipantId, messageUploadTimestampFromServer: Date, messageIdentifierFromEngine: Data?)
    func processNewParticipantOfferMessageJSON(_ newParticipantOffer: NewParticipantOfferMessageJSON, uuidForWebRTC: UUID, contact: ParticipantId, messageUploadTimestampFromServer: Date)
    func report(call: Call, report: CallReport)
    func newParticipantWasAdded(call: Call, callParticipant: CallParticipant)
}

protocol IncomingWebRTCCallDelegate: WebRTCCallDelegate {
    func answerCallCompleted(callUUID: UUID, result: Result<Void, Error>)
}

protocol OutgoingWebRTCCallDelegate: WebRTCCallDelegate {
    func turnCredentialsRequiredByOutgoingCall(outgoingCallUuidForWebRTC: UUID, forOwnedIdentity ownedIdentityCryptoId: ObvCryptoId)
}

class WebRTCCall: Call {

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: WebRTCCall.self))

    let uuid = UUID()

    /// For incomings: The UUID to use internally, for webrtc messages. It is `nil` until the incoming call message is decrypted.
    var uuidForWebRTC: UUID?
    var usesCallKit: Bool
    var groupId: (groupUid: UID, groupOwner: ObvCryptoId)?
    var ownedIdentity: ObvCryptoId?
    private var tokens: [NSObjectProtocol] = []

    weak var delegate_: WebRTCCallDelegate?

    private(set) var callParticipants: [CallParticipant] = []

    func addParticipant(callParticipant: CallParticipant, report: Bool) {
        CallHelper.checkQueue() // OK
        callParticipant.delegate = self
        callParticipants += [callParticipant]
        if report {
            ObvMessengerInternalNotification.callHasBeenUpdated(call: self, updateKind: .callParticipantChange).postOnDispatchQueue()
        }
    }

    func removeParticipant(callParticipant: CallParticipant) {
        CallHelper.checkQueue() // OK
        callParticipants.removeAll { $0.contactIdentity == callParticipant.contactIdentity }
        ObvMessengerInternalNotification.callHasBeenUpdated(call: self, updateKind: .callParticipantChange).postOnDispatchQueue()
    }

    func getParticipant(contact: ParticipantId) -> CallParticipant? {
        CallHelper.checkQueue() // OK
        switch contact {
        case .persisted(contactID: let contactID):
            return callParticipants.first { $0.contactIdentificationStatus?.contactID == contactID }
        case .cryptoId(cryptoId: let cryptoId):
            return callParticipants.first { $0.contactIdentity == cryptoId }
        }
    }


    // MARK: State management

    private(set) var state: CallState = .initial
    private(set) var stateDate = [CallState: Date]()
    private var notificationTokens = [NSObjectProtocol]()

    static var callTimeout: TimeInterval = 60.0 /// seconds
    static var callConnectionTimeout: TimeInterval = 10.0 /// seconds
    private var timeoutTimer: Timer?
    var endCallActionWasRequested: Bool = false

    private var currentAudioInput: (label: String, activate: () -> Void)?

    private let sounds = CallSounds.shared

    fileprivate func setCallState(to newState: CallState) {
        CallHelper.checkQueue() // OK
        guard !state.isFinalState else { return }
        let previousState = state
        if previousState == .callInProgress && newState == .ringing { return }
        os_log("☎️ WebRTCCall will change state: %{public}@ --> %{public}@", log: log, type: .info, state.debugDescription, newState.debugDescription)
        state = newState
        if [.ringing, .gettingTurnCredentials, .initializingCall].contains(newState) {
            self.scheduleCallTimeout()
        }

        if self is OutgoingCall {
            if state == .ringing {
                CallSounds.shared.play(sound: .ringing)
            } else if state == .callInProgress && previousState != .callInProgress {
                CallSounds.shared.play(sound: .connect)
            } else if state.isFinalState && previousState == .callInProgress {
                CallSounds.shared.play(sound: .disconnect)
            } else {
                CallSounds.shared.stopCurrentSound()
            }
        } else if self is IncomingCall {
            if state == .callInProgress && previousState != .callInProgress {
                CallSounds.shared.play(sound: .connect)
            } else if state.isFinalState && previousState == .callInProgress {
                CallSounds.shared.play(sound: .disconnect)
            } else {
                CallSounds.shared.stopCurrentSound()
            }
        }
        if !stateDate.keys.contains(state) {
            stateDate[state] = Date()
        }
        ObvMessengerInternalNotification.callHasBeenUpdated(call: self, updateKind: .state(newState: newState))
            .postOnDispatchQueue()
    }

    func updateStateFromPeerStates() {
        CallHelper.checkQueue() // OK
        let allPeersAreInFinalState = callParticipants.allSatisfy { $0.state.isFinalState }

        if allPeersAreInFinalState {
            endCall()
        }
    }

    func invalidateCallTimeout() {
        CallHelper.checkQueue() // OK
        if let timer = timeoutTimer {
            os_log("☎️ Invalidate Call Timeout Timer", log: log, type: .info)
            timer.invalidate()
            self.timeoutTimer = nil
        }
    }

    func scheduleCallTimeout() {
        CallHelper.checkQueue() // OK
        invalidateCallTimeout()
        let log = self.log
        os_log("☎️ Schedule Call Timeout Participant Timer", log: log, type: .info)
        self.timeoutTimer = Timer.scheduledTimer(withTimeInterval: WebRTCCall.callTimeout, repeats: false) { _ in
            OperationQueue.main.addOperation {
                os_log("☎️ The Call timer is ending the call right now", log: log, type: .error)
                guard self.state != .callInProgress else {
                    os_log("☎️ We prevent the timer from firing since the call is in progress. We should not have gotten to this point.", log: log, type: .error)
                    assertionFailure()
                    return
                }
                self.setUnanswered()
                self.endCall()
                if let incomingCall = self as? IncomingCall {
                    self.delegate_?.report(call: self, report: .missedIncomingCall(caller: incomingCall.callerCallParticipant?.info, participantCount: incomingCall.initialParticipantCount))
                } else if self is OutgoingCall {
                    self.delegate_?.report(call: self, report: .unansweredOutgoingCall(with: self.callParticipants.map({ $0.info })))
                }
            }
        }
    }

    fileprivate init(callParticipants: [CallParticipant], usesCallKit: Bool, uuidForWebRTC: UUID?, delegate: WebRTCCallDelegate, ownedIdentity: ObvCryptoId?, groupId: (groupUid: UID, groupOwner: ObvCryptoId)?) {
        CallHelper.checkQueue() // OK
        self.usesCallKit = usesCallKit
        self.uuidForWebRTC = uuidForWebRTC ?? uuid
        self.delegate_ = delegate
        self.ownedIdentity = ownedIdentity
        self.groupId = groupId
        for callParticipant in callParticipants {
            addParticipant(callParticipant: callParticipant, report: false)
        }
        self.tokens.append(ObvMessengerInternalNotification.observeAudioInputHasBeenActivated(queue: OperationQueue.main) { label, activate in
            self.processAudioInputHasBeenActivatedNotification(label: label, activate: activate)
        })
    }

    func processAudioInputHasBeenActivatedNotification(label: String, activate: @escaping () -> Void) {
        CallHelper.checkQueue() // OK
        guard isOutgoingCall else { return }
        guard currentAudioInput?.label != label else { return }
        /// Keep a trace of audio input during ringing state to restore it when the call become inProgress
        os_log("☎️🎵 Call stores %{public}@ as audio input", log: log, type: .info, label)
        currentAudioInput = (label: label, activate: activate)
    }

    var isMuted: Bool {
        CallHelper.checkQueue() // OK
                                // We return true only if audio is disabled for everyone
        return callParticipants.allSatisfy({ $0.isMuted })
    }

    func mute() {
        CallHelper.checkQueue() // OK
        for participant in self.callParticipants {
            guard !participant.isMuted else { continue }
            participant.mute()
        }
        ObvMessengerInternalNotification.callHasBeenUpdated(call: self, updateKind: .mute)
            .postOnDispatchQueue()
    }

    func unmute() {
        CallHelper.checkQueue() // OK
        for participant in self.callParticipants {
            guard participant.isMuted else { continue }
            participant.unmute()
        }
        ObvMessengerInternalNotification.callHasBeenUpdated(call: self, updateKind: .mute)
            .postOnDispatchQueue()
    }

    func setKicked() {
        CallHelper.checkQueue() // OK
        setCallState(to: .kicked)
    }

    func setUnanswered() {
        CallHelper.checkQueue() // OK
        setCallState(to: .unanswered)
    }

    // MARK: Restarting a call

    func createRestartOffer() {
        CallHelper.checkQueue() // OK

        guard self.uuidForWebRTC != nil else { return }
        guard state == .callInProgress else { return }

        for callParticipant in self.callParticipants {
            guard [.connected, .connectingToPeer, .reconnecting].contains(callParticipant.state) else { return }
            callParticipant.createRestartOffer()
        }
    }

    func handleReconnectCallMessage(callParticipant: CallParticipant, _ reconnectCallMessage: ReconnectCallMessageJSON) {
        CallHelper.checkQueue() // OK
        callParticipant.handleReceivedRestartSdp(
            sessionDescriptionType: reconnectCallMessage.sessionDescriptionType,
            sessionDescription: reconnectCallMessage.sessionDescription,
            reconnectCounter: reconnectCallMessage.reconnectCounter ?? 0,
            peerReconnectCounterToOverride: reconnectCallMessage.peerReconnectCounterToOverride ?? 0)
    }

    func endWebRTCCallByHangingUp(completion: @escaping () -> Void) {
        CallHelper.checkQueue() // OK
        endWebRTCCall(finalState: .hangedUp, completion: completion)
    }

    func endWebRTCCallByRejectingCall(completion: @escaping () -> Void) {
        CallHelper.checkQueue() // OK
        endWebRTCCall(finalState: .callRejected, completion: completion)
    }

    private func endWebRTCCall(finalState: CallState, completion: @escaping () -> Void) {
        CallHelper.checkQueue() // OK
        for callParticipant in callParticipants {
            callParticipant.closeConnection()
        }
        completion()
        self.setCallState(to: finalState)
    }

}

extension WebRTCCall: CallParticipantDelegate {

    var isOutgoingCall: Bool { self is OutgoingCall }

    func participantWasUpdated(callParticipant: CallParticipant, updateKind: CallParticipantUpdateKind) {
        CallHelper.checkQueue() // OK

        guard callParticipants.contains(where: { $0.uuid == callParticipant.uuid }) else { return }
        ObvMessengerInternalNotification.callParticipantHasBeenUpdated(callParticipant: callParticipant, updateKind: updateKind).postOnDispatchQueue()

        switch updateKind {
        case .state(newState: let newState):
            switch newState {
            case .initial:
                break
            case .startCallMessageSent:
                break
            case .ringing:
                guard self is OutgoingCall else { return }
                guard state == .initializingCall else { return }
                setCallState(to: .ringing)
            case .busy:
                removeParticipant(callParticipant: callParticipant)
            case .connectingToPeer:
                guard state == .userAnsweredIncomingCall else { return }
                setCallState(to: .initializingCall)
            case .connected:
                invalidateCallTimeout()
                guard state != .callInProgress else { return }
                setCallState(to: .callInProgress)
                if let currentAudioInput = currentAudioInput {
                    os_log("☎️🎵 Connected call restores %{public}@ as audio input ", log: log, type: .info, currentAudioInput.label)
                    currentAudioInput.activate()
                }
            case .reconnecting:
                break
            case .callRejected:
                break
            case .hangedUp:
                break
            case .kicked:
                break
            case .timeout:
                break
            }
        case .contactID:
            break
        case .contactMuted:
            break
        }
    }

    func connectionIsChecking(for callParticipant: CallParticipant) {
        CallSounds.shared.prepareFeedback()
    }

    func connectionIsConnected(for callParticipant: CallParticipant) {
        CallHelper.checkQueue() // OK
        guard state != .callInProgress else { return }
        self.invalidateCallTimeout()
        setCallState(to: .callInProgress)
    }

    func connectionWasClosed(for callParticipant: CallParticipant) {
        CallHelper.checkQueue() // OK
        removeParticipant(callParticipant: callParticipant)
        updateStateFromPeerStates()
    }

    func dataChannelIsOpened(for callParticipant: CallParticipant) {
        CallHelper.checkQueue() // OK
        guard self is OutgoingCall else { return }
        guard callParticipant.role == .recipient else { assertionFailure(); return }
        callParticipant.sendUpdateParticipantsMessageJSON(callParticipants: self.callParticipants)
    }

    func shouldISendTheOfferToCallParticipant(contactIdentity: ObvCryptoId) -> Bool {
        /// REMARK it should be the same as io.olvid.messenger.webrtc.WebrtcCallService#shouldISendTheOfferToCallParticipant in java
        guard let ownedIdentity = self.ownedIdentity else { assertionFailure(); return false }
        return ownedIdentity > contactIdentity
    }

    func sendMessage(message: WebRTCInnerMessageJSON, forStartingCall: Bool, to callParticipant: CallParticipant) {
        guard let uuidForWebRTC = self.uuidForWebRTC else { assertionFailure(); return }

        do {
            let webrtcMessage = try message.embedInWebRTCMessageJSON(callIdentifier: uuidForWebRTC)
            self.sendWebRTCMessage(to: callParticipant, message: webrtcMessage, forStartingCall: forStartingCall, completion: {})
        } catch {
            assertionFailure()
            return
        }
    }

    func updateParticipant(newCallParticipants: [ContactBytesAndNameJSON]) {
        os_log("☎️ Entering updateParticipant(newCallParticipants: [ContactBytesAndNameJSON])", log: log, type: .info)
        CallHelper.checkQueue() // OK
        guard let ownedIdentity = self.ownedIdentity else { assertionFailure(); return }
        guard let incomingCall = self as? IncomingWebrtcCall else { assertionFailure(); return }
        guard let uuidForWebRTC = uuidForWebRTC else { assertionFailure(); return }

        guard let turnCredentials = self.callParticipants.first?.turnCredentials else { assertionFailure(); return }

        var newCallParticipantNamesAndGatheringPolicies: [ObvCryptoId: (String, GatheringPolicy)] = [:]
        var newParticipantsId: Set<ObvCryptoId> = Set()
        for newParticipant in newCallParticipants {
            let byteContactIdentity = newParticipant.byteContactIdentity
            guard let contactCryptoId = try? ObvCryptoId.init(identity: byteContactIdentity) else { assertionFailure(); continue }
            newParticipantsId.insert(contactCryptoId)
            newCallParticipantNamesAndGatheringPolicies[contactCryptoId] = (newParticipant.displayName, newParticipant.gatheringPolicy ?? .gatherOnce)
        }

        var currentParticipantsId: Set<ObvCryptoId> = Set()
        for currentParticipant in self.callParticipants {
            guard let contactIdentity = currentParticipant.contactIdentity else { assertionFailure(); continue }
            currentParticipantsId.insert(contactIdentity)
        }

        let participantsToAdd = newParticipantsId.subtracting(currentParticipantsId)
        let participantsToRemove = currentParticipantsId.subtracting(newParticipantsId)

        os_log("☎️ We have %d participant(s) to add", log: log, type: .info, participantsToAdd.count)

        for participantToAdd in participantsToAdd {
            guard participantToAdd != ownedIdentity else { continue } /// the received array contains the user himself

            var identityID: TypeSafeManagedObjectID<PersistedObvContactIdentity>? = nil
            ObvStack.shared.performBackgroundTaskAndWait { (context) in
                if let identity = try? PersistedObvContactIdentity.get(contactCryptoId: participantToAdd, ownedIdentityCryptoId: ownedIdentity, within: context),
                   !identity.devices.isEmpty {
                    identityID = identity.typedObjectID
                }
            }
            let shouldISendTheOfferToCallParticipant = self.shouldISendTheOfferToCallParticipant(contactIdentity: participantToAdd)
            guard let (fullName, gatheringPolicy) = newCallParticipantNamesAndGatheringPolicies[participantToAdd] else { assertionFailure(); return }
            let callParticipant: CallParticipant
            let peerConnectionHolder = shouldISendTheOfferToCallParticipant ? WebrtcPeerConnectionHolder(gatheringPolicy: gatheringPolicy) : nil
            if let identityID = identityID {
                callParticipant = CallParticipantImpl.createRecipient(contactID: identityID, peerConnectionHolder: peerConnectionHolder)
            } else {
                callParticipant = CallParticipantImpl.createRecipient(cryptoID: participantToAdd, fullName: fullName, peerConnectionHolder: peerConnectionHolder)
            }
            addParticipant(callParticipant: callParticipant, report: true)
            delegate_?.newParticipantWasAdded(call: self, callParticipant: callParticipant)

            guard callParticipant.contactIdentity != nil else { assertionFailure(); return }

            if shouldISendTheOfferToCallParticipant {
                os_log("☎️ Will set credentials for offer to a call participant", log: log, type: .info, participantsToAdd.count)
                callParticipant.setCredentialsForOffer(turnCredentials: turnCredentials)
                callParticipant.createOffer()
            } else {
                os_log("☎️ No need to send offer to the call participant", log: log, type: .info, participantsToAdd.count)
                /// check if we already received the offer the CallParticipant is supposed to send us
                if let (date, newParticipantOfferMessage) = incomingCall.receivedOfferMessages.removeValue(forKey: .cryptoId( participantToAdd)) {

                    delegate_?.processNewParticipantOfferMessageJSON(newParticipantOfferMessage, uuidForWebRTC: uuidForWebRTC, contact: .cryptoId(participantToAdd), messageUploadTimestampFromServer: date)
                }
            }

        }
        
        os_log("☎️ We have %d participant(s) to remove", log: log, type: .info, participantsToRemove.count)
        
        for participantToRemove in participantsToRemove {
            guard let participant = getParticipant(contact: .cryptoId(participantToRemove)) else { assertionFailure(); continue }
            guard participant.role != .caller else { continue }
            participant.closeConnection()
            removeParticipant(callParticipant: participant)
        }

    }

    // MARK: - Post office service

    func relay(from: ObvCryptoId, to: ObvCryptoId, messageType: WebRTCMessageJSON.MessageType, messagePayload: String) {
        CallHelper.checkQueue() // OK

        guard messageType.isAllowedToBeRelayed else { assertionFailure(); return }

        guard let participant = getParticipant(contact: .cryptoId(to)) else { return }
        let message: WebRTCDataChannelMessageJSON
        do {
            message = try RelayedMessageJSON(from: from.getIdentity(), relayedMessageType: messageType.rawValue, serializedMessagePayload: messagePayload).embedInWebRTCDataChannelMessageJSON()
        } catch {
            os_log("☎️ Could not send UpdateParticipantsMessageJSON: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }
        do {
            try participant.sendDataChannelMessage(message)
        } catch {
            os_log("☎️ Could not send data channel message: %{public}@", log: log, type: .fault, error.localizedDescription)
            return
        }
    }

    func receivedRelayedMessage(from: ObvCryptoId, messageType: WebRTCMessageJSON.MessageType, messagePayload: String) {
        CallHelper.checkQueue() // OK
        guard let uuidForWebRTC = uuidForWebRTC else { assertionFailure(); return }
        delegate_?.processReceivedWebRTCMessage(messageType: messageType, serializedMessagePayload: messagePayload, callIdentifier: uuidForWebRTC, contact: .cryptoId(from), messageUploadTimestampFromServer: Date(), messageIdentifierFromEngine: nil)
    }

    func sendWebRTCMessage(to: CallParticipant, message: WebRTCMessageJSON, forStartingCall: Bool, completion: @escaping () -> Void) {
        CallHelper.checkQueue() // OK
        guard let contactIdentificationStatus = to.contactIdentificationStatus else {
            os_log("☎️ Could not determine contact in the method sendWebRTCMessage", log: log, type: .fault)
            return
        }
        if case .hangedUp = message.messageType {
            // Also send message on the data channel, if the caller is gone
            do {
                let hangedUpDataChannel = try HangedUpDataChannelMessageJSON().embedInWebRTCDataChannelMessageJSON()
                try to.sendDataChannelMessage(hangedUpDataChannel)
            } catch {
                os_log("☎️ Could not send HangedUpDataChannelMessageJSON: %{public}@", log: log, type: .fault, error.localizedDescription)
            }
        }
        switch contactIdentificationStatus {
        case .known(let contactID):
            os_log("☎️ Posting a newWebRTCMessageToSend", log: log, type: .info)
            ObvMessengerInternalNotification.newWebRTCMessageToSend(webrtcMessage: message, contactID: contactID, forStartingCall: forStartingCall, completion: completion)
                .postOnDispatchQueue()
        case .unknown(let cryptoID, _):
            guard message.messageType.isAllowedToBeRelayed else { assertionFailure(); return }
            guard let incomingCall = self as? IncomingCall else { assertionFailure(); return }
            guard let caller = incomingCall.callerCallParticipant else { return }
            let toContactIdentity = cryptoID.getIdentity()

            do {
                let dataChannelMessage = try RelayMessageJSON(to: toContactIdentity, relayedMessageType: message.messageType.rawValue, serializedMessagePayload: message.serializedMessagePayload).embedInWebRTCDataChannelMessageJSON()
                try caller.sendDataChannelMessage(dataChannelMessage)
            } catch {
                os_log("☎️ Could not send RelayMessageJSON: %{public}@", log: log, type: .fault, error.localizedDescription)
                return
            }
        }
    }

    func offerCallCompleted(for callParticipant: CallParticipant, result: Result<TurnSessionWithCredentials, Error>) {
        CallHelper.checkQueue() // OK
        guard let uuidForWebRTC = self.uuidForWebRTC else { assertionFailure(); return }
        guard let gatheringPolicy = callParticipant.gatheringPolicy else { assertionFailure(); return }
        guard callParticipant.contactIdentificationStatus != nil else { assertionFailure(); return }
        switch result {
        case .success((let sessionDescriptionType, let sessionDescription, let turnUserName, let turnPassword, let turnServers)):
            var webrtcMessage: WebRTCMessageJSON
            let messageType = self is OutgoingCall ? "IncomingCallMessage" : "NewParticipantOfferMessage"
            do {
                let message: WebRTCInnerMessageJSON
                if self is OutgoingCall {
                    guard let turnUserName = turnUserName,
                          let turnPassword = turnPassword,
                          let turnServers = turnServers else {
                              assertionFailure(); return
                          }
                    var flitredGroupId: (groupUid: UID, groupOwner: ObvCryptoId)? = nil
                    if let groupId = groupId,
                       let participantIdentity = callParticipant.contactIdentity {
                        ObvStack.shared.viewContext.performAndWait {
                            guard let ownedIdentity = ownedIdentity else { return }
                            guard let ownedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: ownedIdentity, within: ObvStack.shared.viewContext) else {
                                os_log("Could not found ownedIdentity", log: log, type: .fault)
                                return
                            }
                            guard let contactGroup = try? PersistedContactGroup.getContactGroup(groupId: groupId, ownedIdentity: ownedIdentity) else {
                                os_log("Could not found contactGroup", log: log, type: .fault)
                                return
                            }
                            let groupMembers = Set(contactGroup.contactIdentities.map { $0.cryptoId })
                            if groupMembers.contains(participantIdentity) {
                                flitredGroupId = groupId
                            }
                            return
                        }
                    }

                    message = try IncomingCallMessageJSON(
                        sessionDescriptionType: sessionDescriptionType,
                        sessionDescription: sessionDescription,
                        turnUserName: turnUserName,
                        turnPassword: turnPassword,
                        turnServers: turnServers,
                        participantCount: callParticipants.count,
                        groupId: flitredGroupId,
                        gatheringPolicy: gatheringPolicy)
                } else { assert(self is IncomingCall)
                    message = try NewParticipantOfferMessageJSON(
                        sessionDescriptionType: sessionDescriptionType,
                        sessionDescription: sessionDescription,
                        gatheringPolicy: gatheringPolicy)
                }
                webrtcMessage = try message.embedInWebRTCMessageJSON(callIdentifier: uuidForWebRTC)
            } catch {
                os_log("☎️ Could not create and send %{public}@: %{public}@", log: log, type: .fault, messageType, error.localizedDescription)
                assertionFailure()
                return
            }
            let completion = { os_log("☎️ The %{public}@ was received by the server for callIdentifier %{public}@", log: self.log, type: .info, messageType, String(uuidForWebRTC)) }
            self.sendWebRTCMessage(to: callParticipant, message: webrtcMessage, forStartingCall: self is OutgoingCall, completion: completion)
        case .failure(let error):
            os_log("☎️ Could not create offer: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }
    }

    func restartCallCompleted(for callParticipant: CallParticipant, result: Result<ReconnectCallMessageJSON, Error>) {
        CallHelper.checkQueue() // OK
        guard let uuidForWebRTC = uuidForWebRTC else { assertionFailure(); return }

        switch result {
        case .success(let reconnectCallMessage):
            do {
                let webrtcMessage = try reconnectCallMessage.embedInWebRTCMessageJSON(callIdentifier: uuidForWebRTC)
                self.sendWebRTCMessage(to: callParticipant, message: webrtcMessage, forStartingCall: false, completion: {})
            } catch {
                assertionFailure()
                return
            }
        case .failure(let error):
            os_log("☎️ Could not reconnect call: %{public}@", log: log, type: .fault, error.localizedDescription)
            callParticipant.closeConnection()
            return
        }
    }

    func answerCallCompleted(for callParticipant: CallParticipant, result: Result<TurnSession, Error>) {
        CallHelper.checkQueue() // OK
        guard let incomingCall = self as? IncomingWebrtcCall else { assertionFailure(); return }
        guard let uuidForWebRTC = uuidForWebRTC else { assertionFailure(); return }

        switch result {
        case .success((let sessionDescriptionType, let sessionDescription)):
            var webrtcMessage: WebRTCMessageJSON
            let messageDescripton = callParticipant.role == .caller ? "AnswerIncomingCall" : "NewParticipantAnswerMessage"
            do {
                let message: WebRTCInnerMessageJSON
                if callParticipant.role == .caller {
                    message = try AnswerIncomingCallJSON(sessionDescriptionType: sessionDescriptionType, sessionDescription: sessionDescription)
                } else {
                    message = try NewParticipantAnswerMessageJSON(sessionDescriptionType: sessionDescriptionType, sessionDescription: sessionDescription)
                }
                webrtcMessage = try message.embedInWebRTCMessageJSON(callIdentifier: uuidForWebRTC)
            } catch {
                os_log("Could not create and send %{public}@: %{public}@", log: log, type: .fault, messageDescripton, error.localizedDescription)
                assertionFailure()
                incomingCall.delegate?.answerCallCompleted(callUUID: uuid, result: .failure(error))
                return
            }
            let completion = {
                os_log("☎️ The %{public}@ was received by the server for callIdentifier %{public}@", log: self.log, type: .info, messageDescripton, String(uuidForWebRTC))
                incomingCall.delegate?.answerCallCompleted(callUUID: self.uuid, result: .success((/* void */)))
            }
            sendWebRTCMessage(to: callParticipant, message: webrtcMessage, forStartingCall: false, completion: completion)
        case .failure(let error):
            os_log("☎️ Could not answer call: %{public}@", log: log, type: .fault, error.localizedDescription)
            incomingCall.delegate?.answerCallCompleted(callUUID: uuid, result: .failure(error))
            assertionFailure()
        }
    }


}

// MARK: - IncomingWebrtcCall

final class IncomingWebrtcCall: WebRTCCall, IncomingCall {

    let messageIdentifierFromEngine: Data
    private let messageUploadTimestampFromServer: Date

    private(set) var userAnsweredIncomingCall = false
    private var pushKitNotificationWasReceived = false
    var ringingMessageShouldBeSent = true
    var callHasBeenFiltered = false
    var rejectedBecauseOfMissingRecordPermission = false
    var receivedOfferMessages: [ParticipantId: (Date, NewParticipantOfferMessageJSON)] = [:]
    var initialParticipantCount: Int? // From IncomingWebrtcCall

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: IncomingWebrtcCall.self))
    weak var delegate: IncomingWebRTCCallDelegate? {
        delegate_ as? IncomingWebRTCCallDelegate
    }

    deinit {
        debugPrint("IncomingWebrtcCall deinit")
    }

    var callerCallParticipant: CallParticipant? {
        CallHelper.checkQueue() // OK
        return callParticipants.first { $0.role == .caller }
    }

    // MARK: Creating and updating an incoming call

    /// When receiving an encrypted PushKit notification, we immediately instantiate an `IncomingWebrtcCall` instance
    /// so as to show the CallKit UI as soon as possible (by calling the `reportNewIncomingCall` method of the `CXProvider`).
    init(encryptedPushNotification: EncryptedPushNotification, delegate: IncomingWebRTCCallDelegate) {
        CallHelper.checkQueue() // OK
                                /// For now, most of the vars are nil, until the encrypted notification is decrypted, making it possible to update this incoming call instance.
        self.messageIdentifierFromEngine = encryptedPushNotification.messageIdentifierFromEngine
        self.messageUploadTimestampFromServer = encryptedPushNotification.messageUploadTimestampFromServer
        self.pushKitNotificationWasReceived = true

        let callParticipant = CallParticipantImpl.createCaller()
        super.init(callParticipants: [callParticipant], usesCallKit: true, uuidForWebRTC: nil, delegate: delegate, ownedIdentity: nil, groupId: nil)
    }


    init(incomingCallMessage: IncomingCallMessageJSON, contactID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, uuidForWebRTC: UUID, messageIdentifierFromEngine: Data, messageUploadTimestampFromServer: Date, delegate: IncomingWebRTCCallDelegate, useCallKit: Bool) {
        CallHelper.checkQueue() // OK
        self.messageIdentifierFromEngine = messageIdentifierFromEngine
        self.messageUploadTimestampFromServer = messageUploadTimestampFromServer
        self.initialParticipantCount = incomingCallMessage.participantCount

        let callParticipant = CallParticipantImpl.createCaller(incomingCallMessage: incomingCallMessage, contactID: contactID)
        super.init(callParticipants: [callParticipant], usesCallKit: useCallKit, uuidForWebRTC: uuidForWebRTC, delegate: delegate, ownedIdentity: callParticipant.ownedIdentity, groupId: incomingCallMessage.groupId)
    }


    func pushKitNotificationReceived() {
        CallHelper.checkQueue() // OK
        self.pushKitNotificationWasReceived = true
        answerIfRequestedAndIfPossible()
    }

    func setDecryptedElements(incomingCallMessage: IncomingCallMessageJSON, contactID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, uuidForWebRTC: UUID) {
        CallHelper.checkQueue() // OK
        guard !isReady() else { return } /// We do not want to replace a previous peer connection holder
        guard let caller = self.callerCallParticipant as? CallParticipantImpl else { assertionFailure(); return }
        self.uuidForWebRTC = uuidForWebRTC
        caller.updateCaller(incomingCallMessage: incomingCallMessage, contactID: contactID)
        super.ownedIdentity = caller.ownedIdentity
        self.groupId = incomingCallMessage.groupId
        self.initialParticipantCount = incomingCallMessage.participantCount

        ObvMessengerInternalNotification.callParticipantHasBeenUpdated(callParticipant: caller, updateKind: .contactID).postOnDispatchQueue()
        answerIfRequestedAndIfPossible()
    }

    func isReady() -> Bool {
        CallHelper.checkQueue() // OK
        guard let caller = callerCallParticipant else { return false }
        let pushKitIsEitherDisabledOrReady = !ObvMessengerSettings.VoIP.isCallKitEnabled || pushKitNotificationWasReceived
        return uuidForWebRTC != nil && caller.isReady && pushKitIsEitherDisabledOrReady
    }

    // MARK: Answering call

    func answerWebRTCCall() {
        CallHelper.checkQueue() // OK

        userAnsweredIncomingCall = true
        setCallState(to: .userAnsweredIncomingCall)
        answerIfRequestedAndIfPossible()
    }


    private func answerIfRequestedAndIfPossible() {
        CallHelper.checkQueue() // OK

        guard let caller = callerCallParticipant else { return }
        guard userAnsweredIncomingCall else { return }

        caller.createAnswer()
    }

}

// MARK: - OutgoingWebRTCCall

final class OutgoingWebRTCCall: WebRTCCall, OutgoingCall {

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: OutgoingWebRTCCall.self))
    var delegate: OutgoingWebRTCCallDelegate? {
        delegate_ as? OutgoingWebRTCCallDelegate
    }
    private(set) var turnCredentials: TurnCredentials?

    deinit {
        debugPrint("OutgoingWebRTCCall deinit")
    }

    // MARK: Creating an outgoing call

    init(contactIDs: [TypeSafeManagedObjectID<PersistedObvContactIdentity>], delegate: OutgoingWebRTCCallDelegate, usesCallKit: Bool, groupId: (groupUid: UID, groupOwner: ObvCryptoId)?) {
        CallHelper.checkQueue() // OK
        let callParticipants = contactIDs.map { Self.createRecipient(contactID: $0) }
        let participant = callParticipants.first!
        super.init(callParticipants: callParticipants, usesCallKit: usesCallKit, uuidForWebRTC: nil, delegate: delegate, ownedIdentity: participant.ownedIdentity, groupId: groupId)
    }

    static func createRecipient(contactID: TypeSafeManagedObjectID<PersistedObvContactIdentity>) -> CallParticipant {
        let contactInfo = CallHelper.getContactInfo(contactID)
        return CallParticipantImpl.createRecipient(contactID: contactID, gatheringPolicy: contactInfo?.gatheringPolicy ?? .gatherOnce)
    }

    // MARK: Starting an outgoing call

    func startCall() throws {
        guard let ownedIdentity = ownedIdentity else { assertionFailure(); return }
        CallHelper.checkQueue() // OK
        guard state == .initial else {
            os_log("☎️ Trying to start this call although it is not initial", log: log, type: .fault)
            assertionFailure()
            throw makeError(message: "Trying to start this call although it is not initial")
        }
        setCallState(to: .gettingTurnCredentials)
        guard let uuidForWebRTC = self.uuidForWebRTC else {
            os_log("☎️ Could not find uuidForWebRTC which is unexpected for an outgoing call", log: log, type: .fault)
            assertionFailure()
            throw makeError(message: "Could not find uuidForWebRTC which is unexpected for an outgoing call")
        }
        delegate?.turnCredentialsRequiredByOutgoingCall(outgoingCallUuidForWebRTC: uuidForWebRTC, forOwnedIdentity: ownedIdentity)
    }

    func setTurnCredentials(turnCredentials: TurnCredentials) {
        CallHelper.checkQueue() // OK
        guard self.turnCredentials == nil else { assertionFailure(); return }
        self.turnCredentials = turnCredentials

        for callParticipant in callParticipants {
            guard callParticipant.turnCredentials == nil else { continue }
            callParticipant.setCredentialsForOffer(turnCredentials: turnCredentials)
        }
    }

    func offerCall() {
        CallHelper.checkQueue() // OK
        guard turnCredentials != nil else { assertionFailure(); return }
        for callParticipant in self.callParticipants {
            guard callParticipant.turnCredentials != nil else { assertionFailure(); return }
            callParticipant.createOffer()
        }
        self.setCallState(to: .initializingCall)
    }

    func processAnswerIncomingCallJSON(callParticipant: CallParticipant, _ answerIncomingCallMessage: AnswerIncomingCallJSON, completionHandler: @escaping ((Error?) -> Void)) {
        CallHelper.checkQueue() // OK
        callParticipant.setRemoteDescription(sessionDescriptionType: answerIncomingCallMessage.sessionDescriptionType,
                                             sessionDescription: answerIncomingCallMessage.sessionDescription,
                                             completionHandler: completionHandler)
    }

    func processUserWantsToAddParticipants(contactIDs: [TypeSafeManagedObjectID<PersistedObvContactIdentity>]) {
        CallHelper.checkQueue() // OK
        guard !contactIDs.isEmpty else { return }
        let callIsMuted = isMuted
        for contactID in contactIDs {
            let callParticipant = Self.createRecipient(contactID: contactID)

            guard callParticipant.ownedIdentity == ownedIdentity else {
                os_log("☎️ Trying to add contact to call for a different ownedIdentity", log: log, type: .info)
                continue
            }

            guard getParticipant(contact: .persisted(contactID)) == nil else {
                os_log("☎️ Trying to add contact to call which is already in the call", log: log, type: .info)
                continue
            }

            addParticipant(callParticipant: callParticipant, report: true)

            if let turnCredentials = turnCredentials {
                callParticipant.setCredentialsForOffer(turnCredentials: turnCredentials)
                callParticipant.createOffer()
                if callIsMuted {
                    callParticipant.mute()
                }
            }
        }
    }

    func setPermissionDeniedByServer() {
        CallHelper.checkQueue() // OK
        setCallState(to: .permissionDeniedByServer)
    }

    func setCallInitiationNotSupported() {
        CallHelper.checkQueue() // OK
        setCallState(to: .callInitiationNotSupported)
    }

}

extension CallParticipantImpl: WebrtcPeerConnectionHolderDelegate {

    func shouldISendTheOfferToCallParticipant() -> Bool {
        guard let delegate = delegate else { assertionFailure(); return false }
        guard let contactIdentity = contactIdentity else { assertionFailure(); return false }
        return delegate.shouldISendTheOfferToCallParticipant(contactIdentity: contactIdentity)
    }

    func peerConnectionStateDidChange(newState: RTCIceConnectionState) {
        CallHelper.checkQueue() // OK
        switch newState {
        case .new: return
        case .checking:
            self.delegate?.connectionIsChecking(for: self)
        case .connected:
            let oldState = self.state
            self.setPeerState(to: .connected)
            if let delegate = self.delegate, delegate.isOutgoingCall,
               oldState != .connected, oldState != .reconnecting {
                for otherParticipant in delegate.callParticipants.filter({$0.uuid != self.uuid}) {
                    otherParticipant.sendUpdateParticipantsMessageJSON(callParticipants: delegate.callParticipants)
                }
            }
            self.delegate?.connectionIsConnected(for: self)
        case .completed: return
        case .failed, .disconnected:
            self.reconnectAfterConnectionLoss()
        case .closed:
            self.delegate?.connectionWasClosed(for: self)
        case .count: return
        @unknown default: return
        }
    }

    func peerConnectionWasClosedDuringInitialization() {
        CallHelper.checkQueue() // OK
        self.delegate?.connectionWasClosed(for: self)
    }

    fileprivate func dataChannel(of peerConnectionHolder: WebrtcPeerConnectionHolder, didReceiveMessage message: WebRTCDataChannelMessageJSON) {
        CallHelper.checkQueue() // OK
        switch message.messageType {
        case .muted:
            let mutedMessage: MutedMessageJSON
            do {
                mutedMessage = try MutedMessageJSON.decode(serializedMessage: message.serializedMessage)
            } catch {
                os_log("☎️ Could not decode MutedMessageJSON: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
            os_log("☎️ Receive MutedMessageJSON", log: log, type: .info)
            processMutedMessageJSON(message: mutedMessage)
        case .updateParticipant:
            let updateParticipantsMessage: UpdateParticipantsMessageJSON
            do {
                updateParticipantsMessage = try UpdateParticipantsMessageJSON.decode(serializedMessage: message.serializedMessage)
            } catch {
                os_log("☎️ Could not decode UpdateParticipantsMessageJSON: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
            os_log("☎️ Receive UpdateParticipantsMessageJSON", log: log, type: .info)
            processUpdateParticipantsMessageJSON(message: updateParticipantsMessage)
        case .relayMessage:
            let relayMessage: RelayMessageJSON
            do {
                relayMessage = try RelayMessageJSON.decode(serializedMessage: message.serializedMessage)
            } catch {
                os_log("☎️ Could not decode RelayMessageJSON: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
            os_log("☎️ Receive RelayMessageJSON", log: log, type: .info)
            processRelayMessageJSON(message: relayMessage)
        case .relayedMessage:
            let relayedMessage: RelayedMessageJSON
            do {
                relayedMessage = try RelayedMessageJSON.decode(serializedMessage: message.serializedMessage)
            } catch {
                os_log("☎️ Could not decode RelayedMessageJSON: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
            os_log("☎️ Receive RelayedMessageJSON", log: log, type: .info)
            processRelayedMessageJSON(message: relayedMessage)
        case .hangedUpMessage:
            do {
                let hangedUpMessage = try HangedUpDataChannelMessageJSON.decode(serializedMessage: message.serializedMessage)
                processHangedUpMessage(message: hangedUpMessage)
            } catch {
                os_log("☎️ Could not parse HangedUpDataChannelMessageJSON: %{public}@", log: log, type: .fault, error.localizedDescription)
            }


        }
    }

    fileprivate func dataChannel(of peerConnectionHolder: WebrtcPeerConnectionHolder, didChangeState state: RTCDataChannelState) {
        CallHelper.checkQueue() // OK
        os_log("☎️ Data channel changed state. New state is %{public}@", log: log, type: .info, state.description)
        switch state {
        case .open:
            delegate?.dataChannelIsOpened(for: self)
            sendMutedMessageJSON()
        case .connecting, .closing, .closed:
            break
        @unknown default:
            assertionFailure()
        }
    }

    func sendMutedMessageJSON() {
        CallHelper.checkQueue() // OK
        let message: WebRTCDataChannelMessageJSON
        do {
            message = try MutedMessageJSON(muted: isMuted).embedInWebRTCDataChannelMessageJSON()
        } catch {
            os_log("☎️ Could not send MutedMessageJSON: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }
        do {
            try peerConnectionHolder?.sendDataChannelMessage(message)
        } catch {
            os_log("☎️ Could not send data channel message: %{public}@", log: log, type: .fault, error.localizedDescription)
            return
        }
    }

    func createAnswerResult(_ result: Result<TurnSession, Error>) {
        OperationQueue.main.addOperation { [weak self] in
            guard let _self = self else { return }
            _self.delegate?.answerCallCompleted(for: _self, result: result)
            if case .success = result {
                _self.setPeerState(to: .connectingToPeer)
            }
        }
    }

    func createOfferResult(_ result: Result<TurnSessionWithCredentials, Error>) {
        OperationQueue.main.addOperation { [weak self] in
            guard let _self = self else { return }
            _self.delegate?.offerCallCompleted(for: _self, result: result)
            if case .success = result {
                _self.setPeerState(to: .startCallMessageSent)
            }
        }
    }

    func createRestartResult(_ result: Result<ReconnectCallMessageJSON, Error>) {
        OperationQueue.main.addOperation { [weak self] in
            guard let _self = self else { return }
            guard _self.state == .connected || _self.state == .reconnecting else { return }
            _self.delegate?.restartCallCompleted(for: _self, result: result)
        }
    }

    func sendNewIceCandidateMessage(candidate: RTCIceCandidate) {
        OperationQueue.main.addOperation { [weak self] in
            guard let _self = self else { return }
            _self.delegate?.sendMessage(message: candidate.toJSON, forStartingCall: false, to: _self)
        }
    }

    func sendRemoveIceCandidatesMessages(candidates: [RTCIceCandidate]) {
        OperationQueue.main.addOperation { [weak self] in
            guard let _self = self else { return }
            let message = RemoveIceCandidatesMessageJSON(candidates: candidates.map({ $0.toJSON }))
            _self.delegate?.sendMessage(message: message, forStartingCall: false, to: _self)
        }
    }

}

final class CallParticipantImpl: CallParticipant {

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: WebRTCCall.self))

    let uuid: UUID = UUID()
    let role: Role
    var contactIdentificationStatus: ParticipantContactIdentificationStatus?
    var state: PeerState

    private(set) var contactIsMuted = false

    var timeoutTimer: Timer?

    private var peerConnectionHolder: WebrtcPeerConnectionHolder?

    var gatheringPolicy: GatheringPolicy? {
        peerConnectionHolder?.gatheringPolicy
    }

    weak var delegate: CallParticipantDelegate?

    var contactInfo: ContactInfo? {
        guard let contactIdentificationStatus = contactIdentificationStatus else { return nil }
        guard case let .known(contactID) = contactIdentificationStatus else { return nil }
        return CallHelper.getContactInfo(contactID)
    }

    var ownedIdentity: ObvCryptoId? {
        guard let contactIdentificationStatus = contactIdentificationStatus else { return nil }
        switch contactIdentificationStatus {
        case .known: return contactInfo?.ownedIdentity
        case .unknown: assertionFailure(); return nil
        }
    }

    var contactIdentity: ObvCryptoId? {
        guard let contactIdentificationStatus = contactIdentificationStatus else { return nil }
        switch contactIdentificationStatus {
        case .known: return contactInfo?.cryptoId
        case .unknown(let cryptoID, _): return cryptoID
        }
    }

    var fullDisplayName: String? {
        guard let contactIdentificationStatus = contactIdentificationStatus else { return nil }
        switch contactIdentificationStatus {
        case .known: return contactInfo?.fullDisplayName
        case .unknown( _, let fullName): return fullName
        }
    }

    var displayName: String? {
        guard let contactIdentificationStatus = contactIdentificationStatus else { return nil }
        switch contactIdentificationStatus {
        case .known: return contactInfo?.customDisplayName ?? contactInfo?.fullDisplayName
        case .unknown( _, let fullName): return fullName
        }
    }

    var photoURL: URL? { contactInfo?.photoURL }
    var identityColors: (background: UIColor, text: UIColor)? { contactInfo?.identityColors }

    var info: ParticipantInfo? {
        guard let contactIdentificationStatus = contactIdentificationStatus else { return nil }
        switch contactIdentificationStatus {
        case .known(contactID: let contactID):
            return ParticipantInfo(contactID: contactID, isCaller: role == .caller)
        case .unknown:
            return nil
        }
    }

    var isReady: Bool {
        return contactIdentificationStatus != nil && peerConnectionHolder != nil
    }

    /// Create the `caller` participant for an incoming call when nothing is known for this caller (yet). This can happen when receiving a pushkit notification.
    static func createCaller() -> Self {
        return self.init(role: .caller, contactIdentificationStatus: nil, peerConnectionHolder: nil)
    }

    /// When the caller was created using the `createCaller()` method, we update her parameters as soon as they are known.
    func updateCaller(incomingCallMessage: IncomingCallMessageJSON, contactID: TypeSafeManagedObjectID<PersistedObvContactIdentity>) {
        assert(role == .caller)
        assert(self.contactIdentificationStatus == nil)
        assert(self.peerConnectionHolder == nil)
        self.contactIdentificationStatus = .known(contactID: contactID)
        self.peerConnectionHolder = WebrtcPeerConnectionHolder(incomingCallMessage: incomingCallMessage)
        self.peerConnectionHolder?.delegate = self
    }

    func updateRecipient(newParticipantOfferMessage: NewParticipantOfferMessageJSON, turnCredentials: TurnCredentials) {
        assert(role == .recipient)
        assert(self.peerConnectionHolder == nil)
        self.peerConnectionHolder = WebrtcPeerConnectionHolder(
            newParticipantOfferMessage: newParticipantOfferMessage,
            turnCredentials: turnCredentials)
        self.peerConnectionHolder?.delegate = self
    }

    /// Create the `caller` participant for an incoming call when the contact ID of this caller is already known.
    static func createCaller(incomingCallMessage: IncomingCallMessageJSON, contactID: TypeSafeManagedObjectID<PersistedObvContactIdentity>) -> Self {
        let peerConnectionHolder = WebrtcPeerConnectionHolder(incomingCallMessage: incomingCallMessage)
        return self.init(role: .caller, contactIdentificationStatus: .known(contactID: contactID), peerConnectionHolder: peerConnectionHolder)
    }

    static func createRecipient(contactID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, gatheringPolicy: GatheringPolicy) -> Self {
        let peerConnectionHolder = WebrtcPeerConnectionHolder(gatheringPolicy: gatheringPolicy)
        return createRecipient(contactID: contactID, peerConnectionHolder: peerConnectionHolder)
    }

    /// Create a `recipient` participant for an outgoing call
    fileprivate static func createRecipient(contactID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, peerConnectionHolder: WebrtcPeerConnectionHolder?) -> Self {
        return self.init(role: .recipient, contactIdentificationStatus: .known(contactID: contactID), peerConnectionHolder: peerConnectionHolder)
    }

    fileprivate static func createRecipient(cryptoID: ObvCryptoId, fullName: String, peerConnectionHolder: WebrtcPeerConnectionHolder?) -> Self {
        return self.init(role: .recipient, contactIdentificationStatus: .unknown(cryptoId: cryptoID, fullName: fullName), peerConnectionHolder: peerConnectionHolder)
    }

    private init(role: Role, contactIdentificationStatus: ParticipantContactIdentificationStatus?, peerConnectionHolder: WebrtcPeerConnectionHolder?) {
        self.role = role
        self.contactIdentificationStatus = contactIdentificationStatus
        self.peerConnectionHolder = peerConnectionHolder
        self.state = .initial
        self.timeoutTimer = nil
        self.peerConnectionHolder?.delegate = self
    }

    func setPeerState(to newState: PeerState) {
        CallHelper.checkQueue() // OK
        os_log("☎️ WebRTCCall participant will change state: %{public}@ --> %{public}@", log: log, type: .info, self.state.debugDescription, newState.debugDescription)
        self.state = newState

        switch self.state {
        case .initial:
            break
        case .startCallMessageSent:
            scheduleTimeout()
        case .ringing:
            scheduleTimeout()
        case .busy:
            break
        case .callRejected:
            break
        case .connectingToPeer:
            createPeerStateConnectionTimeout()
        case .connected:
            invalidateTimeout()
        case .reconnecting:
            createPeerStateConnectionTimeout()
        case .hangedUp:
            break
        case .kicked:
            break
        case .timeout:
            break
        }
        if self.state.isFinalState {
            closeConnection()
        }

        delegate?.participantWasUpdated(callParticipant: self, updateKind: .state(newState: state))
    }

    func createAnswer() {
        guard let peerConnectionHolder = self.peerConnectionHolder else { assertionFailure(); return }
        peerConnectionHolder.createAnswer()
    }

    func setCredentialsForOffer(turnCredentials: TurnCredentials) {
        assert(role == .recipient)

        guard let peerConnectionHolder = self.peerConnectionHolder else { assertionFailure(); return }
        peerConnectionHolder.setCredentialsForOffer(turnCredentials: turnCredentials)
    }

    func createOffer() {
        assert(role == .recipient)

        guard let peerConnectionHolder = self.peerConnectionHolder else { assertionFailure(); return }
        peerConnectionHolder.createOffer()
    }

    func setRemoteDescription(sessionDescriptionType: String, sessionDescription: String, completionHandler: @escaping ((Error?) -> Void)) {
        guard let peerConnectionHolder = self.peerConnectionHolder else { assertionFailure(); return }
        peerConnectionHolder.setRemoteDescription(sessionDescriptionType: sessionDescriptionType,
                                                  sessionDescription: sessionDescription,
                                                  completionHandler: completionHandler)
    }

    func createRestartOffer() {
        guard let peerConnectionHolder = self.peerConnectionHolder else { assertionFailure(); return }
        peerConnectionHolder.createRestartOffer()
    }

    func handleReceivedRestartSdp(sessionDescriptionType: String,
                                  sessionDescription: String,
                                  reconnectCounter: Int,
                                  peerReconnectCounterToOverride: Int) {
        guard let peerConnectionHolder = self.peerConnectionHolder else { assertionFailure(); return }
        peerConnectionHolder.handleReceivedRestartSdp(sessionDescriptionType: sessionDescriptionType,
                                                      sessionDescription: sessionDescription,
                                                      reconnectCounter: reconnectCounter,
                                                      peerReconnectCounterToOverride: peerReconnectCounterToOverride)
    }

    func reconnectAfterConnectionLoss() {
        CallHelper.checkQueue() // OK
        setPeerState(to: .reconnecting)

        if case .gatherOnce = gatheringPolicy {
            peerConnectionHolder?.createRestartOffer()
        }
    }

    func closeConnection() {
        guard let peerConnectionHolder = self.peerConnectionHolder else { return }
        peerConnectionHolder.close()
    }

    var isMuted: Bool {
        peerConnectionHolder?.isAudioTrackMuted ?? false
    }

    func mute() {
        CallHelper.checkQueue() // OK
        guard let peerConnectionHolder = peerConnectionHolder else { return }
        peerConnectionHolder.muteAudioTracks()
        sendMutedMessageJSON()
    }

    func unmute() {
        CallHelper.checkQueue() // OK
        guard let peerConnectionHolder = peerConnectionHolder else { return }
        peerConnectionHolder.unmuteAudioTracks()
        sendMutedMessageJSON()
    }

    var turnCredentials: TurnCredentials? {
        peerConnectionHolder?.turnCredentials
    }

    private func processMutedMessageJSON(message: MutedMessageJSON) {
        CallHelper.checkQueue() // OK
        guard contactIsMuted != message.muted else { return }
        contactIsMuted = message.muted

        delegate?.participantWasUpdated(callParticipant: self, updateKind: .contactMuted)

    }

    private func processUpdateParticipantsMessageJSON(message: UpdateParticipantsMessageJSON) {
        CallHelper.checkQueue() // OK
        guard role == .caller else { return }
        delegate?.updateParticipant(newCallParticipants: message.callParticipants)
    }

    private func processRelayMessageJSON(message: RelayMessageJSON) {
        CallHelper.checkQueue() // OK
        guard role == .recipient else { return }

        do {
            guard let fromId = self.contactIdentity else { assertionFailure(); return }
            let toId = try ObvCryptoId(identity: message.to)
            guard let messageType = WebRTCMessageJSON.MessageType(rawValue: message.relayedMessageType) else { throw NSError() }
            let messagePayload = message.serializedMessagePayload
            delegate?.relay(from: fromId, to: toId, messageType: messageType, messagePayload: messagePayload)
        } catch {
            os_log("☎️ Could not read received RelayMessageJSON: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }
    }

    private func processRelayedMessageJSON(message: RelayedMessageJSON) {
        CallHelper.checkQueue() // OK
        guard role == .caller else { return }

        do {
            let fromId = try ObvCryptoId(identity: message.from)
            guard let messageType = WebRTCMessageJSON.MessageType(rawValue: message.relayedMessageType) else { throw NSError() }
            let messagePayload = message.serializedMessagePayload
            delegate?.receivedRelayedMessage(from: fromId, messageType: messageType, messagePayload: messagePayload)
        } catch {
            os_log("☎️ Could not read received RelayedMessageJSON: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }
    }

    private func processHangedUpMessage(message: HangedUpDataChannelMessageJSON) {
        CallHelper.checkQueue() // OK
        setPeerState(to: .hangedUp)
    }

    func sendDataChannelMessage(_ message: WebRTCDataChannelMessageJSON) throws {
        guard let peerConnectionHolder = self.peerConnectionHolder else { return }
        try peerConnectionHolder.sendDataChannelMessage(message)
    }

    func sendUpdateParticipantsMessageJSON(callParticipants: [CallParticipant]) {
        let message: WebRTCDataChannelMessageJSON
        do {
            message = try UpdateParticipantsMessageJSON(callParticipants: callParticipants).embedInWebRTCDataChannelMessageJSON()
        } catch {
            os_log("☎️ Could not send UpdateParticipantsMessageJSON: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }
        do {
            try sendDataChannelMessage(message)
        } catch {
            os_log("☎️ Could not send data channel message: %{public}@", log: log, type: .fault, error.localizedDescription)
            return
        }
    }

    func invalidateTimeout() {
        CallHelper.checkQueue() // OK
        if let timer = self.timeoutTimer {
            os_log("☎️ Invalidate Participant Timeout Timer", log: log, type: .info)
            timer.invalidate()
            self.timeoutTimer = nil
        }
    }

    func scheduleTimeout() {
        CallHelper.checkQueue() // OK
        invalidateTimeout()
        let log = self.log
        os_log("☎️ Schedule Participant Timeout Timer", log: log, type: .info)
        self.timeoutTimer = Timer.scheduledTimer(withTimeInterval: WebRTCCall.callTimeout, repeats: false) { _ in
            OperationQueue.main.addOperation {
                guard self.state != .connected else {
                    os_log("☎️ We prevent the timer from firing since the call is in progress. We should not have gotten to this point.", log: log, type: .error)
                    return
                }
                os_log("☎️ Fire Participant Timeout Timer", log: self.log, type: .info)
                self.setPeerState(to: .timeout)
            }
        }
    }

    func createPeerStateConnectionTimeout() {
        CallHelper.checkQueue() // OK
        invalidateTimeout()
        let log = self.log
        os_log("☎️ Schedule Peer State Connection Timeout Timer", log: log, type: .info)
        let timeout = WebRTCCall.callConnectionTimeout * TimeInterval(CGFloat.random(in: 1...2))
        self.timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
            OperationQueue.main.addOperation {
                if let delegate = self.delegate,
                   delegate.callParticipants.count > 1 {
                    self.reconnectAfterConnectionLoss()
                } else {
                    self.scheduleTimeout()
                }
            }
        }
    }

    func processIceCandidatesJSON(message: IceCandidateJSON) {
        CallHelper.checkQueue() // OK
        guard let peerConnectionHolder = self.peerConnectionHolder else { return }
        peerConnectionHolder.addIceCandidate(iceCandidate: message.iceCandidate)
    }

    func processRemoveIceCandidatesMessageJSON(message: RemoveIceCandidatesMessageJSON) {
        CallHelper.checkQueue() // OK
        guard let peerConnectionHolder = self.peerConnectionHolder else { return }
        peerConnectionHolder.removeIceCandidates(iceCandidates: message.iceCandidates)
    }


}

// MARK: - WebrtcPeerConnectionHolderDelegate

fileprivate protocol WebrtcPeerConnectionHolderDelegate: AnyObject {
    func peerConnectionStateDidChange(newState: RTCIceConnectionState)
    func peerConnectionWasClosedDuringInitialization()
    func dataChannel(of peerConnectionHolder: WebrtcPeerConnectionHolder, didReceiveMessage message: WebRTCDataChannelMessageJSON)
    func dataChannel(of peerConnectionHolder: WebrtcPeerConnectionHolder, didChangeState state: RTCDataChannelState)
    func shouldISendTheOfferToCallParticipant() -> Bool

    func createOfferResult(_ result: Result<TurnSessionWithCredentials, Error>)
    func createAnswerResult(_ result: Result<TurnSession, Error>)
    func createRestartResult(_ result: Result<ReconnectCallMessageJSON, Error>)

    func sendNewIceCandidateMessage(candidate: RTCIceCandidate)
    func sendRemoveIceCandidatesMessages(candidates: [RTCIceCandidate])
}

extension GatheringPolicy {
    var rtcPolicy: RTCContinualGatheringPolicy {
        switch self {
        case .gatherOnce: return .gatherOnce
        case .gatherContinually: return .gatherContinually
        }
    }
}

// MARK: - WebrtcPeerConnectionHolder

fileprivate final class WebrtcPeerConnectionHolder: NSObject, RTCPeerConnectionDelegate, CallDataChannelWorkerDelegate {

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: WebrtcPeerConnectionHolder.self))

    private static let errorDomain = "WebrtcPeerConnectionHolder"

    private let outgoingCall: Bool
    let gatheringPolicy: GatheringPolicy
    private let queueForIceGathering = DispatchQueue(label: "Queue for ice gathering")

    private var iceCandidates = [RTCIceCandidate]()
    private var pendingRemoteIceCandidates = [RTCIceCandidate]()
    private var readyToForwardRemoteIceCandidates = false {
        didSet {
            guard readyToForwardRemoteIceCandidates else { return }
            os_log("☎️❄️ Forwarding remote ICE candidates is ready", log: self.log, type: .info)
            drainRemoteIceCandidates()
        }
    }
    private var iceGatheringCompletedWasCalled = false
    private var reconnectOfferCounter: Int = 0
    private var reconnectAnswerCounter: Int = 0

    private static let audioCodecs = Set(["opus", "PCMU", "PCMA", "telephone-event", "red"])

    private var dataChannelWorker: DataChannelWorker?
    weak var delegate: WebrtcPeerConnectionHolderDelegate?

    private var connectionState: RTCIceConnectionState?

    private var turnUserName: String?
    private var turnPassword: String?
    private var turnServersURL: [String]?
    private var sessionDescriptionType: String?
    private var sessionDescription: String?
    private var peerConnection: RTCPeerConnection?

    enum CompletionKind {
        case answer
        case offer
        case restart
    }
    var currentCompletion: CompletionKind? = nil

    private let mediaConstraints = [kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                                    kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueFalse]

    private func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: WebrtcPeerConnectionHolder.errorDomain, code: 0, userInfo: userInfo)
    }

    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
    }()

    var turnCredentials: TurnCredentials? {
        guard let turnUserName = turnUserName else { return nil }
        guard let turnPassword = turnPassword else { return nil }
        return TurnCredentialsImpl(turnUserName: turnUserName,
                                   turnPassword: turnPassword,
                                   turnServers: turnServersURL)
    }

    init(incomingCallMessage: IncomingCallMessageJSON) {
        self.turnUserName = incomingCallMessage.turnUserName
        self.turnPassword = incomingCallMessage.turnPassword
        self.sessionDescriptionType = incomingCallMessage.sessionDescriptionType
        self.sessionDescription = incomingCallMessage.sessionDescription
        self.turnServersURL = incomingCallMessage.turnServers
        self.outgoingCall = false
        self.gatheringPolicy = incomingCallMessage.gatheringPolicy ?? .gatherOnce
        super.init()
    }

    init(newParticipantOfferMessage: NewParticipantOfferMessageJSON, turnCredentials: TurnCredentials) {
        self.turnUserName = turnCredentials.turnUserName
        self.turnPassword = turnCredentials.turnPassword
        self.sessionDescriptionType = newParticipantOfferMessage.sessionDescriptionType
        self.sessionDescription = newParticipantOfferMessage.sessionDescription
        self.turnServersURL = turnCredentials.turnServers
        self.outgoingCall = false
        self.gatheringPolicy = newParticipantOfferMessage.gatheringPolicy ?? .gatherOnce
        super.init()
    }

    /// Used during the init of an outgoing call
    init(gatheringPolicy: GatheringPolicy) {
        self.outgoingCall = true
        self.gatheringPolicy = gatheringPolicy
        super.init()
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

    func setCredentialsForOffer(turnCredentials: TurnCredentials) {
        self.turnUserName = turnCredentials.turnUserName
        self.turnPassword = turnCredentials.turnPassword
        self.turnServersURL = turnCredentials.turnServers
    }

    private func createPeerConnection() {
        assert(peerConnection == nil)
        guard let username = turnUserName else { assertionFailure(); return }
        guard let credential = turnPassword else { assertionFailure(); return }
        var turnServers: [String]
        if let turnServersURL = turnServersURL {
            turnServers = turnServersURL
        } else {
            /// Fallback if the caller use an old olvid version without giving turnServersURL in IncomingCallMessageJSON
            assertionFailure("Turn servers should have been set in setCredentialsForOutgoingCall")
            turnServers = ObvMessengerConstants.TurnServerURLs.loadBalanced
        }
        guard !turnServers.isEmpty else { assertionFailure(); return }
        let iceServer = WebRTC.RTCIceServer(urlStrings: turnServers,
                                            username: username,
                                            credential: credential,
                                            tlsCertPolicy: .insecureNoCheck)
        let rtcConfiguration = RTCConfiguration()
        rtcConfiguration.iceServers = [iceServer]
        rtcConfiguration.iceTransportPolicy = .relay
        rtcConfiguration.sdpSemantics = .unifiedPlan
        rtcConfiguration.continualGatheringPolicy = gatheringPolicy.rtcPolicy
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil,
                                              optionalConstraints: nil)
        os_log("☎️❄️ Create Peer Connection with %{public}@ policy", log: log, type: .info, gatheringPolicy.localizedDescription)
        peerConnection = WebrtcPeerConnectionHolder.factory.peerConnection(with: rtcConfiguration, constraints: constraints, delegate: self)
        assert(peerConnection != nil)
        peerConnection?.addOlvidTracks(factory: WebrtcPeerConnectionHolder.factory)
    }

    func close() {
        guard let peerConnection = self.peerConnection else {
            OperationQueue.main.addOperation {
                self.delegate?.peerConnectionWasClosedDuringInitialization()
            }
            return
        }
        guard peerConnection.connectionState != .closed else { return }
        os_log("☎️ Closing peer connection. State before closing: %{public}@", log: log, type: .info, peerConnection.connectionState.debugDescription)
        peerConnection.close()
    }
    

    func createOffer() {
        assert(peerConnection == nil)
        createPeerConnection()

        os_log("☎️ Create Data Channel", log: log, type: .info)
        createDataChannel()

        let mediaConstraints = RTCMediaConstraints(mandatoryConstraints: self.mediaConstraints, optionalConstraints: nil)
        let log = self.log
        os_log("☎️ Create offer", log: log, type: .info)
        peerConnection?.offer(for: mediaConstraints) { [weak self] (rtcSessionDescription, error) in
            guard let _self = self else { return }
            guard error == nil else { _self.delegate?.createOfferResult(.failure(error!)); return }
            guard let rtcSessionDescription = rtcSessionDescription else {
                _self.delegate?.createOfferResult(.failure(_self.makeError(message: "rtcSessionDescription is nil, which is unexpected")))
                return
            }
            os_log("☎️ Created an RTCSessionDescription", log: log, type: .info)
            // Filter the description
            let filteredLocalRTCSessionDescription: RTCSessionDescription
            do {
                let filteredSdp = try _self.filterSdpDescriptionCodec(sessionDescription: rtcSessionDescription.sdp)
                filteredLocalRTCSessionDescription = RTCSessionDescription(type: rtcSessionDescription.type, sdp: filteredSdp)
            } catch {
                _self.delegate?.createOfferResult(.failure(error))
                return
            }
            if case .gatherOnce = _self.gatheringPolicy {
                // We start the ICE gathering by setting the local description.
                _self.currentCompletion = .offer
            }
            _self.peerConnection?.setLocalDescription(filteredLocalRTCSessionDescription) { (error) in
                guard error == nil else {
                    _self.currentCompletion = nil
                    _self.delegate?.createOfferResult(.failure(error!))
                    return
                }
                if case .gatherContinually = _self.gatheringPolicy {
                    _self.createOfferResult()
                }
            }

        }
    }


    /// For outgoing calls only, or for reconnecting purposes
    func setRemoteDescription(sessionDescriptionType: String, sessionDescription: String, completionHandler: @escaping ((Error?) -> Void)) {
        let rtcSdpType = RTCSessionDescription.type(for: sessionDescriptionType)
        let sdp = RTCSessionDescription(type: rtcSdpType, sdp: sessionDescription)
        guard let peerConnection = peerConnection else {
            completionHandler(makeError(message: "No peer connection available"))
            return
        }
        peerConnection.setRemoteDescription(sdp, completionHandler: completionHandler)
    }

    func createAnswer() {
        assert(peerConnection == nil)
        createPeerConnection()

        guard let peerConnection = self.peerConnection else { delegate?.createAnswerResult(.failure(makeError(message: "No PeerConnection"))); return }
        guard let sessionDescriptionType = self.sessionDescriptionType else { delegate?.createAnswerResult(.failure(makeError(message: "No Session description type"))); return }
        guard let sessionDescription = self.sessionDescription else { delegate?.createAnswerResult(.failure(makeError(message: "No Session description"))); return }

        createDataChannel()

        let mediaConstraints = RTCMediaConstraints(mandatoryConstraints: self.mediaConstraints, optionalConstraints: nil)
        let rtcSdpType = RTCSessionDescription.type(for: sessionDescriptionType)
        let sdp = RTCSessionDescription(type: rtcSdpType, sdp: sessionDescription)

        peerConnection.setRemoteDescription(sdp) { [weak self] (error) in

            guard let _self = self else { return }
            guard error == nil else { _self.delegate?.createAnswerResult(.failure(error!)); return }

            peerConnection.answer(for: mediaConstraints) { (localRTCSessionDescription, error) in

                guard error == nil else { _self.delegate?.createAnswerResult(.failure(error!)); return }
                guard let localRTCSessionDescription = localRTCSessionDescription else {
                    _self.delegate?.createAnswerResult(.failure(_self.makeError(message: "Could not get local RTC Session Description")))
                    return
                }

                // Filter the description
                let filteredLocalRTCSessionDescription: RTCSessionDescription
                do {
                    let filteredSdp = try _self.filterSdpDescriptionCodec(sessionDescription: localRTCSessionDescription.sdp)
                    filteredLocalRTCSessionDescription = RTCSessionDescription(type: localRTCSessionDescription.type, sdp: filteredSdp)
                } catch {
                    _self.delegate?.createAnswerResult(.failure(error))
                    return
                }

                if case .gatherOnce = _self.gatheringPolicy {
                    // We start the ICE gathering by setting the local description.
                    _self.currentCompletion = .answer
                }
                peerConnection.setLocalDescription(filteredLocalRTCSessionDescription) { (error) in
                    guard error == nil else {
                        _self.delegate?.createAnswerResult(.failure(error!))
                        _self.currentCompletion = nil
                        return
                    }
                    if case .gatherContinually = _self.gatheringPolicy {
                        _self.createAnswerResult()
                    }
                }
            }
        }
    }

    func rollback() {
        guard let peerConnection = peerConnection else { assertionFailure(); return }
        os_log("☎️ Rollback", log: log, type: .info)
        peerConnection.setLocalDescription(RTCSessionDescription(type: .rollback, sdp: "")) { _ in }
    }

    private func internalRestartAnwser() {
        guard let peerConnection = peerConnection else { assertionFailure(); return }

        let mediaConstraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil)
        let log = self.log
        peerConnection.answer(for: mediaConstraints) { [weak self] (rtcSessionDescription, error) in
            guard let _self = self else { return }
            guard error == nil else { _self.delegate?.createRestartResult(.failure(error!)); return }
            guard let rtcSessionDescription = rtcSessionDescription else {
                _self.delegate?.createRestartResult(.failure(_self.makeError(message: "rtcSessionDescription is nil, which is unexpected")))
                return
            }

            guard peerConnection.signalingState == .haveRemoteOffer else {
                /// if we are not in  have_remote_offer, we shouldn't be creating an offer or an answer --> we don't set anything
                os_log("☎️ Not in have_remote_offer could not set RTCSessionDescription for restarting", log: log, type: .info)
                return
            }

            os_log("☎️ Created an RTCSessionDescription (%{public}@) for restarting", log: log, type: .info, rtcSessionDescription.type.debugDescription)

            // Filter the description
            let filteredLocalRTCSessionDescription: RTCSessionDescription
            do {
                let filteredSdp = try _self.filterSdpDescriptionCodec(sessionDescription: rtcSessionDescription.sdp)
                filteredLocalRTCSessionDescription = RTCSessionDescription(type: rtcSessionDescription.type, sdp: filteredSdp)
            } catch {
                _self.delegate?.createRestartResult(.failure(error))
                return
            }

            assert(filteredLocalRTCSessionDescription.type == .answer)


            if case .gatherOnce = _self.gatheringPolicy {
                // We start the ICE gathering by setting the local description. We store the completion handler so as to call it later, from one of the delegate methods.
                _self.currentCompletion = .restart
            }
            _self.peerConnection?.setLocalDescription(filteredLocalRTCSessionDescription) { (error) in
                guard error == nil else {
                    _self.delegate?.createRestartResult(.failure(error!))
                    _self.currentCompletion = nil
                    return
                }
                if case .gatherContinually = _self.gatheringPolicy {
                    _self.createRestartResult()
                }
            }
            if case .gatherOnce = _self.gatheringPolicy {
                _self.resetGatheringState()
            }
        }
    }

    private func internalRestartOffer() {
        guard let peerConnection = peerConnection else { assertionFailure(); return }

        let mediaConstraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil)
        let log = self.log
        peerConnection.offer(for: mediaConstraints) { [weak self] (rtcSessionDescription, error) in
            guard let _self = self else { return }
            guard error == nil else { _self.delegate?.createRestartResult(.failure(error!)); return }
            guard let rtcSessionDescription = rtcSessionDescription else {
                _self.delegate?.createRestartResult(.failure(_self.makeError(message: "rtcSessionDescription is nil, which is unexpected")))
                return
            }
            os_log("☎️ Created an RTCSessionDescription (%{public}@) for restarting", log: log, type: .info, rtcSessionDescription.type.debugDescription)

            guard peerConnection.signalingState == .stable else {
                /// if we are not in stable, we shouldn't be creating an offer or an answer --> we don't set anything
                return
            }

            // Filter the description
            let filteredLocalRTCSessionDescription: RTCSessionDescription
            do {
                let filteredSdp = try _self.filterSdpDescriptionCodec(sessionDescription: rtcSessionDescription.sdp)
                filteredLocalRTCSessionDescription = RTCSessionDescription(type: rtcSessionDescription.type, sdp: filteredSdp)
            } catch {
                _self.delegate?.createRestartResult(.failure(error))
                return
            }

            assert(filteredLocalRTCSessionDescription.type == .offer)

            if case .gatherOnce = _self.gatheringPolicy {
                // We start the ICE gathering by setting the local description. We store the completion handler so as to call it later, from one of the delegate methods.
                _self.currentCompletion = .restart
            }
            _self.peerConnection?.setLocalDescription(filteredLocalRTCSessionDescription) { (error) in
                guard error == nil else {
                    _self.delegate?.createRestartResult(.failure(error!))
                    _self.currentCompletion = nil
                    return
                }
                if case .gatherContinually = _self.gatheringPolicy {
                    _self.createRestartResult()
                }
            }
            if case .gatherOnce = _self.gatheringPolicy {
                _self.resetGatheringState()
            }
        }
    }

    func createRestartOffer() {
        guard let peerConnection = peerConnection else { assertionFailure(); return }
        guard let delegate = delegate else { assertionFailure(); return }

        switch peerConnection.signalingState {
        case .haveLocalOffer:
            /// rollback to a stable set before creating the new restart offer
            rollback()
        case .haveRemoteOffer:
            /// we received a remote offer if we are the offer sender, rollback and send a new offer, otherwise juste wait for the answer process to finish
            if delegate.shouldISendTheOfferToCallParticipant() {
                rollback()
            } else {
                return
            }
        default:
            break
        }

        reconnectOfferCounter += 1
        peerConnection.restartIce()
        internalRestartOffer()
    }

    func handleReceivedRestartSdp(sessionDescriptionType: String,
                                  sessionDescription: String,
                                  reconnectCounter: Int,
                                  peerReconnectCounterToOverride: Int) {
        guard let peerConnection = peerConnection else { assertionFailure(); return }
        guard let delegate = delegate else { assertionFailure(); return }

        os_log("☎️ Received restart offer with %{public}@", log: log, type: .info, String(reconnectCounter))

        let sdpType = RTCSessionDescription.type(for: sessionDescriptionType)
        switch sdpType {
        case .offer:
            guard reconnectCounter >= reconnectAnswerCounter else {
                os_log("☎️ Received restart offer with counter too low %{public}@ vs. %{public}@", log: log, type: .info, String(reconnectCounter), String(reconnectAnswerCounter))
                return
            }
            switch peerConnection.signalingState {
            case .haveRemoteOffer:
                os_log("☎️ Received restart offer while already having one --> rollback", log: log, type: .info)
                /// rollback to a stable set before handling the new restart offer
                rollback()
            case .haveLocalOffer:
                /// we already sent an offer
                /// if we are the offer sender, do nothing, otherwise rollback and process the new offer
                if delegate.shouldISendTheOfferToCallParticipant() {
                    if peerReconnectCounterToOverride == reconnectOfferCounter {
                        os_log("☎️ Received restart offer while already having created an offer. It specifies to override my current offer --> rollback", log: log, type: .info)
                        rollback()
                    } else {
                        os_log("☎️ Received restart offer while already having created an offer. I am the offerer --> ignore this new offer", log: log, type: .info)
                        return
                    }
                } else {
                    os_log("☎️ Received restart offer while already having created an offer. I am not the offerer --> rollback", log: log, type: .info)
                    rollback()
                }
            default: break
            }

            reconnectAnswerCounter = reconnectCounter

            setRemoteDescription(sessionDescriptionType: sessionDescriptionType, sessionDescription: sessionDescription) { error in
                guard error == nil else {
                    os_log("Could not set remote description for handling reconnect call message: %{public}@", log: self.log, type: .fault, error!.localizedDescription)
                    assertionFailure()
                    return
                }
            }

            os_log("☎️ Creating answer for restart offer", log: log, type: .info)
            peerConnection.restartIce()
            internalRestartAnwser()

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

            setRemoteDescription(sessionDescriptionType: sessionDescriptionType, sessionDescription: sessionDescription) { error in
                guard error == nil else {
                    os_log("Could not set remote description for handling reconnect call message", log: self.log, type: .fault)
                    assertionFailure()
                    return
                }
            }
        default:
            return
        }

    }

    private func resetGatheringState() {
        guard case .gatherOnce = gatheringPolicy else { assertionFailure(); return }
        queueForIceGathering.sync { [weak self] in
            self?.iceGatheringCompletedWasCalled = false
        }
        iceCandidates.removeAll()
    }

    private func createDataChannel() {
        assert(dataChannelWorker == nil)
        guard let peerConnection = self.peerConnection else {
            os_log("☎️ Cannot create a data channel, there is no peer connection", log: log, type: .fault)
            assertionFailure()
            return
        }
        do {
            self.dataChannelWorker = try DataChannelWorker(with: peerConnection)
            self.dataChannelWorker?.delegate = self
        } catch(let error) {
            os_log("Could not create DataChannelWorker: %{public}@", log: log, type: .fault, error.localizedDescription)
            return
        }
    }

    func addIceCandidate(iceCandidate: RTCIceCandidate) {
        os_log("☎️❄️ addIceCandidate called", log: self.log, type: .info)
        if readyToForwardRemoteIceCandidates {
            guard let peerConnection = peerConnection else { assertionFailure(); return }
            peerConnection.add(iceCandidate) { error in
                guard error == nil else {
                    os_log("☎️❄️ Failed to add remote ICE candidate: %{public}@", log: self.log, type: .fault, error!.localizedDescription)
                    return
                }
            }
        } else {
            os_log("☎️❄️ Not ready to forward remote ICE candidates, add candidate to pending list (count %{public}@)", log: self.log, type: .info, String(pendingRemoteIceCandidates.count))
            pendingRemoteIceCandidates.append(iceCandidate)
        }
    }

    func removeIceCandidates(iceCandidates: [RTCIceCandidate]) {
        os_log("☎️❄️ removeIceCandidates called", log: self.log, type: .info)
        if readyToForwardRemoteIceCandidates {
            guard let peerConnection = peerConnection else { assertionFailure(); return }
            peerConnection.remove(iceCandidates)
        } else {
            os_log("☎️❄️ Not ready to forward remote ICE candidates, remove candidates from pending list (count %{public}@)", log: self.log, type: .info, String(pendingRemoteIceCandidates.count))
            pendingRemoteIceCandidates.removeAll { iceCandidates.contains($0) }
        }
    }

    // MARK: Implementing RTCPeerConnectionDelegate

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        os_log("☎️ RTCPeerConnection didChange RTCSignalingState: %{public}@", log: log, type: .info, stateChanged.debugDescription)
        if stateChanged == .stable && connectionState == .connected {
            OperationQueue.main.addOperation { [weak self] in
                self?.delegate?.peerConnectionStateDidChange(newState: .connected)
            }
        }

        debugPrint(stateChanged)
    }


    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        os_log("☎️ RTCPeerConnection didChange RTCPeerConnectionState: %{public}@", log: log, type: .info, newState.debugDescription)
    }


    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        os_log("☎️ RTCPeerConnection didAdd stream", log: log, type: .info)
        debugPrint(stream)
    }


    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        os_log("☎️ RTCPeerConnection didRemove stream", log: log, type: .info)
        debugPrint(stream)
    }


    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        os_log("☎️ RTCPeerConnection didChange RTCIceConnectionState state: %{public}@", log: log, type: .info, newState.debugDescription)
        self.connectionState = newState
        OperationQueue.main.addOperation { [weak self] in
            self?.delegate?.peerConnectionStateDidChange(newState: newState)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        os_log("☎️❄️ Peer Connection Ice Gathering State changed to: %{public}@", log: log, type: .info, newState.debugDescription)
        guard case .gatherOnce = gatheringPolicy else { return }
        switch newState {
        case .new:
            break
        case .gathering:
            resetGatheringState()
        case .complete:
            if iceCandidates.isEmpty && connectionState == nil {
                os_log("☎️❄️ No ICE candidates found", log: log, type: .info)
            } else {
                // We have all we need to send the local description to the caller.
                os_log("☎️❄️ Calls completed ICE Gathering with %{public}@ candidates", log: self.log, type: .info, String(self.iceCandidates.count))
                queueForIceGathering.async { [weak self] in
                    self?.iceGatheringCompleted()
                }
            }
        @unknown default:
            assertionFailure()
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        os_log("☎️❄️ Peer Connection didGenerate RTCIceCandidate", log: log, type: .info)
        switch gatheringPolicy {
        case .gatherOnce:
            iceCandidates.append(candidate)
            if iceCandidates.count == 1 { /// At least one candidate, we wait one second and hope that the other candidate will be added.
                let queue = DispatchQueue(label: "Sleeping queue", qos: .userInitiated)
                queue.asyncAfter(deadline: .now() + .seconds(2)) { [weak self] in
                    guard let _self = self else { return }
                    os_log("☎️❄️ Calls ICE Gathering after waiting with %{public}@ candidates", log: _self.log, type: .info, String(_self.iceCandidates.count))
                    self?.queueForIceGathering.async {
                        self?.iceGatheringCompleted()
                    }
                }
            }
        case .gatherContinually:
            print(candidate)
            delegate?.sendNewIceCandidateMessage(candidate: candidate)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        os_log("☎️❄️ Peer Connection didRemove RTCIceCandidate", log: log, type: .info)
        switch gatheringPolicy {
        case .gatherOnce:
            iceCandidates.removeAll { candidates.contains($0) }
        case .gatherContinually:
            delegate?.sendRemoveIceCandidatesMessages(candidates: candidates)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        os_log("☎️ Peer Connection didOpen RTCDataChannel", log: log, type: .info)
        debugPrint(dataChannel)
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        os_log("☎️ Peer Connection should negociate RTCPeerConnection", log: log, type: .info)
        guard case .gatherOnce = gatheringPolicy else { return }
        resetGatheringState()
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChangeLocalCandidate local: RTCIceCandidate, remoteCandidate remote: RTCIceCandidate, lastReceivedMs lastDataReceivedMs: Int32, changeReason reason: String) {
        os_log("☎️❄️ Peer Connection didChangeLocalCandidate: %{public}@", log: log, type: .info, reason)
    }


    func drainRemoteIceCandidates() {
        guard case .gatherContinually = gatheringPolicy else { return }
        guard readyToForwardRemoteIceCandidates else { return }
        guard !pendingRemoteIceCandidates.isEmpty else { return }
        os_log("☎️❄️ Drain remote %{public}@ ICE candidate(s)", log: self.log, type: .info, String(pendingRemoteIceCandidates.count))
        for iceCandidate in pendingRemoteIceCandidates {
            addIceCandidate(iceCandidate: iceCandidate)
        }
        pendingRemoteIceCandidates.removeAll()
    }

    private func createAnswerResult() {
        guard let localDescription = peerConnection?.localDescription else { assertionFailure(); return }
        let sessionDescriptionType = RTCSessionDescription.string(for: localDescription.type)
        delegate?.createAnswerResult(
            .success((sessionDescriptionType: sessionDescriptionType,
                      sessionDescription: localDescription.sdp)))
        self.readyToForwardRemoteIceCandidates = true
    }

    private func createOfferResult() {
        guard let turnUserName = self.turnUserName,
              let turnPassword = self.turnPassword else {
                  assertionFailure()
                  return
              }
        guard let localDescription = peerConnection?.localDescription else { assertionFailure(); return }
        let sessionDescriptionType = RTCSessionDescription.string(for: localDescription.type)
        delegate?.createOfferResult(
            .success((sessionDescriptionType: sessionDescriptionType,
                      sessionDescription: localDescription.sdp,
                      turnUserName: turnUserName,
                      turnPassword: turnPassword,
                      turnServersURL: turnServersURL)))
        self.readyToForwardRemoteIceCandidates = true
    }

    private func createRestartResult() {
        guard let localDescription = peerConnection?.localDescription else { assertionFailure(); return }
        let sessionDescriptionType = RTCSessionDescription.string(for: localDescription.type)
        let reconnectCounter: Int
        let peerReconnectCounterToOverride: Int
        if case .offer = localDescription.type {
            reconnectCounter = reconnectOfferCounter
            peerReconnectCounterToOverride = reconnectAnswerCounter
        } else {
            assert(localDescription.type == .answer)
            reconnectCounter = reconnectAnswerCounter
            peerReconnectCounterToOverride = -1
        }

        let reconnectCallMessage: ReconnectCallMessageJSON
        do {
            reconnectCallMessage = try ReconnectCallMessageJSON(
                sessionDescriptionType: sessionDescriptionType,
                sessionDescription: localDescription.sdp,
                reconnectCounter: reconnectCounter,
                peerReconnectCounterToOverride: peerReconnectCounterToOverride)
        } catch {
            os_log("☎️ Could not create ReconnectCallMessageJSON: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
            self.delegate?.createRestartResult(.failure(error))
            return
        }
        os_log("☎️ Build a ReconnectCallMessageJSON: %{public}@", log: log, type: .info, reconnectCallMessage.sessionDescriptionType)
        self.delegate?.createRestartResult(.success(reconnectCallMessage))

    }

    private func iceGatheringCompleted() {
        guard !iceGatheringCompletedWasCalled else { return }
        iceGatheringCompletedWasCalled = true

        os_log("☎️ ICE gathering is completed", log: log, type: .info)

        guard let currentCompletion = self.currentCompletion else { return }
        switch currentCompletion {
        case .answer:
            createAnswerResult()
        case .offer:
            createOfferResult()
        case .restart:
            createRestartResult()
        }
        self.currentCompletion = nil
    }


    // MARK: CallDataChannelWorkerDelegate and related methods

    func dataChannel(didReceiveMessage message: WebRTCDataChannelMessageJSON) {
        OperationQueue.main.addOperation { [weak self] in
            guard let self_ = self else { return }
            self_.delegate?.dataChannel(of: self_, didReceiveMessage: message)
        }
    }

    func dataChannel(didChangeState state: RTCDataChannelState) {
        OperationQueue.main.addOperation { [weak self] in
            guard let self_ = self else { return }
            self_.delegate?.dataChannel(of: self_, didChangeState: state)
        }
    }

    func sendDataChannelMessage(_ message: WebRTCDataChannelMessageJSON) throws {
        try dataChannelWorker?.sendDataChannelMessage(message)
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

fileprivate extension RTCIceCandidate {
    var toJSON: IceCandidateJSON {
        IceCandidateJSON(sdp: sdp, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
    }
}


fileprivate extension RTCPeerConnection {

    func addOlvidTracks(factory: RTCPeerConnectionFactory) {
        let streamId = "audioStreamId"
        let audioTrack = createAudioTrack(factory: factory)
        self.add(audioTrack, streamIds: [streamId])

    }

    private func createAudioTrack(factory: RTCPeerConnectionFactory) -> RTCAudioTrack {
        let audioConstrains = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = factory.audioSource(with: audioConstrains)
        let audioTrack = factory.audioTrack(with: audioSource, trackId: "audio0")
        audioTrack.isEnabled = true
        return audioTrack
    }

}


// MARK: - Utils for filtering description

extension WebrtcPeerConnectionHolder {

    private func filterSdpDescriptionCodec(sessionDescription: String) throws -> String {

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
        // The filteredLines array contains all the lines of the filetered description
        for line in filteredLines {
            debugPrint(line)
        }
        let filteredSessionDescription = filteredLines.joined(separator: "\r\n").appending("\r\n")
        return filteredSessionDescription
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
        guard let peerConnection = self.peerConnection else { return }
        let audioTracks = peerConnection.transceivers.compactMap { return $0.sender.track as? RTCAudioTrack }
        audioTracks.forEach { $0.isEnabled = isEnabled }
    }

    var isAudioTrackMuted: Bool {
        guard self.peerConnection != nil else { return false }
        return !isAudioEnabled
    }

    /// We consider that audio is enabled as soon as at least one audio track is enabled
    var isAudioEnabled: Bool {
        guard let peerConnection = self.peerConnection else { return false }
        var res = false
        let audioTracks = peerConnection.transceivers.compactMap { return $0.sender.track as? RTCAudioTrack }
        res = audioTracks.contains(where: { $0.isEnabled })
        return res
    }

}
