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
import CoreData
import ObvTypes
import ObvEngine
import PushKit
import AVKit
import WebRTC
import OlvidUtils
import ObvCrypto


final actor CallManager: ObvErrorMaker {

    static let errorDomain = "CallManager"
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: CallManager.self))

    private let pushRegistryHandler: ObvPushRegistryHandler

    private var continuationsWaitingForCallKitVoIPNotification = [Data: CheckedContinuation<UUID, Never>]()
    private var filteredIncomingCalls = [UUID]()
    private var currentCalls = [Call]()
    private var messageIdentifiersFromEngineOfRecentlyDeletedIncomingCalls = [Data]()
    private var currentIncomingCalls: [Call] { currentCalls.filter({ $0.direction == .incoming }) }
    private var currentOutgoingCalls: [Call] { currentCalls.filter({ $0.direction == .outgoing }) }
    private var remotelyHangedUpCalls = Set<UUID>()

    private var receivedIceCandidates = [UUID: [(IceCandidateJSON, OlvidUserId)]]()

    /// When receiving a pushkit notification, we do not immediately create a call like we used to do in previous versions of this framework.
    /// Instead, we add an element to this dictionary, indexed by message Ids from the engine. The values are UUID to use with CallKit and when creating the (incoming) call instance
    private var receivedCallKitVoIPNotifications = [Data: UUID]()

    private let obvEngine: ObvEngine
    private var notificationTokens = [NSObjectProtocol]()
    private var notificationForVoIPRegister: NSObjectProtocol?

    private let cxProvider: CXObvProvider
    private let ncxProvider: NCXObvProvider

    private func provider(isCallKit: Bool) -> ObvProvider {
        RTCAudioSession.sharedInstance().useManualAudio = isCallKit
        return isCallKit ? cxProvider : ncxProvider
    }

    init(obvEngine: ObvEngine) {
        let cxProvider = CXObvProvider(configuration: CallManager.providerConfiguration)
        let ncxProvider = NCXObvProvider.instance
        self.obvEngine = obvEngine
        self.cxProvider = cxProvider
        self.ncxProvider = ncxProvider
        self.pushRegistryHandler = ObvPushRegistryHandler(obvEngine: obvEngine, cxObvProvider: cxProvider)
        ncxProvider.setConfiguration(CallManager.providerConfiguration)
        cxProvider.setDelegate(self, queue: nil)
        ncxProvider.setDelegate(self, queue: nil)
    }

    private let queueForPostingNotifications = DispatchQueue(label: "Call queue for posting notifications")

    
    func performPostInitialization() {
        listenToNotifications()
        /// Force provider initialization
        _ = provider(isCallKit: ObvMessengerSettings.VoIP.isCallKitEnabled)
        pushRegistryHandler.registerForVoIPPushes(delegate: self)
    }
    
    
    /// The app's provider configuration, representing its CallKit capabilities
    private static var providerConfiguration: ObvProviderConfiguration {
        let localizedName = NSLocalizedString("Olvid", comment: "Name of application")
        var providerConfiguration = ObvProviderConfigurationImpl(localizedName: localizedName)
        providerConfiguration.supportsVideo = false
        providerConfiguration.maximumCallGroups = 1
        providerConfiguration.maximumCallsPerCallGroup = 1
        providerConfiguration.supportedHandleTypes_ = [.generic]
        providerConfiguration.includesCallsInRecents = ObvMessengerSettings.VoIP.isIncludesCallsInRecentsEnabled
        providerConfiguration.iconTemplateImageData = UIImage(named: "olvid-callkit-logo")?.pngData()
        return providerConfiguration
    }

    
    func applicationAppearedOnScreen(forTheFirstTime: Bool) async {
        for call in currentIncomingCalls {
            guard await !call.state.isFinalState else { return }
            VoIPNotification.anIncomingCallShouldBeShownToUser(newIncomingCall: call)
                .postOnDispatchQueue(queueForPostingNotifications)
            return
        }
    }
    

    private func listenToNotifications() {

        // VoIP notifications

        notificationTokens.append(contentsOf: [
            VoIPNotification.observeUserWantsToKickParticipant { (call, callParticipant) in
                Task { [weak self] in await self?.processUserWantsToKickParticipant(call: call, callParticipant: callParticipant) }
            },
            VoIPNotification.observeUserWantsToAddParticipants { [weak self] (call, contactIds) in
                Task { [weak self] in await self?.processUserWantsToAddParticipants(call: call, contactIds: contactIds) }
            },
        ])

        // Internal notifications

        notificationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeNewWebRTCMessageWasReceived { (webrtcMessage, contactId, messageUploadTimestampFromServer, messageIdentifierFromEngine) in
                Task { [weak self] in
                    await self?.processReceivedWebRTCMessage(messageType: webrtcMessage.messageType,
                                                             serializedMessagePayload: webrtcMessage.serializedMessagePayload,
                                                             callIdentifier: webrtcMessage.callIdentifier,
                                                             contact: contactId,
                                                             messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                                                             messageIdentifierFromEngine: messageIdentifierFromEngine)
                }
            },
            ObvMessengerInternalNotification.observeUserWantsToCallAndIsAllowedTo { (contactIds, groupId) in
                Task { [weak self] in await self?.processUserWantsToCallNotification(contactIds: contactIds, groupId: groupId) }
            },
            ObvMessengerInternalNotification.observeNetworkInterfaceTypeChanged { [weak self] (isConnected) in
                Task { [weak self] in await self?.processNetworkStatusChangedNotification(isConnected: isConnected) }
            },
            ObvMessengerInternalNotification.observeIsCallKitEnabledSettingDidChange { [weak self] in
                Task { [weak self] in await self?.processIsCallKitEnabledSettingDidChangeNotification() }
            },
            ObvMessengerInternalNotification.observeIsIncludesCallsInRecentsEnabledSettingDidChange { [weak self] in
                Task { [weak self] in await self?.processIsIncludesCallsInRecentsEnabledSettingDidChangeNotification() }
            },
        ])

        // Engine notifications

        notificationTokens.append(contentsOf: [
            ObvEngineNotificationNew.observeCallerTurnCredentialsReceived(within: NotificationCenter.default) { [weak self] (ownedIdentity, callUuid, turnCredentials) in
                Task { [weak self] in await  self?.processCallerTurnCredentialsReceivedNotification(ownedIdentity: ownedIdentity, uuidForWebRTC: callUuid, turnCredentials: turnCredentials) }
            },
            ObvEngineNotificationNew.observeCallerTurnCredentialsReceptionFailure(within: NotificationCenter.default) { [weak self] (ownedIdentity, callUuid) in
                Task { [weak self] in await self?.processCallerTurnCredentialsReceptionFailureNotification(ownedIdentity: ownedIdentity, uuidForWebRTC: callUuid) }
            },
            ObvEngineNotificationNew.observeCallerTurnCredentialsReceptionPermissionDenied(within: NotificationCenter.default) { [weak self] (ownedIdentity, callUuid) in
                Task { [weak self] in await self?.processCallerTurnCredentialsReceptionPermissionDeniedNotification(ownedIdentity: ownedIdentity, uuidForWebRTC: callUuid) }
            },
            ObvEngineNotificationNew.observeCallerTurnCredentialsServerDoesNotSupportCalls(within: NotificationCenter.default) { [weak self] (ownedIdentity, callUuid) in
                Task { [weak self] in await self?.processTurnCredentialsServerDoesNotSupportCalls(ownedIdentity: ownedIdentity, uuidForWebRTC: callUuid) }
            },
        ])
    }


    private func addCallToCurrentCalls(call: Call) async throws {
        let callState = await call.state
        assert(callState == .initial)
        os_log("☎️ Adding call to the list of current calls", log: Self.log, type: .info)

        assert(currentCalls.first(where: { $0.uuid == call.uuid }) == nil, "Trying to add a call that already exists in the list of current calls")
        currentCalls.append(call)

        switch call.direction {
        case .outgoing:
            VoIPNotification.newOutgoingCall(newOutgoingCall: call)
                .postOnDispatchQueue(queueForPostingNotifications)
        case .incoming:
            VoIPNotification.newIncomingCall(newIncomingCall: call)
                .postOnDispatchQueue(queueForPostingNotifications)
        }

    }


    private func removeCallFromCurrentCalls(call: Call) async throws {
        os_log("☎️ Removing call from the list of current calls", log: Self.log, type: .info)
        let callState = await call.state
        assert(callState.isFinalState)

        currentCalls.removeAll(where: { $0.uuid == call.uuid })
        if currentCalls.isEmpty {
            // Yes, we need to make sure the calls are properly freed...
            currentCalls = []
        }
        if call.direction == .incoming {
            assert(call.messageIdentifierFromEngine != nil)
            if let messageIdentifierFromEngine = call.messageIdentifierFromEngine {
                messageIdentifiersFromEngineOfRecentlyDeletedIncomingCalls.append(messageIdentifierFromEngine)
            }
        }
        if let newCall = currentCalls.first {
            let newCallState = await newCall.state
            assert(!newCallState.isFinalState)
            VoIPNotification.callHasBeenUpdated(callUUID: newCall.uuid, updateKind: .state(newState: newCallState))
                .postOnDispatchQueue(queueForPostingNotifications)
        } else {
            VoIPNotification.noMoreCallInProgress
                .postOnDispatchQueue(queueForPostingNotifications)
        }
        receivedIceCandidates[call.uuidForWebRTC] = nil
    }


    private func createOutgoingCall(contactIds: [OlvidUserId], groupId: GroupIdentifierBasedOnObjectID?) async throws -> Call {
        let outgoingCall = try await Call.createOutgoingCall(contactIds: contactIds,
                                                             delegate: self,
                                                             usesCallKit: ObvMessengerSettings.VoIP.isCallKitEnabled,
                                                             groupId: groupId,
                                                             queueForPostingNotifications: queueForPostingNotifications)
        try await addCallToCurrentCalls(call: outgoingCall)
        assert(outgoingCall.direction == .outgoing)
        return outgoingCall
    }

}


