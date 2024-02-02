/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import CallKit
import PushKit
import WebRTC
import ObvEngine
import ObvTypes
import ObvCrypto
import ObvSettings
import ObvUICoreData


/// Main class of Olvid's VoIP implementation.
///
/// Remark: Subclass of NSObject as this class implements `PKPushRegistryDelegate` which inherits from `NSObjectProtocol`.
///
/// Remark: We do *not* use an external PushRegistryDelegate (as done in Apple sample code). The reason is that, we receiving a pushkit notification
/// using the async delegate method, we need to report the new incoming call to the system immediately (we cannot call any async method or create a Task).
final class CallProviderDelegate: NSObject {
    
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: CallProviderDelegate.self))

    /// Allows to let the system know about any out-of-band notifications that have happened (i.e., *not* local user actions).
    /// When using CallKit, this holds the CXProvider.
    /// The second important class is the ``CallControllerHolder`` at the ``OlvidCallManager`` level.
    private let callProviderHolder = CallProviderHolder()
    private let callManager = OlvidCallManager()
    private let pushKitNotificationSynchronizer = PushKitNotificationSynchronizer()
    private var pkPushRegistry: PKPushRegistry?
    private let obvEngine: ObvEngine
    private let rtcPeerConnectionQueue = OperationQueue.createSerialQueue(name: "CallProviderDelegate serial queue common to all OlvidCallParticipantPeerConnectionHolder")
    private let callAudioPlayer = OlvidCallAudioPlayer()

    private var notificationTokens = [NSObjectProtocol]()

    private let queueForPostingNotifications = DispatchQueue(label: "CallProviderDelegate queue for posting notifications")

    init(obvEngine: ObvEngine) {
        self.obvEngine = obvEngine
        super.init()
        self.callProviderHolder.setDelegate(self) // CallProviderHolderDelegate
        self.callManager.setNCXCallControllerDelegate(self.callProviderHolder.ncxCallControllerDelegate)
        Task { [weak self] in
            guard let self else { return }
            await callManager.setDelegate(to: self)
        }
    }
    
    deinit {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    
    func performPostInitialization() {
        listenToNotifications()
        registerToPushKitNotifications()
    }
    
    
    private func listenToNotifications() {
        
        // Internal notifications

        notificationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeNewWebRTCMessageWasReceived { (webrtcMessage, fromOlvidUser, messageIdentifierFromEngine) in
                Task { [weak self] in
                    await self?.processReceivedWebRTCMessage(
                        messageType: webrtcMessage.messageType,
                        serializedMessagePayload: webrtcMessage.serializedMessagePayload,
                        uuidForWebRTC: webrtcMessage.callIdentifier,
                        fromOlvidUser: fromOlvidUser,
                        messageIdentifierFromEngine: messageIdentifierFromEngine)
                }
            },
            ObvMessengerInternalNotification.observeUserWantsToCallAndIsAllowedTo { (ownedCryptoId, contactCryptoIds, ownedIdentityForRequestingTurnCredentials, groupId) in
                Task { [weak self] in await self?.processUserWantsToCallNotification(ownedCryptoId: ownedCryptoId, contactCryptoIds: contactCryptoIds, ownedIdentityForRequestingTurnCredentials: ownedIdentityForRequestingTurnCredentials, groupId: groupId) }
            },
        ])
        
    }
    
    
    private func registerToPushKitNotifications() {
        guard self.pkPushRegistry == nil else { assertionFailure(); return }
        pkPushRegistry = PKPushRegistry(queue: nil)
        pkPushRegistry?.delegate = self // PKPushRegistryDelegate
        pkPushRegistry?.desiredPushTypes = [.voIP]
    }
    
}


// MARK: - Implementing PKPushRegistryDelegate

