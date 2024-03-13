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
import CallKit
import AVFoundation
import os.log
import ObvTypes
import ObvUICoreData
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif


protocol OlvidCallManagerDelegate: AnyObject {
    func callWasAdded(callManager: OlvidCallManager, call: OlvidCall) async
    func callWasRemoved(callManager: OlvidCallManager, removedCall: OlvidCall, callStillInProgress: OlvidCall?) async
}


actor OlvidCallManager {
    
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "OlvidCallManager")

    /// Allows to let the system know about any local user actions (i.e., *not* out-of-band notifications that have happened).
    /// When using CallKit, this holds the ``CXCallController``.
    /// The second important class is the ``CallProviderHolder`` at the ``CallProviderDelegate`` level.
    private let callControllerHolder = CallControllerHolder()
    private var calls = [OlvidCall]()
    /// Stores ICE candidates received for a call that cannot be found yet. They will be used as soon as the call is added to the list of calls.
    private var receivedIceCandidatesStoredForLater = [UUID: [(iceCandidate: IceCandidateJSON, userId: OlvidUserId)]]()

    /// We keep a weak reference to the one (and only) ``ObvPeerConnectionFactory``. All ongoing ``OlvidCall`` keep a strong pointer to it, allowing to keep in memory and to re-use the same factory in case
    /// we create a second call while a call already exists. Once the last call is deallocated, the fact that we only keep a weak reference allows to make sure the factory is deallocated too.
    private weak var factory: ObvPeerConnectionFactory?

    private weak var delegate: OlvidCallManagerDelegate?
    
    nonisolated
    func setNCXCallControllerDelegate(_ delegate: NCXCallControllerDelegate) {
        callControllerHolder.setNCXCallControllerDelegate(delegate)
    }
    
    
    func setDelegate(to newDelegate: OlvidCallManagerDelegate) {
        self.delegate = newDelegate
    }
    
    
    /// Adds a call to the array of active calls.
    /// - Parameter call: The call  to add.
    private func addCall(_ call: OlvidCall) {
        os_log("☎️ Adding call %{public}@", log: Self.log, type: .info, call.debugDescription)
        assert(delegate != nil)
        calls.append(call)
        Task { await delegate?.callWasAdded(callManager: self, call: call) }
        // The call has been added to the list of calls, we can process the ICE candidate saved for later.
        os_log("☎️❄️ Looking for ICE candidates saved for later for call %{public}@", log: Self.log, type: .info, call.uuidForWebRTC.uuidString)
        if let candidates = receivedIceCandidatesStoredForLater.removeValue(forKey: call.uuidForWebRTC), !candidates.isEmpty {
            os_log("☎️❄️ Found %{public}d ICE saved for later for call %{public}@", log: Self.log, type: .info, candidates.count, call.uuidForWebRTC.uuidString)
            Task {
                for candidate in candidates {
                    do {
                        os_log("☎️❄️ Processing an ICE candidate saved for later for call %{public}@", log: Self.log, type: .info, call.uuidForWebRTC.uuidString)
                        try await call.processIceCandidatesJSON(iceCandidate: candidate.iceCandidate, participantId: candidate.userId)
                    } catch {
                        os_log("☎️❄️ Failed to process an ICE candidate saved for later %{public}@", log: Self.log, type: .error, error.localizedDescription)
                        assertionFailure() // Continue anyway
                    }
                }
            }
        }
    }
    
    
    func createIncomingCall(uuidForCallKit: UUID, uuidForWebRTC: UUID, contactIdentifier: ObvContactIdentifier, startCallMessage: StartCallMessageJSON, rtcPeerConnectionQueue: OperationQueue, callDelegate: OlvidCallDelegate) async throws -> OlvidCall {
        let factory = self.factory ?? ObvPeerConnectionFactory()
        self.factory = factory
        let incomingCall = try await OlvidCall.createIncomingCall(
            callIdentifierForCallKit: uuidForCallKit,
            uuidForWebRTC: uuidForWebRTC,
            callerId: contactIdentifier,
            startCallMessage: startCallMessage,
            rtcPeerConnectionQueue: rtcPeerConnectionQueue, 
            factory: factory,
            delegate: callDelegate)
        addCall(incomingCall)
        return incomingCall
    }

    
    /// Removes a call from the array of active calls if it exists.
    /// - Parameter call: The call to remove.
    private func removeCall(_ call: OlvidCall) {
        os_log("☎️ Remove call %{public}@", log: Self.log, type: .info, call.debugDescription)
        guard let index = calls.firstIndex(where: { $0 === call }) else { return }
        calls.remove(at: index)
        let callStillInProgress = calls.first(where: { !$0.state.isFinalState })
        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await delegate?.callWasRemoved(callManager: self, removedCall: call, callStillInProgress: callStillInProgress)
        }
    }


    /// Returns the call with the specified UUID if it exists.
    /// - Parameter uuid: The call's unique identifier.
    /// - Returns: The call with the specified UUID if it exists, otherwise `nil`.
    private func callWithCallIdentifierForCallKit(_ uuid: UUID) -> OlvidCall? {
        os_log("☎️ Looking for call with uuidForCallKit %{public}@", log: Self.log, type: .info, uuid.debugDescription)
        guard let index = calls.firstIndex(where: { $0.uuidForCallKit == uuid }) else { return nil }
        return calls[index]
    }

    
    private func callWithCallIdentifierForWebRTC(_ uuid: UUID) -> OlvidCall? {
        os_log("☎️ Looking for call with uuidForWebRTC %{public}@", log: Self.log, type: .info, uuid.debugDescription)
        guard let index = calls.firstIndex(where: { $0.uuidForWebRTC == uuid }) else { return nil }
        return calls[index]
    }
    
    
    var someCallIsInProgress: Bool {
        let inProgressCall = calls.first(where: { !$0.state.isFinalState })
        return inProgressCall != nil
    }
    
}