// MARK: - Processing notifications

extension CallManager {

    private func processIsCallKitEnabledSettingDidChangeNotification() {
        // Force provider initialization
        _ = provider(isCallKit: ObvMessengerSettings.VoIP.isCallKitEnabled)
    }


    private func processIsIncludesCallsInRecentsEnabledSettingDidChangeNotification() {
        let provider = self.provider(isCallKit: ObvMessengerSettings.VoIP.isCallKitEnabled)
        var configuration = provider.configuration_
        configuration.includesCallsInRecents = ObvMessengerSettings.VoIP.isIncludesCallsInRecentsEnabled
        provider.configuration_ = configuration
    }


    private func processNetworkStatusChangedNotification(isConnected: Bool) async {
        os_log("☎️ Processing a network status changed notification", log: Self.log, type: .info)
        await withTaskGroup(of: Void.self) { taskGroup in
            for call in currentCalls {
                taskGroup.addTask {
                    do {
                        try await call.restartIceIfAppropriate()
                    } catch {
                        os_log("☎️ Could not restart ICE after a network status change: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                        assertionFailure()
                    }
                }
            }
        }
    }


    private func processCallerTurnCredentialsReceptionFailureNotification(ownedIdentity: ObvCryptoId, uuidForWebRTC: UUID) async {
        os_log("☎️ Processing a CallerTurnCredentialsReceptionFailure notification", log: Self.log, type: .fault)
        guard let call = currentOutgoingCalls.first(where: { $0.uuidForWebRTC == uuidForWebRTC }) else { return }
        await call.endCallAsPermissionWasDeniedByServer()
    }


    private func processCallerTurnCredentialsReceptionPermissionDeniedNotification(ownedIdentity: ObvCryptoId, uuidForWebRTC: UUID) async {
        os_log("☎️ Processing a CallerTurnCredentialsReceptionPermissionDenied notification", log: Self.log, type: .fault)
        guard let call = currentOutgoingCalls.first(where: { $0.uuidForWebRTC == uuidForWebRTC }) else { return }
        await call.endCallAsPermissionWasDeniedByServer()
    }


    private func processTurnCredentialsServerDoesNotSupportCalls(ownedIdentity: ObvCryptoId, uuidForWebRTC: UUID) async {
        os_log("☎️ Processing a TurnCredentialsServerDoesNotSupportCalls notification", log: Self.log, type: .fault)
        guard let call = currentOutgoingCalls.first(where: { $0.uuidForWebRTC == uuidForWebRTC }) else { return }
        await call.endCallAsInitiationNotSupported()
        VoIPNotification.serverDoesNotSupportCall
            .postOnDispatchQueue(queueForPostingNotifications)
    }


    /// This method is called when receiving the credentials allowing to make an outgoing call. At this point, the outgoing call has already been created and is waiting for these credentials.
    /// Under the hood, the caller has a peer connection holder which of the call participants, but these connection holders do *not* have a WebRTC peer connection yet.
    /// Setting the credentials will create these peer connections.
    private func processCallerTurnCredentialsReceivedNotification(ownedIdentity: ObvCryptoId, uuidForWebRTC: UUID, turnCredentials: ObvTurnCredentials) async {
        let currentOutgoingCalls = self.currentCalls.filter({ $0.direction == .outgoing })
        guard let outgoingCall = currentOutgoingCalls.first(where: { $0.uuidForWebRTC == uuidForWebRTC }) else { return }
        await outgoingCall.setTurnCredentials(turnCredentials)
    }

}



// MARK: - ObvPushRegistryHandlerDelegate

extension CallManager: ObvPushRegistryHandlerDelegate {

    /// When using CallKit, we always wait until the pushkit notification is received before creating an incoming call.
    /// When we receive it, we do not create an "empty" call instance like we used to do in previous versions of the framework.
    /// Instead, we simply add an element to the `receivedCallKitVoIPNotifications` dictionary.
    /// This essentially is what this method is about.
    func successfullyReportedNewIncomingCallToCallKit(uuidForCallKit: UUID, messageIdentifierFromEngine: Data) async {

        // If the incoming call was recently deleted, we just dismiss the CallKit UI (that we just showed) and terminate.

        guard !messageIdentifiersFromEngineOfRecentlyDeletedIncomingCalls.contains(messageIdentifierFromEngine) else {
            cxProvider.endReportedIncomingCall(with: uuidForCallKit, inSeconds: 2)
            return
        }

        // Add an entry to the receivedCallKitVoIPNotifications array

        assert(receivedCallKitVoIPNotifications[messageIdentifierFromEngine] == nil)
        receivedCallKitVoIPNotifications[messageIdentifierFromEngine] = uuidForCallKit

        // We may have already received a start call message (in case we are in a CallKit scenario and the WebSocket was faster than the VoIP notification)
        // In that situation, we know the StartCall processing method is waiting that the VoIP push notification is received before creating the incoming call and adding it to the list of current call.
        // The following two lines allows to "unblock" the start call processing method.

        if let continuation = continuationsWaitingForCallKitVoIPNotification.removeValue(forKey: messageIdentifierFromEngine) {
            continuation.resume(returning: uuidForCallKit)
        }

    }