extension CallProviderDelegate: PKPushRegistryDelegate {
    
    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        let voipToken = pushCredentials.token
        os_log("☎️✅ We received a voip notification token: %{public}@", log: Self.log, type: .info, voipToken.hexString())
        Task {
            await ObvPushNotificationManager.shared.setCurrentVoipToken(to: voipToken)
            await ObvPushNotificationManager.shared.requestRegisterToPushNotificationsForAllActiveOwnedIdentities()
        }
    }
    
    
    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        os_log("☎️✅❌ Push Registry did invalidate push token", log: Self.log, type: .info)
        Task {
            await ObvPushNotificationManager.shared.setCurrentVoipToken(to: nil)
            await ObvPushNotificationManager.shared.requestRegisterToPushNotificationsForAllActiveOwnedIdentities()
        }
    }

    
    /// Remark: We do *not* use the async version of the this delegate method, not the async version of ``reportNewIncomingCall(with:update:completion:)`` as we encountered countless issues with them (in particular, when in the background).
    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {

        os_log("☎️✅ We received a voip notification", log: Self.log, type: .info)
        
        assert(ObvMessengerSettings.VoIP.receiveCallsOnThisDevice, "When setting receiveCallsOnThisDevice to false, we should have removed the VoIP token from the server (and thus we should not receive this notification)")
        
        guard let encryptedNotification = ObvEncryptedPushNotification(dict: payload.dictionaryPayload) else {
            os_log("☎️ Could not extract encrypted notification", log: Self.log, type: .fault)
            reportFakeNewIncomingCall()
            return
        }
         
        // We notify the discussions coordinator.
        // Eventually the encrypted notification will be decrypted and sent back to us.
        
        os_log("☎️ We request a decryption of the encrypted notification", log: Self.log, type: .info)

        ObvMessengerInternalNotification.newObvEncryptedPushNotificationWasReceivedViaPushKitNotification(encryptedNotification: encryptedNotification)
            .postOnDispatchQueue()

        // The incoming call UUID is derived from the message identifier from engine of the received pushkit notification
        
        let callIdentifierForCallKit = encryptedNotification.messageIdFromServer.deterministicUUID

        // Get a "fake" CXCallUpdate describing the incoming call. It will be updated once we receive the result of the decryption of the notification.
        
        let initalUpdate = CXCallUpdate.createForIncomingCallUntilStartCallMessageIsAvailable(callIdentifierForCallKit: callIdentifierForCallKit)

        // Report the incoming call to the system.
        // Do so before creating an incoming call so as to make sure reporting the call did not throw.
        // Calls may be denied for various legitimate reasons. See CXErrorCodeIncomingCallError.
        
        os_log("☎️✅ We will report new incoming call to the system", log: Self.log, type: .info)

        callProviderHolder.provider.reportNewIncomingCall(with: callIdentifierForCallKit, update: initalUpdate) { [weak self] error in
            
            if let error {
                os_log("☎️✅❌ We failed to report an incoming call: %{public}@", log: Self.log, type: .info, error.localizedDescription)
                DispatchQueue.main.async {
                    completion()
                }
                assertionFailure()
                return
            }
            
            Task { [weak self] in
                DispatchQueue.main.async {
                    completion()
                }
                await self?.didReportNewIncomingCallToCallKit(encryptedNotification: encryptedNotification, callIdentifierForCallKit: callIdentifierForCallKit)
            }
            
        }

    }
    
    
    /// Called when we fail to recover the `ObvEncryptedPushNotification` when receiving a `PushKit` notification.
    /// Since this "never" happens, we just do what it takes to prevent the system from crashing the app.
    private func reportFakeNewIncomingCall() {
        let fakeUUIDForCallKit = UUID()
        let fakeUpdate = CXCallUpdate.createForIncomingCallUntilStartCallMessageIsAvailable(callIdentifierForCallKit: fakeUUIDForCallKit)
        callProviderHolder.provider.reportNewIncomingCall(with: fakeUUIDForCallKit, update: fakeUpdate) { _ in assertionFailure() }
    }
    
    
    /// Called after successfully reporting a new incoming call to the system when using `CallKit`.
    private func didReportNewIncomingCallToCallKit(encryptedNotification: ObvEncryptedPushNotification, callIdentifierForCallKit: UUID) async {
        os_log("☎️✅ Did report new incoming call to the system", log: Self.log, type: .info)
        
        // Wait for the (decrypted) start call message allowing to create a proper CXCallUpdate
        
        let callerId: ObvContactIdentifier
        let startCallMessage: StartCallMessageJSON
        let uuidForWebRTC: UUID
        do {
            (callerId, startCallMessage, uuidForWebRTC) = try await pushKitNotificationSynchronizer.waitForStartCallMessage(encryptedNotification: encryptedNotification)
        } catch {
            callProviderHolder.provider.reportCall(with: callIdentifierForCallKit, endedAt: Date(), reason: .failed)
            assertionFailure()
            return
        }
        
        // Create an incoming call and add it to the call manager
        
        os_log("☎️ Creating an incoming OlvidCall", log: Self.log, type: .info)
        
        let incomingCall: OlvidCall
        do {
            incomingCall = try await callManager.createIncomingCall(
                uuidForCallKit: callIdentifierForCallKit,
                uuidForWebRTC: uuidForWebRTC,
                contactIdentifier: callerId,
                startCallMessage: startCallMessage,
                rtcPeerConnectionQueue: rtcPeerConnectionQueue,
                callDelegate: self)
        } catch {
            os_log("☎️ Could not create incoming call: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            callProviderHolder.provider.reportCall(with: callIdentifierForCallKit, endedAt: Date(), reason: .failed)
            assertionFailure()
            return
        }

        // Use the updated call to update the CallKit interface
        
        let update = await incomingCall.createUpToDateCXCallUpdate()
        os_log("☎️ Using the created incoming call to update the CXCallProvider", log: Self.log, type: .info)
        callProviderHolder.provider.reportCall(with: callIdentifierForCallKit, updated: update)
        
    }
    
}


// MARK: - Processing WebRTCMessageJSON messages received from the discussions coordinator

extension CallProviderDelegate {