// MARK: - ICE candidates stored for later

extension OlvidCallManager {
    
    func processICECandidateForCall(uuidForWebRTC: UUID, iceCandidate: IceCandidateJSON, contact: OlvidUserId) async throws {
        if let call = callWithCallIdentifierForWebRTC(uuidForWebRTC) {
            os_log("☎️❄️ Process IceCandidateJSON message for call %{public}@", log: Self.log, type: .info, call.uuidForWebRTC.uuidString)
            try await call.processIceCandidatesJSON(iceCandidate: iceCandidate, participantId: contact)
        } else {
            os_log("☎️❄️ Received new remote ICE Candidates for a call %{public}@ that does not exists yet: we save it for later.", log: Self.log, type: .info, uuidForWebRTC.uuidString)
            saveICECandidateForLater(uuidForWebRTC: uuidForWebRTC, iceCandidate: iceCandidate, contact: contact)
        }
    }
    
    
    private func saveICECandidateForLater(uuidForWebRTC: UUID, iceCandidate: IceCandidateJSON, contact: OlvidUserId) {
        os_log("☎️❄️ Saving an ICE candidate for later for call %{public}@", log: Self.log, type: .info, uuidForWebRTC.uuidString)
        var candidates = receivedIceCandidatesStoredForLater[uuidForWebRTC] ?? []
        candidates += [(iceCandidate, contact)]
        receivedIceCandidatesStoredForLater[uuidForWebRTC] = candidates
    }
    

    /// Called when an ICE candidate previously received (and saved for later)  should actually be discarded. In that case, we remove it from the list of candidates saved for later.
    private func removeIceCandidatesMessageSavedForLater(uuidForWebRTC: UUID, message: RemoveIceCandidatesMessageJSON) {
        var candidates = receivedIceCandidatesStoredForLater[uuidForWebRTC] ?? []
        candidates.removeAll { message.candidates.contains($0.0) }
        receivedIceCandidatesStoredForLater[uuidForWebRTC] = candidates
    }
    
}


// MARK: - Process JSON messages received from remote users

extension OlvidCallManager {
    