    func failedToReportNewIncomingCallToCallKit(callUUID: UUID, error: Error) async {

        let incomingCallError = ObvErrorCodeIncomingCallError(rawValue: (error as NSError).code) ?? .unknown
        switch incomingCallError {
        case .unknown, .unentitled, .callUUIDAlreadyExists, .maximumCallGroupsReached:
            os_log("☎️ reportNewIncomingCall failed -> ending call: %{public}@", log: Self.log, type: .error, error.localizedDescription)
            assertionFailure()
        case .filteredByDoNotDisturb, .filteredByBlockList:
            os_log("☎️ reportNewIncomingCall filtered (busy/blocked) -> set call has been filtered", log: Self.log, type: .info)
            filteredIncomingCalls.append(callUUID)
        }

    }

}



// MARK: - Processing received WebRTC messages

extension CallManager {

    internal func processReceivedWebRTCMessage(messageType: WebRTCMessageJSON.MessageType, serializedMessagePayload: String, callIdentifier: UUID, contact: OlvidUserId, messageUploadTimestampFromServer: Date, messageIdentifierFromEngine: Data?) async {
        if case .hangedUp = messageType {
            os_log("☎️🛑 We received %{public}@ message", log: Self.log, type: .info, messageType.description)
        } else {
            os_log("☎️ We received %{public}@ message", log: Self.log, type: .info, messageType.description)
        }
        do {
            switch messageType {

            case .startCall:
                let startCallMessage = try StartCallMessageJSON.jsonDecode(serializedMessagePayload: serializedMessagePayload)
                guard let messageIdentifierFromEngine = messageIdentifierFromEngine else { assertionFailure(); return }
                try await processStartCallMessage(startCallMessage,
                                                  uuidForWebRTC: callIdentifier,
                                                  userId: contact,
                                                  messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                                                  messageIdentifierFromEngine: messageIdentifierFromEngine)

            case .answerCall:
                let answerCallMessage = try AnswerCallJSON.jsonDecode(serializedMessagePayload: serializedMessagePayload)
                try await processAnswerCallMessage(answerCallMessage, uuidForWebRTC: callIdentifier, contact: contact, messageUploadTimestampFromServer: messageUploadTimestampFromServer)

            case .rejectCall:
                let rejectCallMessage = try RejectCallMessageJSON.jsonDecode(serializedMessagePayload: serializedMessagePayload)
                try await processRejectCallMessage(rejectCallMessage, uuidForWebRTC: callIdentifier, contact: contact, messageUploadTimestampFromServer: messageUploadTimestampFromServer)

            case .hangedUp:
                let hangedUpMessage = try HangedUpMessageJSON.jsonDecode(serializedMessagePayload: serializedMessagePayload)
                try await processHangedUpMessage(hangedUpMessage, uuidForWebRTC: callIdentifier, contact: contact, messageUploadTimestampFromServer: messageUploadTimestampFromServer)

            case .ringing:
                _ = try RingingMessageJSON.jsonDecode(serializedMessagePayload: serializedMessagePayload)
                try await processRingingMessageJSON(uuidForWebRTC: callIdentifier, contact: contact, messageUploadTimestampFromServer: messageUploadTimestampFromServer)

            case .busy:
                _ = try BusyMessageJSON.jsonDecode(serializedMessagePayload: serializedMessagePayload)
                try await processBusyMessageJSON(uuidForWebRTC: callIdentifier, contact: contact, messageUploadTimestampFromServer: messageUploadTimestampFromServer)

            case .reconnect:
                let reconnectCallMessage = try ReconnectCallMessageJSON.jsonDecode(serializedMessagePayload: serializedMessagePayload)
                try await processReconnectCallMessageJSON(reconnectCallMessage, uuidForWebRTC: callIdentifier, contact: contact, messageUploadTimestampFromServer: messageUploadTimestampFromServer)

            case .newParticipantAnswer:
                let newParticipantAnswer = try NewParticipantAnswerMessageJSON.jsonDecode(serializedMessagePayload: serializedMessagePayload)
                try await processNewParticipantAnswerMessageJSON(newParticipantAnswer, uuidForWebRTC: callIdentifier, contact: contact, messageUploadTimestampFromServer: messageUploadTimestampFromServer)

            case .newParticipantOffer:
                let newParticipantOffer = try NewParticipantOfferMessageJSON.jsonDecode(serializedMessagePayload: serializedMessagePayload)
                try await processNewParticipantOfferMessageJSON(newParticipantOffer, uuidForWebRTC: callIdentifier, contact: contact, messageUploadTimestampFromServer: messageUploadTimestampFromServer)

            case .kick:
                let kickMessage = try KickMessageJSON.jsonDecode(serializedMessagePayload: serializedMessagePayload)
                try await processKickMessageJSON(kickMessage, uuidForWebRTC: callIdentifier, contact: contact, messageUploadTimestampFromServer: messageUploadTimestampFromServer)

            case .newIceCandidate:
                os_log("☎️❄️ We received new ICE Candidate message: %{public}@", log: Self.log, type: .info, messageType.description)
                let iceCandidate = try IceCandidateJSON.jsonDecode(serializedMessagePayload: serializedMessagePayload)
                try await processIceCandidateMessage(message: iceCandidate, uuidForWebRTC: callIdentifier, contact: contact)

            case .removeIceCandidates:
                let removeIceCandidatesMessage = try RemoveIceCandidatesMessageJSON.jsonDecode(serializedMessagePayload: serializedMessagePayload)
                try await processRemoveIceCandidatesMessage(message: removeIceCandidatesMessage, uuidForWebRTC: callIdentifier, contact: contact)

            }
        } catch {
            os_log("☎️ Could not parse or process the WebRTCMessageJSON: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
        }
    }


    /// This method processes a received StartCallMessageJSON. In case we use CallKit and Olvid is in the background, this message is probably first received first within a PushKit notification, that gets decrypted very fast, which eventually triggers this method. Note that
    /// since decrypting a notification does *not* delete the decryption key, it almost certain that this method will get called a second time: the message will be fetched from the server, decrypted as usual, which eventually triggers this method again.
    private func processStartCallMessage(_ startCallMessage: StartCallMessageJSON, uuidForWebRTC: UUID, userId: OlvidUserId, messageUploadTimestampFromServer: Date, messageIdentifierFromEngine: Data) async throws {

        // If the call was already terminated, discard this message

        guard !remotelyHangedUpCalls.contains(uuidForWebRTC) else {
            return
        }

        // If the call already exists in the current calls, we do nothing. This can happen when decrypting the VoIP notification first (when using CallKit), then receiving the start call message via the network In that case, we can receive the start call message twice. We only consider the first occurence

        guard currentIncomingCalls.first(where: { $0.messageIdentifierFromEngine == messageIdentifierFromEngine }) == nil else {
            os_log("We already received this start call message (which can occur when using CallKit). We discard this one.", log: Self.log, type: .info)
            return
        }

        // We check that the `StartCallMessageJSON` is not too old. If this is the case, we ignore it

        let timeInterval = Date().timeIntervalSince(messageUploadTimestampFromServer) // In seconds
        guard timeInterval < Call.acceptableTimeIntervalForStartCallMessages else {
            os_log("☎️ We received an old StartCallMessageJSON, uploaded %{timeInterval}f seconds ago on the server. We ignore it.", log: Self.log, type: .info, timeInterval)
            return
        }

        os_log("☎️ We received a fresh StartCallMessageJSON, uploaded %{timeInterval}f seconds ago on the server.", log: Self.log, type: .info, timeInterval)

        // In the CallKit case, we are not in charge of inserting the incoming call in the `currentIncomingCalls` array.
        // In that case, we wait until this is done.
        // In the non-CallKit case, we are in charge and we insert it right away.

        let useCallKit = ObvMessengerSettings.VoIP.isCallKitEnabled
        let callUUID: UUID
        if useCallKit {
            callUUID = await waitUntilCallKitVoIPIsReceived(messageIdentifierFromEngine: messageIdentifierFromEngine)
        } else {
            callUUID = UUID()
        }
        let incomingCall = await Call.createIncomingCall(uuid: callUUID,
                                                         startCallMessage: startCallMessage,
                                                         contactId: userId,
                                                         uuidForWebRTC: uuidForWebRTC,
                                                         messageIdentifierFromEngine: messageIdentifierFromEngine,
                                                         messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                                                         delegate: self,
                                                         useCallKit: useCallKit,
                                                         queueForPostingNotifications: queueForPostingNotifications)

        try await addCallToCurrentCalls(call: incomingCall)

        assert(incomingCall.direction == .incoming)

        // Now that we know for sure that the incoming call is part of the current calls, we can process the
        // ICE candidates we may already have received

        for (iceCandidate, contact) in receivedIceCandidates[incomingCall.uuidForWebRTC] ?? [] {
            os_log("☎️❄️ Process pending remote IceCandidateJSON message", log: Self.log, type: .info)
            try? await incomingCall.processIceCandidatesJSON(iceCandidate: iceCandidate, participantId: contact)
        }
        receivedIceCandidates[incomingCall.uuidForWebRTC] = nil

        // Finish the processing

        if incomingCall.usesCallKit {

            guard !filteredIncomingCalls.contains(where: { $0 == incomingCall.uuid }) else {
                os_log("☎️ processStartCallMessage: end the filtered call", log: Self.log, type: .info)
                await incomingCall.endCallAsReportingAnIncomingCallFailed(error: .filteredByDoNotDisturb)
                return
            }

            // Update the CallKit UI

            let callUpdate = await ObvCallUpdateImpl.make(with: incomingCall)
            self.provider(isCallKit: true).reportCall(with: incomingCall.uuid, updated: callUpdate)

            // Send the ringing message

            await sendRingingMessageToCaller(forIncomingCall: incomingCall)

        } else {

            await provider(isCallKit: false).reportNewIncomingCall(with: incomingCall.uuid, update: ObvCallUpdateImpl.make(with: incomingCall)) { result in
                Task { [weak self] in
                    guard let _self = self else { return }
                    switch result {
                    case .failure(let error):
                        let incomingCallError = ObvErrorCodeIncomingCallError(rawValue: (error as NSError).code) ?? .unknown
                        switch incomingCallError {
                        case .unknown, .unentitled, .callUUIDAlreadyExists, .filteredByDoNotDisturb, .filteredByBlockList:
                            os_log("☎️ reportNewIncomingCall failed -> ending call", log: Self.log, type: .error)
                        case .maximumCallGroupsReached:
                            os_log("☎️ reportNewIncomingCall maximumCallGroupsReached -> ending call", log: Self.log, type: .error)
                            await Self.report(call: incomingCall, report: .missedIncomingCall(caller: incomingCall.callerCallParticipant?.info, participantCount: startCallMessage.participantCount))
                        }
                        await incomingCall.endCallAsReportingAnIncomingCallFailed(error: incomingCallError)
                    case .success:
                        VoIPNotification.showCallViewControllerForAnsweringNonCallKitIncomingCall(incomingCall: incomingCall)
                            .postOnDispatchQueue(_self.queueForPostingNotifications)
                        await self?.sendRingingMessageToCaller(forIncomingCall: incomingCall)
                    }
                }
            }

        }

    }


    /// In case we use CallKit, we insert a call in the `currentCalls` array when receiving the start call message, not when receiving the VoIP notification.
    /// Yet, in the case we use CallKit, we first need to wait until we receive a CallKit VoIP notification. The fact that we received this notification
    /// is materialized by the insertion of a new element in the `receivedCallKitVoIPNotifications` dictionary, and the "start call message"
    /// processing method waits until this event occurs.
    /// This method (using a patern based on async/await continuations) allows to do just that. To make it work, we must resume the continuation
    /// stored in the `continuationsWaitingForCallKitVoIPNotification` array at the time we add an element in the  insert the `receivedCallKitVoIPNotifications array.
    private func waitUntilCallKitVoIPIsReceived(messageIdentifierFromEngine: Data) async -> UUID {
        if let uuidForCallKit = receivedCallKitVoIPNotifications[messageIdentifierFromEngine] {
            return uuidForCallKit
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<UUID, Never>) in
            Task {
                if let uuidForCallKit = receivedCallKitVoIPNotifications[messageIdentifierFromEngine] {
                    continuation.resume(returning: uuidForCallKit)
                } else {
                    assert(continuationsWaitingForCallKitVoIPNotification[messageIdentifierFromEngine] == nil)
                    continuationsWaitingForCallKitVoIPNotification[messageIdentifierFromEngine] = continuation
                }
            }
        }
    }