    /// This method gets called when a `WebRTCMessageJSON` is received by the discussions coordinator. This is in particular called when a start call message is received either through the websocket, 
    /// or when an encrypted notification that we notified from the `PushKitNotificationSynchronizer` was successfuly decrypted.
    /// It is also called when we need to relay a message received on the data channel of an ongoing call. In that case, the `messageIdentifierFromEngine` is `nil`. This cannot happen for a `StartCallMessageJSON`.
    ///
    ///
    ///
    private func processReceivedWebRTCMessage(messageType: WebRTCMessageJSON.MessageType, serializedMessagePayload: String, uuidForWebRTC: UUID, fromOlvidUser: OlvidUserId, messageIdentifierFromEngine: UID?) async {
        
        do {
            
            switch messageType {
            case .startCall:
                guard let messageIdentifierFromEngine else { assertionFailure(); return }
                guard let contactIdentifier = fromOlvidUser.contactIdentifier else { assertionFailure(); return }
                guard ObvMessengerSettings.VoIP.receiveCallsOnThisDevice else {
                    // The local user decided not to receive calls on this device.
                    // If the user has only one device, we reject the call and notify the user that she missed a call due to her settings.
                    // If she has several devices, we do nothing.
                    if try await ownedIdentityHasSeveralDevices(ownedCryptoId: fromOlvidUser.ownCryptoId) {
                        return
                    } else {
                        // Notify the caller that the call is not going to be answered
                        let rejectedMessage = try RejectCallMessageJSON().embedInWebRTCMessageJSON(callIdentifier: uuidForWebRTC)
                        guard let contactID = fromOlvidUser.contactObjectID else { assertionFailure(); return }
                        await newWebRTCMessageToSend(webrtcMessage: rejectedMessage, contactID: contactID, forStartingCall: false)
                        // Notify the local user that a call was missed
                        let caller = OlvidCallParticipantInfo(contactObjectID: contactID, isCaller: true)
                        VoIPNotification.reportCallEvent(callUUID: messageIdentifierFromEngine.deterministicUUID, callReport: .rejectedIncomingCallAsTheReceiveCallsOnThisDeviceSettingIsFalse(caller: caller), groupId: nil, ownedCryptoId: fromOlvidUser.ownCryptoId)
                            .postOnDispatchQueue()
                        return
                    }
                }
                let startCallMessage = try StartCallMessageJSON.jsonDecode(serializedMessagePayload: serializedMessagePayload)
                if ObvUICoreDataConstants.useCallKit {
                    await pushKitNotificationSynchronizer.continuePushKitNotificationProcessing(startCallMessage, messageIdFromServer: messageIdentifierFromEngine, callerId: contactIdentifier, uuidForWebRTC: uuidForWebRTC)
                } else {
                    // Since we are not using CallKit, we don't use manual audio. Note that the CallKit counterpart of this call is made in
                    // ``pushRegistry(_:didReceiveIncomingPushWith:for:)``, thus, prior reporting the call.
                    let uuidForCallKit = messageIdentifierFromEngine.deterministicUUID
                    let incomingCall = try await callManager.createIncomingCall(
                        uuidForCallKit: uuidForCallKit,
                        uuidForWebRTC: uuidForWebRTC,
                        contactIdentifier: contactIdentifier,
                        startCallMessage: startCallMessage,
                        rtcPeerConnectionQueue: rtcPeerConnectionQueue,
                        callDelegate: self)
                    let update = await incomingCall.createUpToDateCXCallUpdate()
                    callProviderHolder.provider.reportNewIncomingCall(with: uuidForCallKit, update: update) { error in
                        if let error {
                            os_log("☎️ Could not report new incoming call: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                            assertionFailure()
                            return
                        }
                    }
                }
            case .answerCall:
                guard !fromOlvidUser.isOwnedIdentity else { assertionFailure(); return }
                let contact = fromOlvidUser
                let answerCallMessage = try AnswerCallJSON.jsonDecode(serializedMessagePayload: serializedMessagePayload)
                try await processAnswerCallMessage(answerCallMessage, uuidForWebRTC: uuidForWebRTC, contact: contact)

            case .rejectCall:
                guard !fromOlvidUser.isOwnedIdentity else { assertionFailure(); return }
                let contact = fromOlvidUser
                let rejectCallMessage = try RejectCallMessageJSON.jsonDecode(serializedMessagePayload: serializedMessagePayload)
                let (outgoingCall, participantInfo) = try await callManager.processRejectCallMessage(rejectCallMessage, uuidForWebRTC: uuidForWebRTC, contact: contact)
                Self.report(call: outgoingCall, report: .rejectedOutgoingCall(from: participantInfo))
                callProviderHolder.provider.reportCall(with: outgoingCall.uuidForCallKit, endedAt: Date(), reason: .unanswered)

            case .hangedUp:
                guard !fromOlvidUser.isOwnedIdentity else { assertionFailure(); return }
                let contact = fromOlvidUser
                let hangedUpMessage = try HangedUpMessageJSON.jsonDecode(serializedMessagePayload: serializedMessagePayload)
                try await processHangedUpMessage(hangedUpMessage, uuidForWebRTC: uuidForWebRTC, contact: contact)

            case .ringing:
                guard !fromOlvidUser.isOwnedIdentity else { assertionFailure(); return }
                let contact = fromOlvidUser
                _ = try RingingMessageJSON.jsonDecode(serializedMessagePayload: serializedMessagePayload)
                await callManager.processRingingMessageJSON(uuidForWebRTC: uuidForWebRTC, contact: contact)

            case .busy:
                guard !fromOlvidUser.isOwnedIdentity else { assertionFailure(); return }
                let contact = fromOlvidUser
                _ = try BusyMessageJSON.jsonDecode(serializedMessagePayload: serializedMessagePayload)
                let (outgoingCall, participantInfo) = try await callManager.processBusyMessageJSON(uuidForWebRTC: uuidForWebRTC, contact: contact)
                Self.report(call: outgoingCall, report: .busyOutgoingCall(from: participantInfo))

            case .reconnect:
                guard !fromOlvidUser.isOwnedIdentity else { assertionFailure(); return }
                let contact = fromOlvidUser
                let reconnectCallMessage = try ReconnectCallMessageJSON.jsonDecode(serializedMessagePayload: serializedMessagePayload)
                try await callManager.processReconnectCallMessageJSON(reconnectCallMessage, uuidForWebRTC: uuidForWebRTC, contact: contact)

            case .newParticipantAnswer:
                guard !fromOlvidUser.isOwnedIdentity else { assertionFailure(); return }
                let contact = fromOlvidUser
                let newParticipantAnswer = try NewParticipantAnswerMessageJSON.jsonDecode(serializedMessagePayload: serializedMessagePayload)
                try await callManager.processNewParticipantAnswerMessageJSON(newParticipantAnswer, uuidForWebRTC: uuidForWebRTC, contact: contact)

            case .newParticipantOffer:
                guard !fromOlvidUser.isOwnedIdentity else { assertionFailure(); return }
                let contact = fromOlvidUser
                let newParticipantOffer = try NewParticipantOfferMessageJSON.jsonDecode(serializedMessagePayload: serializedMessagePayload)
                try await callManager.processNewParticipantOfferMessageJSON(newParticipantOffer, uuidForWebRTC: uuidForWebRTC, contact: contact)

            case .kick:
                guard !fromOlvidUser.isOwnedIdentity else { assertionFailure(); return }
                let contact = fromOlvidUser
                try await processKickMessageJSON(serializedMessagePayload: serializedMessagePayload, uuidForWebRTC: uuidForWebRTC, contact: contact)

            case .newIceCandidate:
                guard !fromOlvidUser.isOwnedIdentity else { assertionFailure(); return }
                let contact = fromOlvidUser
                os_log("☎️❄️ We received new ICE Candidate message: %{public}@", log: Self.log, type: .info, messageType.description)
                let iceCandidate = try IceCandidateJSON.jsonDecode(serializedMessagePayload: serializedMessagePayload)
                try await callManager.processICECandidateForCall(uuidForWebRTC: uuidForWebRTC, iceCandidate: iceCandidate, contact: contact)

            case .removeIceCandidates:
                guard !fromOlvidUser.isOwnedIdentity else { assertionFailure(); return }
                let contact = fromOlvidUser
                let removeIceCandidatesMessage = try RemoveIceCandidatesMessageJSON.jsonDecode(serializedMessagePayload: serializedMessagePayload)
                try await callManager.processRemoveIceCandidatesMessage(message: removeIceCandidatesMessage, uuidForWebRTC: uuidForWebRTC, contact: contact)
                
            case .answeredOrRejectedOnOtherDevice:
                guard fromOlvidUser.isOwnedIdentity else { assertionFailure(); return }
                let answeredOrRejectedOnOtherDeviceMessage = try AnsweredOrRejectedOnOtherDeviceMessageJSON.jsonDecode(serializedMessagePayload: serializedMessagePayload)
                let (incomingCall, callReport, cxCallEndedReason) = try await callManager.processAnsweredOrRejectedOnOtherDeviceMessage(answered: answeredOrRejectedOnOtherDeviceMessage.answered, uuidForWebRTC: uuidForWebRTC, ownedCryptoId: fromOlvidUser.ownCryptoId)
                guard let incomingCall else { return }
                if let cxCallEndedReason {
                    callProviderHolder.provider.reportCall(with: incomingCall.uuidForCallKit, endedAt: Date(), reason: cxCallEndedReason)
                }
                if let callReport {
                    Self.report(call: incomingCall, report: callReport)
                }

            }
            
        } catch {
            if let error = error as? OlvidCallManager.ObvError, error == .callNotFound {
                return
            } else {
                assertionFailure()
                os_log("☎️ Could not parse or process the WebRTCMessageJSON: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            }
        }
        
    }
    
    
    func processKickMessageJSON(serializedMessagePayload: String, uuidForWebRTC: UUID, contact: OlvidUserId) async throws {
        let kickMessage = try KickMessageJSON.jsonDecode(serializedMessagePayload: serializedMessagePayload)
        let (incomingCall, callReport, cxCallEndedReason) = try await callManager.processKickMessageJSON(kickMessage, uuidForWebRTC: uuidForWebRTC, contact: contact)
        if let cxCallEndedReason {
            assert(cxCallEndedReason == .remoteEnded)
            callProviderHolder.provider.reportCall(with: incomingCall.uuidForCallKit, endedAt: Date(), reason: cxCallEndedReason)
        }
        if let callReport {
            Self.report(call: incomingCall, report: callReport)
        }
    }
    
    
    private func processAnswerCallMessage(_ answerCallMessage: AnswerCallJSON, uuidForWebRTC: UUID, contact: OlvidUserId) async throws {
        do {
            let (outgoingCall, participantInfo) = try await callManager.processAnswerCallMessage(answerCallMessage, uuidForWebRTC: uuidForWebRTC, contact: contact)
            Self.report(call: outgoingCall, report: .acceptedOutgoingCall(from: participantInfo))
        } catch {
            os_log("☎️ Failed to answer call: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
            throw error
        }
    }


    private func processHangedUpMessage(_ hangedUpMessage: HangedUpMessageJSON, uuidForWebRTC: UUID, contact: OlvidUserId) async throws {
        
        let (call, missedIncomingCallReport) = try await callManager.processHangedUpMessage(hangedUpMessage, uuidForWebRTC: uuidForWebRTC, contact: contact)
        
        if let missedIncomingCallReport {
            Self.report(call: call, report: missedIncomingCallReport)
        }
        
        if call.state.isFinalState {
            
            // Stop call audio when ending a call in a simulator
            stopAudioWhenNotUsingCallKit()
            
            callProviderHolder.provider.reportCall(with: call.uuidForCallKit, endedAt: Date(), reason: .remoteEnded)
            
        }

    }
    
}


// MARK: - Implementing OlvidCallDelegate

extension CallProviderDelegate: OlvidCallDelegate {
    
    
    /// We leverage the call's state change to let the system know about certain out-of-band notifications that have happened.
    func callDidChangeState(call: OlvidCall, previousState: OlvidCall.State, newState: OlvidCall.State) {

        // Calling reportOutgoingCall(with: UUID, startedConnectingAt: Date?)
        
        switch call.direction {
        case .outgoing:
            if newState == .outgoingCallIsConnecting {
                callProviderHolder.provider.reportOutgoingCall(with: call.uuidForCallKit, startedConnectingAt: Date())
            }
        case .incoming:
            if newState == .userAnsweredIncomingCall {
                callProviderHolder.provider.reportOutgoingCall(with: call.uuidForCallKit, startedConnectingAt: Date())
            }
        }
        
        // Calling reportOutgoingCall(with: UUID, connectedAt: Date?)

        if newState == .callInProgress {
            callProviderHolder.provider.reportOutgoingCall(with: call.uuidForCallKit, connectedAt: Date())
        }
        
        // Notify (allows to show the in-house UI when using CallKit
        
        if call.direction == .incoming && newState == .userAnsweredIncomingCall {
            if call.direction == .incoming && ObvUICoreDataConstants.useCallKit {
                let model = OlvidCallViewController.Model(call: call, manager: callManager)
                VoIPNotification.newCallToShow(model: model)
                    .post()
            } else {
                // The notification was already sent
            }
        }
        
        // Notify if a call was ended
        
        if call.state.isFinalState {
            VoIPNotification.callWasEnded(uuidForCallKit: call.uuidForCallKit)
                .postOnDispatchQueue()
        }
        
        // Play a sound
        
        playSound(call: call, previousState: previousState, newState: newState)
        
    }
    
    
    /// Disconnect sounds are not played in the simulator. For some reason, this dramatically slows down everything.
    private func playSound(call: OlvidCall, previousState: OlvidCall.State, newState: OlvidCall.State) {
        
        switch call.direction {
        case .outgoing:
            if newState == .ringing {
                os_log("☎️ OlvidCall will play sound .ringing", log: Self.log, type: .info)
                callAudioPlayer.play(.ringing)
            } else if newState == .callInProgress && previousState != .callInProgress {
                os_log("☎️ OlvidCall will play sound .connect", log: Self.log, type: .info)
                callAudioPlayer.play(.connect)
            } else if newState == .reconnecting && previousState != .reconnecting {
                callAudioPlayer.play(.reconnecting)
            } else if newState.isFinalState && (previousState == .callInProgress || previousState == .ringing), ObvMessengerConstants.isRunningOnRealDevice {
                os_log("☎️ OlvidCall will play sound .disconnect", log: Self.log, type: .info)
                if !ObvMessengerConstants.targetEnvironmentIsMacCatalyst {
                    // We do not play the disconnect sound under macOS, the timing is too random in practice
                    callAudioPlayer.play(.disconnect)
                } else {
                    callAudioPlayer.stop()
                }
            } else {
                callAudioPlayer.stop()
            }
        case .incoming:
            if newState == .callInProgress && previousState != .callInProgress {
                os_log("☎️ OlvidCall will play sound .connect", log: Self.log, type: .info)
                callAudioPlayer.play(.connect)
            } else if newState == .reconnecting && previousState != .reconnecting {
                callAudioPlayer.play(.reconnecting)
            } else if newState.isFinalState && previousState == .callInProgress, ObvMessengerConstants.isRunningOnRealDevice {
                os_log("☎️ OlvidCall will play sound .disconnect", log: Self.log, type: .info)
                if !ObvMessengerConstants.targetEnvironmentIsMacCatalyst {
                    // We do not play the disconnect sound under macOS, the timing is too random in practice
                    callAudioPlayer.play(.disconnect)
                } else {
                    callAudioPlayer.stop()
                }
            } else {
                callAudioPlayer.stop()
            }
        }
        
    }

    
    func incomingWasNotAnsweredToAndTimedOut(call: OlvidCall) async {
        
        let (callReport, cxCallEndedReason) = await callManager.incomingWasNotAnsweredToAndTimedOut(uuidForCallKit: call.uuidForCallKit)

        if let cxCallEndedReason {
            assert(cxCallEndedReason == .unanswered)
            callProviderHolder.provider.reportCall(with: call.uuidForCallKit, endedAt: Date(), reason: cxCallEndedReason)
        }
        
        if let callReport {
            Self.report(call: call, report: callReport)
        }
        
    }
    
    
    func requestTurnCredentialsForCall(call: OlvidCall, ownedIdentityForRequestingTurnCredentials: ObvCryptoId) async throws -> ObvTurnCredentials {
        return try await obvEngine.getTurnCredentials(ownedCryptoId: ownedIdentityForRequestingTurnCredentials)
    }
    
    
    func newWebRTCMessageToSend(webrtcMessage: ObvUICoreData.WebRTCMessageJSON, contactID: ObvUICoreData.TypeSafeManagedObjectID<ObvUICoreData.PersistedObvContactIdentity>, forStartingCall: Bool) async {
        os_log("☎️ Posting a newWebRTCMessageToSend", log: Self.log, type: .info)
        VoIPNotification.newWebRTCMessageToSend(webrtcMessage: webrtcMessage, contactID: contactID, forStartingCall: forStartingCall)
            .postOnDispatchQueue(queueForPostingNotifications)
    }
    
    
    func newParticipantWasAdded(call: OlvidCall, callParticipant: OlvidCallParticipant) async {
        switch call.direction {
        case .incoming:
            Self.report(call: call, report: .newParticipantInIncomingCall(callParticipant.info))
        case .outgoing:
            Self.report(call: call, report: .newParticipantInOutgoingCall(callParticipant.info))
        }
        let update = await call.createUpToDateCXCallUpdate()
        callProviderHolder.provider.reportCall(with: call.uuidForCallKit, updated: update)
    }
    
    
    private static func report(call: OlvidCall, report: CallReport) {
        os_log("☎️📖 Report call to user as %{public}@", log: Self.log, type: .info, report.description)
        VoIPNotification.reportCallEvent(callUUID: call.uuidForCallKit, callReport: report, groupId: call.groupId, ownedCryptoId: call.ownedCryptoId)
            .postOnDispatchQueue()
    }

    
    func receivedRelayedMessage(call: OlvidCall, messageType: WebRTCMessageJSON.MessageType, serializedMessagePayload: String, uuidForWebRTC: UUID, fromOlvidUser: OlvidUserId) async {
        await self.processReceivedWebRTCMessage(
            messageType: messageType,
            serializedMessagePayload: serializedMessagePayload,
            uuidForWebRTC: uuidForWebRTC,
            fromOlvidUser: fromOlvidUser,
            messageIdentifierFromEngine: nil)
    }

    
    func receivedHangedUpMessage(call: OlvidCall, serializedMessagePayload: String, uuidForWebRTC: UUID, fromOlvidUser: OlvidUserId) async {
        await self.processReceivedWebRTCMessage(
            messageType: .hangedUp,
            serializedMessagePayload: serializedMessagePayload,
            uuidForWebRTC: uuidForWebRTC,
            fromOlvidUser: fromOlvidUser,
            messageIdentifierFromEngine: nil)
    }
    
}


// MARK: - Processing user requests

extension CallProviderDelegate {
    
    private func processUserWantsToCallNotification(ownedCryptoId: ObvCryptoId, contactCryptoIds: Set<ObvCryptoId>, ownedIdentityForRequestingTurnCredentials: ObvCryptoId, groupId: GroupIdentifier?) async {

        let granted = await AVAudioSession.sharedInstance().requestRecordPermission()
        
        if granted {
            
            do {
                // The following call will eventually trigger a system call to provider(_ provider: CXProvider, perform action: CXStartCallAction)
                try await callManager.localUserWantsToStartOutgoingCall(
                    ownedCryptoId: ownedCryptoId,
                    contactCryptoIds: contactCryptoIds,
                    ownedIdentityForRequestingTurnCredentials: ownedIdentityForRequestingTurnCredentials,
                    groupId: groupId,
                    rtcPeerConnectionQueue: rtcPeerConnectionQueue,
                    olvidCallDelegate: self)
            } catch {
                os_log("☎️ Failed to create outgoing call %{public}@", log: Self.log, type: .info, error.localizedDescription)
                assertionFailure()
                return
            }
            
        } else {
            
            ObvMessengerInternalNotification.outgoingCallFailedBecauseUserDeniedRecordPermission
                .postOnDispatchQueue(queueForPostingNotifications)
            
        }

    }
    
}


// MARK: - Implementing ObvProviderDelegate

extension CallProviderDelegate: CallProviderHolderDelegate {
    
    /// Required method of the `CXProviderDelegate` protocol.
    func providerDidReset(_ provider: CallProviderHolder) async {
        assertionFailure()
        os_log("☎️ Provider did reset", log: Self.log, type: .info)
    }
    
    
    /// Called by the system when the user starts an outgoing call.
    func provider(_ provider: CallProviderHolder, perform action: CXStartCallAction) async {
        os_log("☎️ Call to provider(CXStartCallAction) for call with uuidForCallKit %{public}@", log: Self.log, type: .info, action.callUUID.debugDescription)
        do {
            
            // Configure the audio session but do not start call audio here.
            // When using CallKit, call audio should not be started until the audio session is activated by the system,
            // after having its priority elevated.
            await configureAudioSession()

            // Trigger the call to be started via the underlying network service.
            let upToDateCXCallUpdate = try await callManager.localUserWantsToPerform(action)
            
            // Signal to the system that the action was successfully performed.
            os_log("☎️ Fulfills call to provider(CXStartCallAction) for call with uuidForCallKit %{public}@", log: Self.log, type: .info, action.callUUID.debugDescription)
            action.fulfill()

            // If we stop here, the name displayed within iOS call log is incorrect (it shows the call UUID). Updating the call right now does the trick.
            os_log("☎️ Using the created incoming call to update the CXCallProvider", log: Self.log, type: .info)
            callProviderHolder.provider.reportCall(with: action.callUUID, updated: upToDateCXCallUpdate)

        } catch {
            os_log("☎️ Fails call to provider(CXStartCallAction) for call with uuidForCallKit %{public}@", log: Self.log, type: .error, action.callUUID.debugDescription)
            assertionFailure()
            action.fail()
        }
    }
    
    
    /// Called by the system when the user answers an incoming call from the CallKit interface. Also called when the user accepts a call from the non-CallKit interface (on a simulator).
    /// In that last case, we created a `CXAnswerCallAction` ourselves at the OlvidCallManager level.
    func provider(_ provider: CallProviderHolder, perform action: CXAnswerCallAction) async {
        os_log("☎️ [CXAnswerCallAction] Call to provider(CXAnswerCallAction) for call with uuidForCallKit %{public}@", log: Self.log, type: .info, action.callUUID.debugDescription)
        do {
            
            // Configure the audio session but do not start call audio here.
            // When using CallKit, call audio should not be started until the audio session is activated by the system,
            // after having its priority elevated.
            await configureAudioSession()

            // Trigger the call to be answered via the underlying network service.
            let (incomingCall, callerInfo, answeredOnOtherDeviceMessageJSON) = try await callManager.localUserWantsToPerform(action)
            
            // Signal to the system that the action was successfully performed.
            os_log("☎️ [CXAnswerCallAction] Fulfills call to provider(CXAnswerCallAction) for call with uuidForCallKit %{public}@", log: Self.log, type: .info, action.callUUID.debugDescription)
            action.fulfill()
            
            Self.report(call: incomingCall, report: .acceptedIncomingCall(caller: callerInfo))
            
            // Notify other owned devices that the call was accepted on this device
            
            if let answeredOnOtherDeviceMessageJSON {
                VoIPNotification.newOwnedWebRTCMessageToSend(ownedCryptoId: incomingCall.ownedCryptoId, webrtcMessage: answeredOnOtherDeviceMessageJSON)
                    .postOnDispatchQueue()
            }
            
        } catch {
            os_log("☎️ [CXAnswerCallAction] Fails call to provider(CXAnswerCallAction) for call with uuidForCallKit %{public}@", log: Self.log, type: .error, action.callUUID.debugDescription)
            assertionFailure()
            action.fail()
        }
    }
    
    
    /// Called by the system when the user ends (or rejects) an incoming call from the CallKit interface or as a result of a `CXEndCallAction` requested by the `OlvidCallManager` (triggered by the Olvid UI).
    /// Note that this is *not* called when the call is ended by the contact.
    func provider(_ provider: CallProviderHolder, perform action: CXEndCallAction) async {
        os_log("☎️ Call to provider(CXEndCallAction) for call with uuidForCallKit %{public}@", log: Self.log, type: .info, action.callUUID.debugDescription)
        do {
            
            // Let the OlvidCallManager end the call.
            // This returns an optional report as well as the call removed from the list of calls.
            let (call, report, rejectedOnOtherDeviceMessageJSON) = try await callManager.localUserWantsToPerform(action)
            
            // If there is a report to send, do it now
            if let call, let report {
                Self.report(call: call, report: report)
            }
            
            // Stop call audio when ending a call in a simulator
            stopAudioWhenNotUsingCallKit()

            // Signal to the system that the action was successfully performed.
            os_log("☎️ Fulfills call to provider(CXEndCallAction) for call with uuidForCallKit %{public}@", log: Self.log, type: .info, action.callUUID.debugDescription)
            action.fulfill()
            
            // If answeredOnOtherDeviceMessageJSON != nil, it means we have to notify other owned devices that the call was rejected on this device
            
            if let call, let rejectedOnOtherDeviceMessageJSON {
                VoIPNotification.newOwnedWebRTCMessageToSend(ownedCryptoId: call.ownedCryptoId, webrtcMessage: rejectedOnOtherDeviceMessageJSON)
                    .postOnDispatchQueue()
            }

        } catch {
            os_log("☎️ Fails call to provider(CXEndCallAction) for call with uuidForCallKit %{public}@", log: Self.log, type: .error, action.callUUID.debugDescription)
            assertionFailure()
            action.fail()
        }
    }
    
    
    func provider(_ provider: CallProviderHolder, perform action: CXSetMutedCallAction) async {
        os_log("☎️ Call to provider(CXSetMutedCallAction) for call with uuidForCallKit %{public}@", log: Self.log, type: .info, action.callUUID.debugDescription)
        do {

            try await callManager.localUserWantsToSetMuteSelf(action)
            os_log("☎️ Fulfills call to provider(CXSetMutedCallAction) for call with uuidForCallKit %{public}@", log: Self.log, type: .info, action.callUUID.debugDescription)
            action.fulfill()
            
        } catch {
            os_log("☎️ Fails call to provider(CXSetMutedCallAction) for call with uuidForCallKit %{public}@", log: Self.log, type: .error, action.callUUID.debugDescription)
            assertionFailure()
            action.fail()
        }
    }
    
    
    /// This delegate method is called *only* when using CallKit.
    func provider(_ provider: CallProviderHolder, didActivate audioSession: AVAudioSession) async {
        // See https://stackoverflow.com/a/55781328
        os_log("☎️🎵 Provider did activate audioSession %{public}@", log: Self.log, type: .info, audioSession.description)
        RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
        if RTCAudioSession.sharedInstance().useManualAudio {
            // true when using CallKit
            RTCAudioSession.sharedInstance().isAudioEnabled = true
        }
    }


    /// This delegate method is called *only* when using CallKit.
    func provider(_ provider: CallProviderHolder, didDeactivate audioSession: AVAudioSession) async {
        os_log("☎️🎵 Provider did deactivate audioSession %{public}@", log: Self.log, type: .info, audioSession.description)
        RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
        if RTCAudioSession.sharedInstance().useManualAudio {
            // true when using CallKit
            RTCAudioSession.sharedInstance().isAudioEnabled = false
        }
    }

}


// MARK: - Audio utils

extension CallProviderDelegate {
    
    private func configureAudioSession() async {
        os_log("☎️🎵 Configure audio session", log: Self.log, type: .info)
        let op = ConfigureAudioSessionOperation()
        os_log("☎️ Operations in the queue: %{public}@ before adding %{public}@", log: Self.log, type: .info, rtcPeerConnectionQueue.operations.debugDescription, op.debugDescription)
        await rtcPeerConnectionQueue.addAndAwaitOperation(op)
        if op.isCancelled {
            os_log("☎️🎵 Audio configuration failed", log: Self.log, type: .fault)
            // We do not throw as the configuration fails sometimes (e.g., when accepting an incoming call while another Olvid call was in progress).
            // In the failure cases we encoutered, the call worked anyway.
        }
    }

    
    /// This is called when ending a call (both incoming and ougoing). In the CallKit case, this does nothing, as the same work is done at the appropriate time in ``provider(_:didDeactivate:)``.
    /// In the non-CallKit case, we stop the WebRTC audio.
    func stopAudioWhenNotUsingCallKit() {
        if !(ObvUICoreDataConstants.useCallKit) {
            // We don't await until the audio session is stopped
            // To allow the call window to close quickly, we wait some time before diactivating audio
            let rtcPeerConnectionQueue = self.rtcPeerConnectionQueue
            rtcPeerConnectionQueue.addOperation {
                os_log("☎️🔚 Deactivating audio on end call", log: Self.log, type: .info)
                RTCAudioSession.sharedInstance().isAudioEnabled = false
                try? RTCAudioSession.sharedInstance().setActive(false)
                os_log("☎️🔚 Deactivated audio on end call", log: Self.log, type: .info)
            }
        }
    }
    
}


// MARK: - Implementing OlvidCallManagerDelegate

extension CallProviderDelegate: OlvidCallManagerDelegate {
    
    func callWasAdded(callManager: OlvidCallManager, call: OlvidCall) async {
        let model = OlvidCallViewController.Model(call: call, manager: callManager)
        if call.direction == .incoming && ObvUICoreDataConstants.useCallKit {
            // In the CallKit case, we don't want to show the in-house UI together with the CallKit UI for an incoming call.
            // We wait until the local user accepts the incoming call.
        } else {
            VoIPNotification.newCallToShow(model: model)
                .post()
        }
    }
    
    nonisolated
    func callWasRemoved(callManager: OlvidCallManager, removedCall: OlvidCall, callStillInProgress: OlvidCall?) async {
        
        os_log("☎️🔚 Call to callWasRemoved(callManager: OlvidCallManager, removedCall: OlvidCall, callStillInProgress: OlvidCall?)", log: Self.log, type: .info)
        
        if let callStillInProgress {
            let model = OlvidCallViewController.Model(call: callStillInProgress, manager: callManager)
            VoIPNotification.newCallToShow(model: model)
                .post()
        } else {
            VoIPNotification.noMoreCallInProgress
                .postOnDispatchQueue()
        }
        
    }
    
}


// MARK: - Errors

extension CallProviderDelegate {
    
    enum ObvError: Error {
        case audioConfigurationFailed
        case couldNotFindIncomingCallInCallManager
        case couldNotFindOutgoingCallInCallManager
        case noSpecifiedOwnedCryptoIdForRequestingTurnCredentialsForOutgoingCall
    }
    
}


// MARK: - Extensions / Helpers

fileprivate extension CallProviderDelegate {
    
    @MainActor
    func ownedIdentityHasSeveralDevices(ownedCryptoId: ObvCryptoId) async throws -> Bool {
        guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: ObvStack.shared.viewContext) else { assertionFailure(); return false }
        return ownedIdentity.devices.count > 1
    }
    
}

fileprivate extension ObvEncryptedPushNotification {

    init?(dict: [AnyHashable: Any]) {

        guard let wrappedKeyString = dict["encryptedHeader"] as? String else { return nil }
        guard let encryptedContentString = dict["encryptedMessage"] as? String else { return nil }

        guard let wrappedKey = Data(base64Encoded: wrappedKeyString),
              let encryptedContent = Data(base64Encoded: encryptedContentString),
              let maskingUID = dict["maskinguid"] as? String,
              let messageUploadTimestampFromServerAsDouble = dict["timestamp"] as? Double,
              let messageIdFromServer = dict["messageuid"] as? String else {
                  return nil
              }

        let messageUploadTimestampFromServer = Date(timeIntervalSince1970: messageUploadTimestampFromServerAsDouble / 1000.0)

        self.init(messageIdFromServer: messageIdFromServer,
                  wrappedKey: wrappedKey,
                  encryptedContent: encryptedContent,
                  encryptedExtendedContent: nil,
                  maskingUID: maskingUID,
                  messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                  localDownloadTimestamp: Date())

    }

}


extension CXCallUpdate {
    
    static func createForIncomingCallUntilStartCallMessageIsAvailable(callIdentifierForCallKit: UUID) -> Self {
        let update = Self()
        update.localizedCallerName = "..."
        update.remoteHandle = .init(type: .generic, value: callIdentifierForCallKit.uuidString)
        update.hasVideo = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsHolding = false
        update.supportsDTMF = false
        return update
    }
    
}