    func processNewParticipantOfferMessageJSON(_ newParticipantOffer: NewParticipantOfferMessageJSON, uuidForWebRTC: UUID, contact: OlvidUserId) async throws {
        
        guard let incomingCall = callWithCallIdentifierForWebRTC(uuidForWebRTC) else {
            throw ObvError.callNotFound
        }
        
        guard incomingCall.direction == .incoming else {
            assertionFailure()
            throw ObvError.expectingAnIncomingCall
        }
        
        try await incomingCall.processNewParticipantOfferMessageJSONFromContact(contact, newParticipantOffer)
        
    }
    
    
    func processHangedUpMessage(_ hangedUpMessage: HangedUpMessageJSON, uuidForWebRTC: UUID, contact: OlvidUserId) async throws -> (call: OlvidCall, report: CallReport?) {
        
        guard let call = callWithCallIdentifierForWebRTC(uuidForWebRTC) else {
            throw ObvError.callNotFound
        }

        guard !call.state.isFinalState else { return (call, nil) }

        let callStateWasInitial = (call.state == .initial)
        let callStateWasRinging = (call.state == .ringing)

        let participantInfo = try await call.callParticipantDidHangUp(participantId: contact)

        let callReport: CallReport?
        if callStateWasInitial && call.direction == .incoming {
            callReport = .missedIncomingCall(caller: participantInfo, participantCount: call.initialParticipantCount)
        } else if callStateWasRinging && call.direction == .outgoing {
            callReport = .unansweredOutgoingCall(with: [participantInfo])
        } else {
            callReport = nil
        }
        
        if call.state.isFinalState {
           removeCall(call)            
        }

        return (call, callReport)
        
    }
    
    
    func processRingingMessageJSON(uuidForWebRTC: UUID, contact: OlvidUserId) async {
        
        guard let outgoingCall = callWithCallIdentifierForWebRTC(uuidForWebRTC) else {
            // No need to throw for a ringing message
            return
        }
        
        await outgoingCall.processRingingMessageJSONFromContact(contact)
        
    }
    
    
    func processRejectCallMessage(_ rejectCallMessage: RejectCallMessageJSON, uuidForWebRTC: UUID, contact: OlvidUserId) async throws -> (outgoingCall: OlvidCall, participantInfo: OlvidCallParticipantInfo?) {
        
        guard let outgoingCall = callWithCallIdentifierForWebRTC(uuidForWebRTC) else {
            throw ObvError.callNotFound
        }

        assert(outgoingCall.direction == .outgoing)
        
        let participantInfo = await outgoingCall.processRejectCallMessageFromContact(contact)

        if outgoingCall.state.isFinalState {
            removeCall(outgoingCall)
        }
        
        return (outgoingCall, participantInfo)
    }
    
    
    func processAnswerCallMessage(_ answerCallMessage: AnswerCallJSON, uuidForWebRTC: UUID, contact: OlvidUserId) async throws ->  (outgoingCall: OlvidCall, participantInfo: OlvidCallParticipantInfo?) {
        
        guard let outgoingCall = callWithCallIdentifierForWebRTC(uuidForWebRTC) else {
            throw ObvError.callNotFound
        }

        let participantInfo = try await outgoingCall.processAnswerCallJSONFromContact(contact, answerCallMessage)

        
        return (outgoingCall, participantInfo)
    }
    
    
    func processBusyMessageJSON(uuidForWebRTC: UUID, contact: OlvidUserId) async throws -> (outgoingCall: OlvidCall, participantInfo: OlvidCallParticipantInfo?) {
        
        guard let outgoingCall = callWithCallIdentifierForWebRTC(uuidForWebRTC) else {
            throw ObvError.callNotFound
        }

        let participantInfo = await outgoingCall.processBusyMessageJSONFromContact(contact)
        
        return (outgoingCall, participantInfo)

    }
    
    
    func processReconnectCallMessageJSON(_ reconnectCallMessage: ReconnectCallMessageJSON, uuidForWebRTC: UUID, contact: OlvidUserId) async throws {
        
        guard let call = callWithCallIdentifierForWebRTC(uuidForWebRTC) else {
            // The message certainly concerns an old call
            return
        }

        try await call.processReconnectCallMessageJSONFromContact(contact, reconnectCallMessage)
        
    }
    
    
    func processNewParticipantAnswerMessageJSON(_ newParticipantAnswer: NewParticipantAnswerMessageJSON, uuidForWebRTC: UUID, contact: OlvidUserId) async throws {
        
        guard let call = callWithCallIdentifierForWebRTC(uuidForWebRTC) else {
            throw ObvError.callNotFound
        }

        try await call.processNewParticipantAnswerMessageJSONFromContact(contact, newParticipantAnswer)
        
    }
    
    
    func processKickMessageJSON(_ kickMessage: KickMessageJSON, uuidForWebRTC: UUID, contact: OlvidUserId) async throws -> (cll: OlvidCall, callReport: CallReport?, cxCallEndedReason: CXCallEndedReason?) {
        
        guard let incomingCall = callWithCallIdentifierForWebRTC(uuidForWebRTC) else {
            throw ObvError.callNotFound
        }

        guard incomingCall.direction == .incoming else {
            assertionFailure()
            throw ObvError.expectingAnIncomingCall
        }

        let (callReport, cxCallEndedReason) = try await incomingCall.processKickMessageJSONFromContact(contact)
        
        assert(incomingCall.state.isFinalState)
        removeCall(incomingCall)

        return (incomingCall, callReport, cxCallEndedReason)
        
    }
    
    
    func processRemoveIceCandidatesMessage(message: RemoveIceCandidatesMessageJSON, uuidForWebRTC: UUID, contact: OlvidUserId) async throws {
        
        if let call = callWithCallIdentifierForWebRTC(uuidForWebRTC) {
            os_log("☎️❄️ Process RemoveIceCandidatesMessageJSON message", log: Self.log, type: .info)
            try await call.removeIceCandidatesJSON(removeIceCandidatesJSON: message, participantId: contact)
        } else {
            os_log("☎️❄️ Received removed remote ICE Candidates for a call that does not exists yet", log: Self.log, type: .info)
            removeIceCandidatesMessageSavedForLater(uuidForWebRTC: uuidForWebRTC, message: message)
        }

    }
    
    
    func processAnsweredOrRejectedOnOtherDeviceMessage(answered: Bool, uuidForWebRTC: UUID, ownedCryptoId: ObvCryptoId) async throws -> (incomingCall: OlvidCall?, callReport: CallReport?, cxCallEndedReason: CXCallEndedReason?) {
        
        os_log("☎️ Process AnsweredOrRejectedOnOtherDeviceMessage", log: Self.log, type: .info)
        
        if let incomingCall = callWithCallIdentifierForWebRTC(uuidForWebRTC) {
            
            assert(incomingCall.direction == .incoming)
            let (callReport, cxCallEndedReason) = await incomingCall.processAnsweredOrRejectedOnOtherDeviceMessage(answered: answered)
            
            assert(incomingCall.state.isFinalState)
            removeCall(incomingCall)
            
            return (incomingCall, callReport, cxCallEndedReason)
            
        } else {
            
            // We expect to rarely arrive here as the CallKit notification should be fast enough
            assertionFailure()
            return (nil, nil, nil)

        }
        
    }
    
}