    private func processAnswerCallMessage(_ answerCallMessage: AnswerCallJSON, uuidForWebRTC: UUID, contact: OlvidUserId, messageUploadTimestampFromServer: Date) async throws {
        guard let outgoingCall = currentOutgoingCalls.first(where: { $0.uuidForWebRTC == uuidForWebRTC }) else { return }
        guard let participant = await outgoingCall.getParticipant(remoteCryptoId: contact.remoteCryptoId) else { return }
        provider(isCallKit: outgoingCall.usesCallKit).reportOutgoingCall(with: outgoingCall.uuid, startedConnectingAt: nil)
        do {
            try await outgoingCall.processAnswerCallJSON(callParticipant: participant, answerCallMessage)
        } catch {
            os_log("Could not set remote description -> ending call", log: Self.log, type: .fault)
            try await participant.closeConnection()
            assertionFailure()
            throw error
        }
        Self.report(call: outgoingCall, report: .acceptedOutgoingCall(from: participant.info))
    }


    private func processRejectCallMessage(_ rejectCallMessage: RejectCallMessageJSON, uuidForWebRTC: UUID, contact: OlvidUserId, messageUploadTimestampFromServer: Date) async throws {
        guard let call = currentCalls.filter({ $0.uuidForWebRTC == uuidForWebRTC }).first else { return }
        guard let participant = await call.getParticipant(remoteCryptoId: contact.remoteCryptoId) else { return }
        guard call.direction == .outgoing else { return }
        let participantState = await participant.getPeerState()
        guard [.startCallMessageSent, .ringing].contains(participantState) else { return }

        try await participant.setPeerState(to: .callRejected)
        Self.report(call: call, report: .rejectedOutgoingCall(from: participant.info))
    }