// MARK: - Processing local user requests

extension OlvidCallManager {
    
    /// Called from the ``CallProviderDelegate.provider(_:perform:)`` delegate method.
    ///
    /// This delegate method was either called because
    /// - the user ended the call from the CallKit UI
    /// - the user ended the call from the in-house UI. In that case, we created a `CXEndCallAction` within this manager
    /// and passed it to the `CallControllerHolder` so as to let the system know about the local user action.
    func localUserWantsToPerform(_ action: CXEndCallAction) async throws -> (call: OlvidCall?, callReport: CallReport?, rejectedOnOtherDeviceMessageJSON: WebRTCMessageJSON?) {
        
        os_log("☎️🔚 Call to localUserWantsToPerform(_ action: CXEndCallAction)", log: Self.log, type: .info)
        
        guard let call = callWithCallIdentifierForCallKit(action.callUUID) else {
            return (nil, nil, nil)
        }

        // Remove the ended call from the app's list of calls.
        os_log("☎️🔚 Removing call from the list of calls", log: Self.log, type: .info)
        removeCall(call)

        let endingIncomingCallInInitialState = (call.direction == .incoming) && (call.state == .initial)
        
        // Trigger the call to be ended via the underlying network service.
        let callReport = await call.endWasRequestedByLocalUser()
        
        let rejectedOnOtherDeviceMessageJSON: WebRTCMessageJSON?
        if endingIncomingCallInInitialState {
            rejectedOnOtherDeviceMessageJSON = try? AnsweredOrRejectedOnOtherDeviceMessageJSON(answered: false).embedInWebRTCMessageJSON(callIdentifier: call.uuidForWebRTC)
        } else {
            rejectedOnOtherDeviceMessageJSON = nil
        }
        
        os_log("☎️🔚 End of call to localUserWantsToPerform(_ action: CXEndCallAction)", log: Self.log, type: .info)

        return (call, callReport, rejectedOnOtherDeviceMessageJSON)

    }
    
    
    /// Called from the ``CallProviderDelegate.provider(_:perform:)`` delegate method.
    /// Returns the `ParticipantInfo` of the caller.
    ///
    /// This delegate method was either called because
    /// - the user accepted an incoming call from the CallKit UI
    /// - the user accepted an incoming call from the in-house UI. In that case, we created a `CXAnswerCallAction` within this manager
    /// and passed it to the `CallControllerHolder` so as to let the system know about the local user action.
    func localUserWantsToPerform(_ action: CXAnswerCallAction) async throws -> (incomingCall: OlvidCall, callerInfo: OlvidCallParticipantInfo?, answeredOnOtherDeviceMessageJSON: WebRTCMessageJSON?) {
        
        os_log("☎️ Call to localUserWantsToPerform %{public}@", log: Self.log, type: .info, action.uuid.uuidString)

        guard let incomingCall = callWithCallIdentifierForCallKit(action.callUUID) else {
            assertionFailure()
            throw ObvError.callNotFound
        }

        let callerInfo = try await incomingCall.localUserWantsToAnswerThisIncomingCall()

        let answeredOnOtherDeviceMessageJSON = try? AnsweredOrRejectedOnOtherDeviceMessageJSON(answered: true).embedInWebRTCMessageJSON(callIdentifier: incomingCall.uuidForWebRTC)

        return (incomingCall, callerInfo, answeredOnOtherDeviceMessageJSON)
        
    }

    
    /// Called from the ``CallProviderDelegate.provider(_:perform:)`` delegate method.
    /// Returns up-to-date ``CXCallUpdate`` so as to update the CallKit UI.
    ///
    /// This delegate method was called as we created a ``CXStartCallAction`` in ``localUserWantsToStartOutgoingCall(ownedCryptoId:contactCryptoIds:ownedIdentityForRequestingTurnCredentials:groupId:rtcPeerConnectionQueue:olvidCallDelegate:)``
    func localUserWantsToPerform(_ action: CXStartCallAction) async throws -> CXCallUpdate {
        
        guard let outgoingCall = callWithCallIdentifierForCallKit(action.callUUID) else {
            assertionFailure()
            throw ObvError.callNotFound
        }

        try await outgoingCall.startOutgoingCall()
        
        let update = await outgoingCall.createUpToDateCXCallUpdate()
        return update
        
    }
    
    
    func localUserWantsToSetMuteSelf(_ action: CXSetMutedCallAction) async throws {
        
        guard let call = callWithCallIdentifierForCallKit(action.callUUID) else {
            // As this is sometimes called by CallKit when hanging up a call, we simply return here.
            return
        }
        
        try await call.setMuteSelfForOtherParticipants(muted: action.isMuted)
        
    }
    
}