    private func processHangedUpMessage(_ hangedUpMessage: HangedUpMessageJSON, uuidForWebRTC: UUID, contact: OlvidUserId, messageUploadTimestampFromServer: Date) async throws {
        guard let call = currentCalls.filter({ $0.uuidForWebRTC == uuidForWebRTC }).first else {
            remotelyHangedUpCalls.insert(uuidForWebRTC)
            return
        }
        let callStateIsInitial = await call.state == .initial
        if call.direction == .incoming && callStateIsInitial {
            await Self.report(call: call, report: .missedIncomingCall(caller: call.callerCallParticipant?.info, participantCount: call.initialParticipantCount))
        }
        try await call.callParticipantDidHangUp(participantId: contact)
    }


    private func processBusyMessageJSON(uuidForWebRTC: UUID, contact: OlvidUserId, messageUploadTimestampFromServer: Date) async throws {
        guard let call = currentCalls.filter({ $0.uuidForWebRTC == uuidForWebRTC }).first else { return }
        guard let participant = await call.getParticipant(remoteCryptoId: contact.remoteCryptoId) else { return }
        guard await participant.getPeerState() == .startCallMessageSent else { return }

        try await participant.setPeerState(to: .busy)
        Self.report(call: call, report: .busyOutgoingCall(from: participant.info))
    }


    private func processRingingMessageJSON(uuidForWebRTC: UUID, contact: OlvidUserId, messageUploadTimestampFromServer: Date) async throws {
        guard let outgoingCall = currentOutgoingCalls.first(where: { $0.uuidForWebRTC == uuidForWebRTC }) else { return }
        guard let participant = await outgoingCall.getParticipant(remoteCryptoId: contact.remoteCryptoId) else { return }
        guard await participant.getPeerState() == .startCallMessageSent else { return }

        try await participant.setPeerState(to: .ringing)
    }


    private func processReconnectCallMessageJSON(_ reconnectCallMessage: ReconnectCallMessageJSON, uuidForWebRTC: UUID, contact: OlvidUserId, messageUploadTimestampFromServer: Date) async throws {
        guard let call = currentCalls.first(where: { $0.uuidForWebRTC == uuidForWebRTC }) else { return }
        guard let participant = await call.getParticipant(remoteCryptoId: contact.remoteCryptoId) else { return }
        try await call.handleReconnectCallMessage(callParticipant: participant, reconnectCallMessage)
    }


    private func processNewParticipantAnswerMessageJSON(_ newParticipantAnswer: NewParticipantAnswerMessageJSON, uuidForWebRTC: UUID, contact: OlvidUserId, messageUploadTimestampFromServer: Date) async throws {
        os_log("☎️ Call to processNewParticipantAnswerMessageJSON", log: Self.log, type: .info)
        guard let call = currentCalls.first(where: { $0.uuidForWebRTC == uuidForWebRTC }) else { return }
        guard let participant = await call.getParticipant(remoteCryptoId: contact.remoteCryptoId) else { return }
        guard participant.role == .recipient else { return }
        let remoteCryptoId = participant.remoteCryptoId
        guard call.shouldISendTheOfferToCallParticipant(cryptoId: remoteCryptoId) else { return }
        let sessionDescription = RTCSessionDescription(type: newParticipantAnswer.sessionDescriptionType, sdp: newParticipantAnswer.sessionDescription)
        os_log("☎️ Will call setRemoteDescription on the participant", log: Self.log, type: .info)
        try await participant.setRemoteDescription(sessionDescription: sessionDescription)
    }


    func processNewParticipantOfferMessageJSON(_ newParticipantOffer: NewParticipantOfferMessageJSON, uuidForWebRTC: UUID, contact: OlvidUserId, messageUploadTimestampFromServer: Date) async throws {
        /// We check that the `NewParticipantOfferMessageJSON` is not too old. If this is the case, we ignore it
        let timeInterval = Date().timeIntervalSince(messageUploadTimestampFromServer) // In seconds
        guard timeInterval < 30 else {
            os_log("☎️ We received an old NewParticipantOfferMessageJSON, uploaded %{timeInterval}f seconds ago on the server. We ignore it.", log: Self.log, type: .info, timeInterval)
            return
        }

        guard let incomingCall = currentCalls.first(where: { $0.uuidForWebRTC == uuidForWebRTC && $0.direction == .incoming }) else { return }
        guard let participant = await incomingCall.getParticipant(remoteCryptoId: contact.remoteCryptoId) else {
            // Put the message in queue as we might simply receive the update call participant message later
            await incomingCall.addPendingOffer((messageUploadTimestampFromServer, newParticipantOffer), from: contact)
            return
        }
        guard participant.role == .recipient else { return }
        let remoteCryptoId = participant.remoteCryptoId
        guard !incomingCall.shouldISendTheOfferToCallParticipant(cryptoId: remoteCryptoId) else { return }

        guard let turnCredentials = incomingCall.turnCredentialsReceivedFromCaller else { assertionFailure(); return }

        try await participant.updateRecipient(newParticipantOfferMessage: newParticipantOffer, turnCredentials: turnCredentials)
    }


    private func processKickMessageJSON(_ kickMessage: KickMessageJSON, uuidForWebRTC: UUID, contact: OlvidUserId, messageUploadTimestampFromServer: Date) async throws {
        guard let call = currentCalls.first(where: { $0.uuidForWebRTC == uuidForWebRTC }) else { return }
        guard let participant = await call.getParticipant(remoteCryptoId: contact.remoteCryptoId) else { return }
        guard participant.role == .caller else { return }
        os_log("☎️ We received an KickMessageJSON from caller", log: Self.log, type: .info)
        await call.endCallAsLocalUserGotKicked()
    }


    private func processIceCandidateMessage(message: IceCandidateJSON, uuidForWebRTC: UUID, contact: OlvidUserId) async throws {

        if let call = currentCalls.first(where: { $0.uuidForWebRTC == uuidForWebRTC }) {

            os_log("☎️❄️ Process IceCandidateJSON message", log: Self.log, type: .info)
            try await call.processIceCandidatesJSON(iceCandidate: message, participantId: contact)

        } else {

            guard !remotelyHangedUpCalls.contains(uuidForWebRTC) else { return }
            os_log("☎️❄️ Received new remote ICE Candidates for a call that does not exists yet. Adding the ICE candidate to the receivedIceCandidates array.", log: Self.log, type: .info)
            var candidates = receivedIceCandidates[uuidForWebRTC] ?? []
            candidates += [(message, contact)]
            receivedIceCandidates[uuidForWebRTC] = candidates
            return

        }

    }