// MARK: - Automatically ending a call

extension OlvidCallManager {
    
    func incomingCallCannotBeAnsweredBecauseOfDeniedRecordPermission(uuidForCallKit: UUID) async throws -> (incomingCall: OlvidCall?, callReport: CallReport?, WebRTCMessageJSON?) {
        
        guard let incomingCall = callWithCallIdentifierForCallKit(uuidForCallKit) else {
            assertionFailure()
            throw ObvError.callNotFound
        }
        
        let (callReport, _) = try await incomingCall.endBecauseOfDeniedRecordPermission()
        
        if incomingCall.state.isFinalState {
           removeCall(incomingCall)
        } else {
            assertionFailure()
        }
        
        let rejectedOnOtherDeviceMessageJSON = try? AnsweredOrRejectedOnOtherDeviceMessageJSON(answered: false).embedInWebRTCMessageJSON(callIdentifier: incomingCall.uuidForWebRTC)

        return (incomingCall, callReport, rejectedOnOtherDeviceMessageJSON)
        
    }
    
    
    func incomingWasNotAnsweredToAndTimedOut(uuidForCallKit: UUID) async -> (callReport: CallReport?, cxCallEndedReason: CXCallEndedReason?) {
        
        guard let incomingCall = callWithCallIdentifierForCallKit(uuidForCallKit) else {
            assertionFailure()
            return (nil, nil)
        }

        let values = await incomingCall.endIncomingCallAsItTimedOut()

        if incomingCall.state.isFinalState {
           removeCall(incomingCall)
        } else {
            assertionFailure()
        }

        return values
        
    }
    
}


// MARK: - Starting an outgoing call or adding/removeing new participants

extension OlvidCallManager {
    