    private func processRemoveIceCandidatesMessage(message: RemoveIceCandidatesMessageJSON, uuidForWebRTC: UUID, contact: OlvidUserId) async throws {

        if let call = currentCalls.first(where: { $0.uuidForWebRTC == uuidForWebRTC }) {

            os_log("☎️❄️ Process RemoveIceCandidatesMessageJSON message", log: Self.log, type: .info)
            try await call.removeIceCandidatesJSON(removeIceCandidatesJSON: message, participantId: contact)

        } else {

            guard !remotelyHangedUpCalls.contains(uuidForWebRTC) else { return }
            os_log("☎️❄️ Received removed remote ICE Candidates for a call that does not exists yet", log: Self.log, type: .info)
            var candidates = receivedIceCandidates[uuidForWebRTC] ?? []
            candidates.removeAll { message.candidates.contains($0.0) }
            receivedIceCandidates[uuidForWebRTC] = candidates

        }

    }


    private func processUserWantsToCallNotification(contactIds: [OlvidUserId], groupId: GroupIdentifierBasedOnObjectID?) async {

        debugPrint("Call to processUserWantsToCallNotification")
        
        // 2022-06-20 We used to wait until the app is initialized and active. Still needed?
        // 2022-06-27 We comment the following line, it shouldn't be necessary now.
        // _ = await NewAppStateManager.shared.waitUntilAppIsInitialized()

        // We first check that there is no ongoing call before allowing a new call
        
        for currentCall in currentCalls {
            guard await currentCall.state.isFinalState else {
                os_log("☎️ Trying to create a new outgoing call while another (not finished) call exists is not allowed", log: Self.log, type: .error)
                return
            }
        }
        
        let granted = await AVAudioSession.sharedInstance().requestRecordPermission()
        if granted {
            await initiateCall(with: contactIds, groupId: groupId)
        } else {
            ObvMessengerInternalNotification.outgoingCallFailedBecauseUserDeniedRecordPermission
                .postOnDispatchQueue(queueForPostingNotifications)
        }

    }