    /// This is called when the local user wants to start a new outgoing call. This method creates a ``CXStartCallAction`` so as to let the system know about the user action.
    /// Eventually, this manager will be called back from the ``provider(_:perform:CXStartCallAction)`` delegate method of the ``CallProviderDelegate``.
    func localUserWantsToStartOutgoingCall(ownedCryptoId: ObvCryptoId, contactCryptoIds: Set<ObvCryptoId>, ownedIdentityForRequestingTurnCredentials: ObvCryptoId, groupId: GroupIdentifier?, rtcPeerConnectionQueue: OperationQueue, olvidCallDelegate: OlvidCallDelegate) async throws {
        
        guard !contactCryptoIds.isEmpty else {
            assertionFailure()
            throw ObvError.cannotStartOutgoingCallAsNotCalleeWasSpecified
        }
        
        guard !someCallIsInProgress else {
            assertionFailure()
            throw ObvError.cannotStartOutgoingCallWhileAnotherCallIsInProgress
        }

        // Create the outgoing call and add it to the list of calls
        
        let factory = self.factory ?? ObvPeerConnectionFactory()
        self.factory = factory
        let outgoingCall = try await OlvidCall.createOutgoingCall(
            ownedCryptoId: ownedCryptoId,
            contactCryptoIds: contactCryptoIds,
            ownedIdentityForRequestingTurnCredentials: ownedIdentityForRequestingTurnCredentials,
            groupId: groupId,
            rtcPeerConnectionQueue: rtcPeerConnectionQueue, 
            factory: factory,
            delegate: olvidCallDelegate)
        
        addCall(outgoingCall)

        // Create a CXStartCallAction and pass it to the CallControllerHolder to inform it about the local user action
        // Eventually, this manager will be called back in localUserWantsToPerform(_:)

        os_log("☎️ Creating CXStartCallAction for call with uuidForCallKit %{public}@", log: Self.log, type: .info, outgoingCall.uuidForCallKit.uuidString)
        
        let handle = CXHandle(type: .generic, value: outgoingCall.uuidForCallKit.uuidString)
        let startCallAction = CXStartCallAction(call: outgoingCall.uuidForCallKit, handle: handle)
        // We don't set the startCallAction.contactIdentifier as it is not used by CallKit (to the contrary of what the documentation says).
        // Instead, in the CallProviderHolderDelegate, we update the call using a CXCallUpdate.
        startCallAction.isVideo = false
        let transaction = CXTransaction()
        transaction.addAction(startCallAction)
        try await callControllerHolder.callController.request(transaction)

    }
    

    /// This method is actully required by the ``OlvidCallViewActionsProtocol``. It is called when the user wants to add new participants to an existing outgoing call.
    func userWantsToAddParticipantsToExistingCall(uuidForCallKit: UUID, participantsToAdd: Set<ObvCryptoId>) async throws {
        
        guard let outgoingCall = callWithCallIdentifierForCallKit(uuidForCallKit) else {
            throw ObvError.callNotFound
        }
        
        try await outgoingCall.userWantsToAddParticipantsToThisOutgoingCall(participantsToAdd: participantsToAdd)

    }


    /// This method is actully required by the ``OlvidCallViewActionsProtocol``. It is called when the user (caller) wants to remove a participant from an existing outgoing call.
    func userWantsToRemoveParticipant(uuidForCallKit: UUID, participantToRemove: ObvCryptoId) async throws {
        
        guard let outgoingCall = callWithCallIdentifierForCallKit(uuidForCallKit) else {
            throw ObvError.callNotFound
        }

        if outgoingCall.otherParticipants.count <= 1 {
            try await userWantsToEndOngoingCall(uuidForCallKit: uuidForCallKit)
        } else {
            try await outgoingCall.userWantsToRemoveParticipantFromThisOutgoingCall(cryptoId: participantToRemove)
        }
        
    }
    
    
    /// This method is actully required by the ``OlvidCallViewActionsProtocol``. It is called when the user (caller) wants to have a one2one chat with a participant.
    func userWantsToChatWithParticipant(uuidForCallKit: UUID, participant: ObvCryptoId) async throws {
        
        guard let call = callWithCallIdentifierForCallKit(uuidForCallKit) else {
            throw ObvError.callNotFound
        }
        
        try await call.userWantsToChatWithParticipant(participant: participant)
        
    }
    
}


// MARK: - Implementing the OlvidCallViewActionsProtocol for the UI

extension OlvidCallManager {
    
    /// This is called from the in house-UI (``OlvidCallView``) when the user accepts an incoming call.
    /// We first end "all" calls that are not in a finished state, then accept the call.
    func userAcceptedIncomingCall(uuidForCallKit: UUID) async throws {
        
        // End all current calls
        
        let callsToEnd = calls
            .filter({ !$0.state.isFinalState && $0.uuidForCallKit != uuidForCallKit })
            .map({ $0.uuidForCallKit })
        for call in callsToEnd {
            try await userWantsToEndOngoingCall(uuidForCallKit: call)
        }
        
        // Accept the incoming call
        
        os_log("☎️ Creating CXAnswerCallAction for call %{public}@", log: Self.log, type: .info, uuidForCallKit.uuidString)
        guard let incomingCall = callWithCallIdentifierForCallKit(uuidForCallKit) else {
            throw ObvError.callNotFound
        }
        await incomingCall.localUserAcceptedIncomingCallFromInHouseUI()
        let answerCallAction = CXAnswerCallAction(call: uuidForCallKit)
        let transaction = CXTransaction()
        transaction.addAction(answerCallAction)
        try await callControllerHolder.callController.request(transaction)
        
    }
    

    /// Called when the local user taps the reject call button on the in-house UI when receiving an incoming call.
    func userRejectedIncomingCall(uuidForCallKit: UUID) async throws {
        let endCallAction = CXEndCallAction(call: uuidForCallKit)
        let transaction = CXTransaction()
        transaction.addAction(endCallAction)
        try await callControllerHolder.callController.request(transaction)
    }


    /// Called when the user taps the end call button on the in-house UI during an ongoing call (both for incoming and outgoing calls).
    /// This is also called when the user removes the only other participant of an outgoing call
    func userWantsToEndOngoingCall(uuidForCallKit: UUID) async throws {
        os_log("☎️🔚 userWantsToEndOngoingCall %{public}@", log: Self.log, type: .info, uuidForCallKit.uuidString)
        let endCallAction = CXEndCallAction(call: uuidForCallKit)
        let transaction = CXTransaction()
        transaction.addAction(endCallAction)
        try await callControllerHolder.callController.request(transaction)
    }

    
    /// Called when the user taps the mute (or unmute) call button on the in-house UI during an ongoing call (both for incoming and outgoing calls).
    func userWantsToSetMuteSelf(uuidForCallKit: UUID, muted: Bool) async throws {
        os_log("☎️ userWantsToMuteSelf %{public}@", log: Self.log, type: .info, uuidForCallKit.uuidString)
        let mutedCallAction = CXSetMutedCallAction(call: uuidForCallKit, muted: muted)
        let transaction = CXTransaction()
        transaction.addAction(mutedCallAction)
        try await callControllerHolder.callController.request(transaction)
    }

    
    func userWantsToStartOrStopVideoCamera(uuidForCallKit: UUID, start: Bool, preferredPosition: AVCaptureDevice.Position) async throws {
        os_log("☎️ userWantsToStartOrStopVideoCamera %{public}@", log: Self.log, type: .info, uuidForCallKit.uuidString)
        guard let call = callWithCallIdentifierForCallKit(uuidForCallKit) else {
            assertionFailure()
            return
        }
        try await call.userWantsToStartOrStopVideoCamera(start: start, preferredPosition: preferredPosition)
    }
    
    
    func callViewDidDisappear(uuidForCallKit: UUID) async {
        os_log("☎️ callViewDidDisappear %{public}@", log: Self.log, type: .info, uuidForCallKit.uuidString)
        guard let call = callWithCallIdentifierForCallKit(uuidForCallKit) else { return }
        await call.callViewDidDisappear()
    }
    
    
    func callViewDidAppear(uuidForCallKit: UUID) async {
        os_log("☎️ callViewDidAppear %{public}@", log: Self.log, type: .info, uuidForCallKit.uuidString)
        guard let call = callWithCallIdentifierForCallKit(uuidForCallKit) else {
            assertionFailure()
            return
        }
        await call.callViewDidAppear()
    }
    
}


// MARK: - Errors

extension OlvidCallManager {
    
    enum ObvError: Error {
        case callNotFound
        case cannotStartOutgoingCallWhileAnotherCallIsInProgress
        case cannotStartOutgoingCallAsNotCalleeWasSpecified
        case expectingAnIncomingCall
    }
    
}