    private func processUserWantsToKickParticipant(call: GenericCall, callParticipant: CallParticipant) async {
        guard let call = call as? Call else {
            os_log("☎️ Unknown call type", log: Self.log, type: .fault)
            assertionFailure()
            return
        }
        guard let outgoingCall = currentOutgoingCalls.first(where: { $0.uuidForWebRTC == call.uuidForWebRTC }) else { return }
        do {
            try await outgoingCall.processUserWantsToKickParticipant(callParticipant: callParticipant)
        } catch {
            os_log("☎️ Could not properly kick participant: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }


    private func processUserWantsToAddParticipants(call: GenericCall, contactIds: [OlvidUserId]) async {
        guard !contactIds.isEmpty else { assertionFailure(); return }
        guard let call = call as? Call else {
            os_log("Unknown call type", log: Self.log, type: .fault)
            assertionFailure()
            return
        }
        guard currentOutgoingCalls.first(where: { $0.uuidForWebRTC == call.uuidForWebRTC }) != nil else { return }
        guard call.direction == .outgoing else { return }
        do {
            try await call.processUserWantsToAddParticipants(contactIds: contactIds)
        } catch {
            os_log("☎️ Could not process processUserWantsToAddParticipants: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }
    }
}


// MARK: - Incoming/Outgoing Call Delegate

extension CallManager: IncomingCallDelegate, OutgoingCallDelegate {

    func turnCredentialsRequiredByOutgoingCall(outgoingCallUuidForWebRTC: UUID, forOwnedIdentity ownedIdentityCryptoId: ObvCryptoId) async {
        obvEngine.getTurnCredentials(ownedIdenty: ownedIdentityCryptoId, callUuid: outgoingCallUuidForWebRTC)
    }

}


// MARK: - Helpers

extension CallManager {

    /// This method sends a `RingingMessageJSON` to the caller. It makes sure this message is sent only once.
    private func sendRingingMessageToCaller(forIncomingCall call: Call) async {
        assert(call.direction == .incoming)
        os_log("☎️ Within sendRingingMessageToCaller", log: Self.log, type: .info)
        await call.sendRingingMessageToCaller()
    }

}


// MARK: - Actions

extension CallManager {

    private func initiateCall(with contactIds: [OlvidUserId], groupId: GroupIdentifierBasedOnObjectID?) async {

        guard !contactIds.isEmpty else { assertionFailure(); return }

        os_log("☎️ initiateCall with %{public}@", log: Self.log, type: .info, contactIds.map { $0.debugDescription }.joined(separator: ", "))

        do {
            try ObvAudioSessionUtils.shared.configureAudioSessionForMakingOrAnsweringCall()
        } catch {
            os_log("☎️ Failed to configure audio session: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure() // Continue anyway
        }

        let sortedContactIds = contactIds.sorted(by: { $0.displayName < $1.displayName })

        let outgoingCall: Call
        do {
            outgoingCall = try await createOutgoingCall(contactIds: sortedContactIds, groupId: groupId)
            assert(outgoingCall.direction == .outgoing)
        } catch {
            os_log("☎️ Could not create outgoing call: %{public}@", log: Self.log, type: .error, error.localizedDescription)
            assertionFailure()
            return
        }

        guard let firstContactId = contactIds.first else { return }
        let firstContactDisplayName = firstContactId.displayName

        let outgoingCallUuid = outgoingCall.uuid
        let handleValue: String = String(outgoingCallUuid)

        do {
            try await outgoingCall.initializeCall(contactIdentifier: firstContactDisplayName, handleValue: handleValue)
        } catch {
            os_log("☎️ Start call failed: %{public}@", log: Self.log, type: .error, error.localizedDescription)
            await outgoingCall.endCallAsOutgoingCallInitializationFailed()
            return
        }
    }

}


// MARK: - Call Delegate

extension CallManager {

    static func report(call: Call, report: CallReport) {
        let ownedIdentity = call.ownedIdentity
        os_log("☎️📖 Report call to user as %{public}@", log: Self.log, type: .info, report.description)
        VoIPNotification.reportCallEvent(callUUID: call.uuid, callReport: report, groupId: call.groupId, ownedCryptoId: ownedIdentity)
            .postOnDispatchQueue()
    }


    func newParticipantWasAdded(call: Call, callParticipant: CallParticipant) async {
        switch call.direction {
        case .incoming:
            Self.report(call: call, report: .newParticipantInIncomingCall(callParticipant.info))
        case .outgoing:
            Self.report(call: call, report: .newParticipantInOutgoingCall(callParticipant.info))
        }
        let callUpdate = await ObvCallUpdateImpl.make(with: call)
        self.provider(isCallKit: call.usesCallKit).reportCall(with: call.uuid, updated: callUpdate)
    }


    func callReachedFinalState(call: Call) async {
        do {
            try await removeCallFromCurrentCalls(call: call)
        } catch {
            os_log("Could not remove call from current calls: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }


    func outgoingCallReachedReachedInProgressState(call: Call) async {
        assert(call.direction == .outgoing)
        provider(isCallKit: call.usesCallKit).reportOutgoingCall(with: call.uuid, connectedAt: nil)
    }


    /// This call delegate method gets called when a call is ended in an out-of-band manner, i.e., not because the local user decided to end the call.
    /// In that case, we want to report this information to CallKit.
    func callOutOfBoundEnded(call: Call, reason: ObvCallEndedReason) async {
        let callState = await call.state
        assert(callState.isFinalState)
        provider(isCallKit: call.usesCallKit).reportCall(with: call.uuid, endedAt: nil, reason: reason)
    }

}


// MARK: - ObvProviderDelegate

extension CallManager: ObvProviderDelegate {

    func providerDidBegin() async {
        os_log("☎️ Provider did begin", log: Self.log, type: .info)
    }


    func providerDidReset() async {
        os_log("☎️ Provider did reset", log: Self.log, type: .info)
    }


    func provider(perform action: ObvStartCallAction) async {

        os_log("☎️ Provider perform action: %{public}@", log: Self.log, type: .info, action.debugDescription)

        guard let outgoingCall = currentCalls.first(where: { $0.uuid == action.callUUID && $0.direction == .outgoing }) else {
            os_log("☎️ Could not start call, call not found", log: Self.log, type: .fault)
            action.fail()
            assertionFailure()
            return
        }

        do {
            try await outgoingCall.startCall()
        } catch(let error) {
            os_log("☎️ startCall failed: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            await outgoingCall.endCallAsOutgoingCallInitializationFailed()
            action.fail()
            assertionFailure()
            return
        }

        action.fulfill()

        // If we stop here, the name displayed within iOS call log is incorrect (it shows the CoreData instance's URI). Updating the call right now does the trick.
        let callUpdate = await ObvCallUpdateImpl.make(with: outgoingCall)
        provider(isCallKit: outgoingCall.usesCallKit).reportCall(with: outgoingCall.uuid, updated: callUpdate)

        // At this point, credentials have been requested to the engine (when calling outgoingCall.startCall() above).
        // The outgoing call will evolve when receiving these credentials.
    }


    func provider(perform action: ObvAnswerCallAction) async {

        os_log("☎️ Provider perform answer call action", log: Self.log, type: .info)

        guard let call = currentCalls.first(where: { $0.uuid == action.callUUID && $0.direction == .incoming }) else {
            os_log("☎️ Could not answer call: could not find the call within the current calls", log: Self.log, type: .fault)
            action.fail()
            return
        }

        guard AVAudioSession.sharedInstance().recordPermission == .granted else {
            os_log("☎️ We reject the call since there is no record permission", log: Self.log, type: .fault)
            await call.endCallBecauseOfMissingRecordPermission()
            action.fail()
            return
        }

        guard await !call.userDidAnsweredIncomingCall() else {
            action.fail()
            return
        }

        /* Although https://www.youtube.com/watch?v=_64EiziqbuE @ 20:35 says that we should not configure
         * the audio here, we do so anyway. Otherwise, CallKit does not call the
         * func provider(didActivate audioSession: AVAudioSession)
         * delegate method in the case the call is received when the screen is locked.
         */
        do {
            try ObvAudioSessionUtils.shared.configureAudioSessionForMakingOrAnsweringCall()
        } catch {
            os_log("☎️🎵 Could not configure the audio session: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            action.fail()
            assertionFailure()
            return
        }

        do {
            try await call.answerWebRTCCall()
        } catch {
            os_log("☎️ Failed to answer WebRTC call: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            action.fail()
            assertionFailure()
            return
        }

        action.fulfill()

        await Self.report(call: call, report: .acceptedIncomingCall(caller: call.callerCallParticipant?.info))
    }


    /// This delegate method is called when the local user ends the call from the CallKit UI or from the Olvid UI.
    func provider(perform action: ObvEndCallAction) async {

        os_log("☎️🛑 Provider perform end call action for call with UUID %{public}@", log: Self.log, type: .info, action.callUUID as CVarArg)

        guard let call = currentCalls.first(where: { $0.uuid == action.callUUID }) else {
            os_log("Cannot find call after performing ObvEndCallAction", log: Self.log, type: .fault)
            action.fail()
            assertionFailure()
            return
        }

        await call.userRequestedToEndCallWasFulfilled()

        action.fulfill()

    }


    func provider(perform action: ObvSetHeldCallAction) async {
        os_log("☎️ Provider perform set held call action", log: Self.log, type: .info)
        action.fulfill()
        assertionFailure("Not implemented")
    }


    func provider(perform action: ObvSetMutedCallAction) async {
        os_log("☎️ Provider perform set muted call action", log: Self.log, type: .info)
        guard let call = currentCalls.first(where: { $0.uuid == action.callUUID }) else { action.fail(); return }
        if action.isMuted {
            await call.muteSelfForOtherParticipants()
        } else {
            await call.unmuteSelfForOtherParticipants()
        }
        action.fulfill()
    }


    func provider(perform action: ObvPlayDTMFCallAction) async {
        os_log("☎️ Provider perform play DTMF action", log: Self.log, type: .info)
        action.fulfill()
    }


    func provider(timedOutPerforming action: ObvAction) async {
        os_log("☎️ Provider timed out performing action %{public}@", log: Self.log, type: .info, action.debugDescription)
        action.fulfill()
    }


    func provider(didActivate audioSession: AVAudioSession) async {
        // See https://stackoverflow.com/a/55781328
        os_log("☎️🎵 Provider did activate audioSession %{public}@", log: Self.log, type: .info, audioSession.description)
        RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
        RTCAudioSession.sharedInstance().isAudioEnabled = true
    }


    func provider(didDeactivate audioSession: AVAudioSession) async {
        os_log("☎️🎵 Provider did deactivate audioSession %{public}@", log: Self.log, type: .info, audioSession.description)
        RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
        RTCAudioSession.sharedInstance().isAudioEnabled = false
    }

}


// MARK: - Extensions / Helpers

fileprivate extension EncryptedPushNotification {

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


fileprivate extension ObvCallUpdateImpl {

    static func make(with call: Call) async -> ObvCallUpdate {
        var update = ObvCallUpdateImpl()
        let callParticipants = await call.getCallParticipants()
        let sortedContacts: [(isCaller: Bool, displayName: String)] = callParticipants.map {
            let displayName = $0.displayName
            return ($0.role == .caller, displayName)
        }.sorted {
            if $0.isCaller { return true }
            if $1.isCaller { return false }
            return $0.displayName < $1.displayName
        }

        update.remoteHandle_ = ObvHandleImpl(type_: .generic, value: String(call.uuid))
        if call.direction == .incoming && sortedContacts.count == 1 {
            update.localizedCallerName = sortedContacts.first?.displayName
            if call.initialParticipantCount > 1 {
                update.localizedCallerName! += " + \(call.initialParticipantCount - 1)"
            }
        } else if sortedContacts.count > 0 {
            let contactName = sortedContacts.map({ $0.displayName }).joined(separator: ", ")
            update.localizedCallerName = contactName
        } else {
            update.localizedCallerName = "..."
        }
        update.hasVideo = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsHolding = false
        update.supportsDTMF = false
        return update
    }


    static func make(with encryptedNotification: EncryptedPushNotification) -> (uuidForCallKit: UUID, obvCallUpdate: ObvCallUpdate) {
        var update = ObvCallUpdateImpl()
        let uuidForCallKit = UUID()
        update.remoteHandle_ = ObvHandleImpl(type_: .generic, value: String(uuidForCallKit))
        update.localizedCallerName = "..."
        update.hasVideo = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsHolding = false
        update.supportsDTMF = false
        return (uuidForCallKit, update)
    }

}


// MARK: - ContactInfo

protocol ContactInfo {
    var objectID: TypeSafeManagedObjectID<PersistedObvContactIdentity> { get }
    var ownedIdentity: ObvCryptoId? { get }
    var cryptoId: ObvCryptoId? { get }
    var fullDisplayName: String { get }
    var customDisplayName: String? { get }
    var sortDisplayName: String { get }
    var photoURL: URL? { get }
    var identityColors: (background: UIColor, text: UIColor)? { get }
    var gatheringPolicy: GatheringPolicy { get }
}


// MARK: - ContactInfoImpl

struct ContactInfoImpl: ContactInfo {
    var objectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>
    var ownedIdentity: ObvCryptoId?
    var cryptoId: ObvCryptoId?
    var fullDisplayName: String
    var customDisplayName: String?
    var sortDisplayName: String
    var photoURL: URL?
    var identityColors: (background: UIColor, text: UIColor)?
    var gatheringPolicy: GatheringPolicy

    init(contact persistedContactIdentity: PersistedObvContactIdentity) {
        self.objectID = persistedContactIdentity.typedObjectID
        self.ownedIdentity = persistedContactIdentity.ownedIdentity?.cryptoId
        self.cryptoId = persistedContactIdentity.cryptoId
        self.fullDisplayName = persistedContactIdentity.fullDisplayName
        self.customDisplayName = persistedContactIdentity.customDisplayName
        self.sortDisplayName = persistedContactIdentity.sortDisplayName
        self.photoURL = persistedContactIdentity.customPhotoURL ?? persistedContactIdentity.photoURL
        self.identityColors = persistedContactIdentity.cryptoId.colors
        self.gatheringPolicy = persistedContactIdentity.supportsCapability(.webrtcContinuousICE) ? .gatherContinually : .gatherOnce
    }
}


// MARK: - GatheringPolicy

extension GatheringPolicy {
    var rtcPolicy: RTCContinualGatheringPolicy {
        switch self {
        case .gatherOnce: return .gatherOnce
        case .gatherContinually: return .gatherContinually
        }
    }
}



// MARK: - ObvPushRegistryHandler

/// We create one instance of this class when instantiating the call coordinator. This instance handles the interaction with the PushKit registry as it register to VoIP push notifications and
/// Receives incoming pushes. When an incoming VoIP push notification is received, it reports it (as required by Apple specifications) then calls its delegate (the call coordinator).
fileprivate final class ObvPushRegistryHandler: NSObject, PKPushRegistryDelegate {

    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: CallManager.self))

    private let obvEngine: ObvEngine
    private let cxObvProvider: CXObvProvider
    private var didRegisterToVoIPNotifications = false
    private var voipRegistry: PKPushRegistry!
    private let internalQueue = DispatchQueue(label: "ObvPushRegistryHandler internal queue")

    weak var delegate: ObvPushRegistryHandlerDelegate?

    init(obvEngine: ObvEngine, cxObvProvider: CXObvProvider) {
        self.obvEngine = obvEngine
        self.cxObvProvider = cxObvProvider
        super.init()
    }


    func registerForVoIPPushes(delegate: ObvPushRegistryHandlerDelegate) {
        internalQueue.async { [weak self] in
            guard let _self = self else { return }
            guard !_self.didRegisterToVoIPNotifications else { return }
            defer { _self.didRegisterToVoIPNotifications = true }
            assert(_self.delegate == nil)
            _self.delegate = delegate
            os_log("☎️ Registering for VoIP push notifications", log: Self.log, type: .info)
            _self.voipRegistry = PKPushRegistry(queue: _self.internalQueue)
            _self.voipRegistry.delegate = self
            _self.voipRegistry.desiredPushTypes = [.voIP]
        }
    }


    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        let voipToken = pushCredentials.token
        os_log("☎️✅ We received a voip notification token: %{public}@", log: Self.log, type: .info, voipToken.hexString())
        Task {
            await ObvPushNotificationManager.shared.setCurrentVoipToken(to: voipToken)
            await ObvPushNotificationManager.shared.tryToRegisterToPushNotifications()
        }
    }


    // Implementing PKPushRegistryDelegate

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        os_log("☎️✅❌ Push Registry did invalidate push token", log: Self.log, type: .info)
        Task {
            await ObvPushNotificationManager.shared.setCurrentVoipToken(to: nil)
            await ObvPushNotificationManager.shared.tryToRegisterToPushNotifications()
        }
    }


    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {

        os_log("☎️✅ We received a voip notification", log: Self.log, type: .info)

        guard let encryptedNotification = EncryptedPushNotification(dict: payload.dictionaryPayload) else {
            os_log("☎️ Could not extract encrypted notification", log: Self.log, type: .fault)
            // We are not be able to make a link between this call and the received StartCallMessageJSON, we report a cancelled call to respect PushKit constraints.
            cxObvProvider.reportNewCancelledIncomingCall()
            assertionFailure()
            return
        }

        // We request the immediate decryption of the encrypted notification. This call returns nothing.
        // Eventually, we should receive a NewWebRTCMessageWasReceived notification from the discussion coordinator,
        // Containing the decrypted data. Calling this method here is an optimization (we could also wait for the same
        // Message arriving through the websocket).

        tryDecryptAndProcessEncryptedNotification(encryptedNotification)

        let (uuidForCallKit, callUpdate) = ObvCallUpdateImpl.make(with: encryptedNotification)

        os_log("☎️✅ We will report new incoming call to CallKit", log: Self.log, type: .info)

        cxObvProvider.reportNewIncomingCall(with: uuidForCallKit, update: callUpdate) { result in
            switch result {
            case .failure(let error):
                os_log("☎️✅❌ We failed to report an incoming call: %{public}@", log: Self.log, type: .info, error.localizedDescription)
                Task { [weak self] in
                    await self?.delegate?.failedToReportNewIncomingCallToCallKit(callUUID: uuidForCallKit, error: error)
                    DispatchQueue.main.async {
                        completion()
                    }
                }
            case .success:
                Task { [weak self] in
                    os_log("☎️✅ We successfully reported an incoming call to CallKit", log: Self.log, type: .info)
                    await self?.delegate?.successfullyReportedNewIncomingCallToCallKit(uuidForCallKit: uuidForCallKit, messageIdentifierFromEngine: encryptedNotification.messageIdentifierFromEngine)
                    DispatchQueue.main.async {
                        completion()
                    }
                }
            }
        }

    }


    private func tryDecryptAndProcessEncryptedNotification(_ encryptedNotification: EncryptedPushNotification) {
        let obvMessage: ObvMessage
        do {
            obvMessage = try obvEngine.decrypt(encryptedPushNotification: encryptedNotification)
        } catch {
            os_log("☎️ Could not decrypt received voip notification, the contained message has certainly been decrypted after being received by the webSocket", log: Self.log, type: .info)
            return
        }
        // We send the obvMessage to the PersistedDiscussionsUpdatesCoordinator, who will pass us back an StartCallMessageJSON
        ObvMessengerInternalNotification.newObvMessageWasReceivedViaPushKitNotification(obvMessage: obvMessage)
            .postOnDispatchQueue()
    }

}


protocol ObvPushRegistryHandlerDelegate: IncomingCallDelegate {

    func failedToReportNewIncomingCallToCallKit(callUUID: UUID, error: Error) async
    func successfullyReportedNewIncomingCallToCallKit(uuidForCallKit: UUID, messageIdentifierFromEngine: Data) async

}
