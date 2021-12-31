/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

final class CallCoordinator: NSObject {

    private static let errorDomain = "CallCoordinator"
    private func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: CallCoordinator.errorDomain, code: 0, userInfo: userInfo)
    }

    private var voipRegistry: PKPushRegistry!

    private var currentCalls = [Call]()
    private var messageIdentifiersFromEngineOfRecentlyDeletedIncomingCalls = [Data]()
    private var currentIncomingCalls: [IncomingCall] { currentCalls.compactMap({ $0 as? IncomingCall }) }
    private var currentOutgoingCalls: [OutgoingCall] { currentCalls.compactMap({ $0 as? OutgoingCall }) }
    private var remotelyHangedUpCalls = Set<UUID>()

    private func addCallToCurrentCallsAndNotify(call: Call) {
        CallHelper.checkQueue() // OK
        assert(call.state == .initial)
        os_log("☎️ Adding call to the list of current calls", log: log, type: .info)
        assert(currentCalls.first(where: { $0.uuid == call.uuid }) == nil, "Trying to add a call that already exists in the list of current calls")
        currentCalls.append(call)
    }


    private func removeCallFromCurrentCalls(call: Call) {
        os_log("☎️ Removing call from the list of current calls", log: log, type: .info)
        CallHelper.checkQueue() // OK
        assert(call.state.isFinalState)
        currentCalls.removeAll(where: { $0.uuid == call.uuid })
        if currentCalls.isEmpty { currentCalls = [] } // Yes, we need to make sure the calls are properly freed...
        if let incomingCall = call as? IncomingCall {
            messageIdentifiersFromEngineOfRecentlyDeletedIncomingCalls.append(incomingCall.messageIdentifierFromEngine)
        }
        if let newCall = currentCalls.first {
            assert(!newCall.state.isFinalState)
            ObvMessengerInternalNotification.callHasBeenUpdated(call: newCall, updateKind: .state(newState: newCall.state)).postOnDispatchQueue()
        } else {
            ObvMessengerInternalNotification.noMoreCallInProgress.postOnDispatchQueue()
        }
    }


    private func createIncomingCall(encryptedPushKitNotification: EncryptedPushNotification) -> IncomingCall? {
        CallHelper.checkQueue() // OK
        guard !messageIdentifiersFromEngineOfRecentlyDeletedIncomingCalls.contains(encryptedPushKitNotification.messageIdentifierFromEngine) else {
            return nil
        }
        let incomingCall = IncomingWebrtcCall(encryptedPushNotification: encryptedPushKitNotification, delegate: self)
        addCallToCurrentCallsAndNotify(call: incomingCall)
        return incomingCall
    }

    private func createIncomingCall(incomingCallMessage: IncomingCallMessageJSON, contactID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, uuidForWebRTC: UUID, messageIdentifierFromEngine: Data, messageUploadTimestampFromServer: Date) throws -> IncomingCall {
        CallHelper.checkQueue() // OK
        guard !messageIdentifiersFromEngineOfRecentlyDeletedIncomingCalls.contains(messageIdentifierFromEngine) else {
            throw makeError(message: "Call was recently deleted")
        }
        let incomingCall = IncomingWebrtcCall(incomingCallMessage: incomingCallMessage,
                                              contactID: contactID,
                                              uuidForWebRTC: uuidForWebRTC,
                                              messageIdentifierFromEngine: messageIdentifierFromEngine,
                                              messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                                              delegate: self,
                                              useCallKit: ObvMessengerSettings.VoIP.isCallKitEnabled)
        addCallToCurrentCallsAndNotify(call: incomingCall)
        return incomingCall
    }

    private func createOutgoingCall(contactIDs: [TypeSafeManagedObjectID<PersistedObvContactIdentity>],
                                    groupId: (groupUid: UID, groupOwner: ObvCryptoId)?) -> OutgoingCall {
        CallHelper.checkQueue() // OK
        let outgoingCall = OutgoingWebRTCCall(contactIDs: contactIDs, delegate: self, usesCallKit: ObvMessengerSettings.VoIP.isCallKitEnabled, groupId: groupId)
        addCallToCurrentCallsAndNotify(call: outgoingCall)
        return outgoingCall
    }

    private var currentAnswerCallActions = [UUID: ObvAnswerCallAction]()

    private var pushKitCompletionForIncomingCall = [UUID: () -> Void]()

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: CallCoordinator.self))
    private let obvEngine: ObvEngine
    private var notificationTokens = [NSObjectProtocol]()
    private var notificationForVoIPRegister: NSObjectProtocol?
    private var didRegisterToVoIPNotifications = false
    private var callToPerformAfterAppStateBecomesActive: (contactIDs: [TypeSafeManagedObjectID<PersistedObvContactIdentity>], groupId: (groupUid: UID, groupOwner: ObvCryptoId)?)? = nil

    private var cxProvider: CXObvProvider?
    private var ncxProvider: NCXObvProvider?
    private func provider(isCallKit: Bool) -> ObvProvider {
        RTCAudioSession.sharedInstance().useManualAudio = isCallKit
        if isCallKit {
            Concurrency.sync(lock: "Synchronize CXObvProvider.instance") {
                if cxProvider == nil {
                    cxProvider = CXObvProvider(configuration: type(of: self).providerConfiguration)
                    cxProvider!.setDelegate(self, queue: DispatchQueue.main)
                }
            }
            return cxProvider!
        } else {
            Concurrency.sync(lock: "Synchronize NCXObvProvider.instance") {
                if ncxProvider == nil {
                    ncxProvider = NCXObvProvider.instance
                    ncxProvider?.setConfiguration(type(of: self).providerConfiguration)
                    ncxProvider!.setDelegate(self, queue: DispatchQueue.main)
                }
            }
            return ncxProvider!
        }
    }

    init(obvEngine: ObvEngine) {
        self.obvEngine = obvEngine

        super.init()
        listenToNotifications()
        /// Force provider initialization
        _ = provider(isCallKit: ObvMessengerSettings.VoIP.isCallKitEnabled)


        if AppStateManager.shared.currentState.isInitialized {
            registerForVoIPPushes()
        } else {
            let log = self.log
            notificationForVoIPRegister = ObvMessengerInternalNotification.observeAppStateChanged { [weak self] _, currentState in
                os_log("☎️ The call coordinator observed that the app state did change to %{public}@", log: log, type: .info, currentState.debugDescription)
                guard currentState.isInitialized else { return }
                os_log("☎️ Since the app is initialized, we can register for VoIP push notifications", log: log, type: .info)
                if let notificationForVoIPRegister = self?.notificationForVoIPRegister {
                    NotificationCenter.default.removeObserver(notificationForVoIPRegister)
                    self?.notificationForVoIPRegister = nil
                }
                self?.registerForVoIPPushes()
            }
        }
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

    func registerForVoIPPushes() {
        let log = self.log
        DispatchQueue.main.async {
            guard !self.didRegisterToVoIPNotifications else { return }
            defer { self.didRegisterToVoIPNotifications = true }
            os_log("☎️ Registering for VoIP push notifications", log: log, type: .info)
            self.voipRegistry = PKPushRegistry(queue: nil)
            self.voipRegistry.delegate = self
            self.voipRegistry.desiredPushTypes = [.voIP]
        }
    }

    private func listenToNotifications() {
        notificationTokens.append(ObvMessengerInternalNotification.observeNewWebRTCMessageWasReceived(object: nil, queue: OperationQueue.main) { [weak self] (webrtcMessage, contactID, messageUploadTimestampFromServer, messageIdentifierFromEngine) in
            self?.processReceivedWebRTCMessage(messageType: webrtcMessage.messageType, serializedMessagePayload: webrtcMessage.serializedMessagePayload, callIdentifier: webrtcMessage.callIdentifier, contact: .persisted(contactID), messageUploadTimestampFromServer: messageUploadTimestampFromServer, messageIdentifierFromEngine: messageIdentifierFromEngine)
        })
        notificationTokens.append(ObvMessengerInternalNotification.observeUserWantsToCallAndIsAllowedTo(object: nil, queue: OperationQueue.main) { [weak self] (contactIDs, groupId) in
            self?.processUserWantsToCallNotification(contactIDs: contactIDs, groupId: groupId)
        })
        notificationTokens.append(ObvMessengerInternalNotification.observeCallHasBeenUpdated(queue: OperationQueue.main) { [weak self] (call, updateKind) in
            self?.processCallHasBeenUpdatedNotification(call: call, updateKind: updateKind)
        })
        notificationTokens.append(ObvEngineNotificationNew.observeCallerTurnCredentialsReceived(within: NotificationCenter.default, queue: OperationQueue.main) { [weak self] (ownedIdentity, callUuid, turnCredentials) in
            self?.processCallerTurnCredentialsReceivedNotification(ownedIdentity: ownedIdentity, uuidForWebRTC: callUuid, turnCredentials: turnCredentials)
        })
        notificationTokens.append(ObvEngineNotificationNew.observeCallerTurnCredentialsReceptionFailure(within: NotificationCenter.default, queue: OperationQueue.main) { [weak self] (ownedIdentity, callUuid) in
            self?.processCallerTurnCredentialsReceptionFailureNotification(ownedIdentity: ownedIdentity, uuidForWebRTC: callUuid)
        })
        notificationTokens.append(ObvEngineNotificationNew.observeCallerTurnCredentialsReceptionPermissionDenied(within: NotificationCenter.default, queue: OperationQueue.main) { [weak self] (ownedIdentity, callUuid) in
            self?.processCallerTurnCredentialsReceptionPermissionDeniedNotification(ownedIdentity: ownedIdentity, uuidForWebRTC: callUuid)
        })
        notificationTokens.append(ObvEngineNotificationNew.observeCallerTurnCredentialsServerDoesNotSupportCalls(within: NotificationCenter.default, queue: OperationQueue.main) { [weak self] (ownedIdentity, callUuid) in
            self?.processTurnCredentialsServerDoesNotSupportCalls(ownedIdentity: ownedIdentity, uuidForWebRTC: callUuid)
        })
        notificationTokens.append(ObvMessengerInternalNotification.observeNetworkInterfaceTypeChanged(queue: OperationQueue.main) { [weak self] (isConnected) in
            self?.processNetworkStatusChangedNotification(isConnected: isConnected)
        })
        notificationTokens.append(ObvMessengerInternalNotification.observeIsCallKitEnabledSettingDidChange(queue: OperationQueue.main) { [weak self] in
            self?.processIsCallKitEnabledSettingDidChangeNotification()
        })
        notificationTokens.append(ObvMessengerInternalNotification.observeIsIncludesCallsInRecentsEnabledSettingDidChange(queue: OperationQueue.main) { [weak self] in
            self?.processIsIncludesCallsInRecentsEnabledSettingDidChangeNotification()
        })
        notificationTokens.append(ObvMessengerInternalNotification.observeUserWantsToKickParticipant(queue: OperationQueue.main) { [weak self] (call, callParticipant) in
            self?.processUserWantsToKickParticipant(call: call, callParticipant: callParticipant)
        })
        notificationTokens.append(ObvMessengerInternalNotification.observeUserWantsToAddParticipants(queue: OperationQueue.main) { [weak self] (call, contactIDs) in
            self?.processUserWantsToAddParticipants(call: call, contactIDs: contactIDs)
        })
        notificationTokens.append(ObvMessengerInternalNotification.observeAppStateChanged(queue: OperationQueue.main) { [weak self] (_, currentState) in
            self?.processAppStateChangedNotification(currentState: currentState)
        })

    }

}


extension CallCoordinator {

    private func processIsCallKitEnabledSettingDidChangeNotification() {
        CallHelper.checkQueue() // OK
                                /// Force provider initialization
        _ = provider(isCallKit: ObvMessengerSettings.VoIP.isCallKitEnabled)
    }

    private func processIsIncludesCallsInRecentsEnabledSettingDidChangeNotification() {
        CallHelper.checkQueue() // OK
        let provider = self.provider(isCallKit: ObvMessengerSettings.VoIP.isCallKitEnabled)
        var configuration = provider.configuration_
        configuration.includesCallsInRecents = ObvMessengerSettings.VoIP.isIncludesCallsInRecentsEnabled
        provider.configuration_ = configuration
    }

    private func processNetworkStatusChangedNotification(isConnected: Bool) {
        CallHelper.checkQueue() // OK
        for call in currentCalls {
            call.createRestartOffer()
        }
    }


    private func processCallerTurnCredentialsReceptionFailureNotification(ownedIdentity: ObvCryptoId, uuidForWebRTC: UUID) {
        CallHelper.checkQueue() // OK
        os_log("☎️ Processing a CallerTurnCredentialsReceptionFailure notification", log: log, type: .fault)
        guard let call = currentOutgoingCalls.first(where: { $0.uuidForWebRTC == uuidForWebRTC }) else { return }
        call.endCall()
    }

    private func processCallerTurnCredentialsReceptionPermissionDeniedNotification(ownedIdentity: ObvCryptoId, uuidForWebRTC: UUID) {
        CallHelper.checkQueue() // OK
        os_log("☎️ Processing a CallerTurnCredentialsReceptionPermissionDenied notification", log: log, type: .fault)
        guard let call = currentOutgoingCalls.first(where: { $0.uuidForWebRTC == uuidForWebRTC }) else { return }
        call.setPermissionDeniedByServer()
    }

    private func processTurnCredentialsServerDoesNotSupportCalls(ownedIdentity: ObvCryptoId, uuidForWebRTC: UUID) {
        CallHelper.checkQueue() // OK
        os_log("☎️ Processing a TurnCredentialsServerDoesNotSupportCalls notification", log: log, type: .fault)
        guard let call = currentOutgoingCalls.first(where: { $0.uuidForWebRTC == uuidForWebRTC }) else { return }
        call.setCallInitiationNotSupported()
        ObvMessengerInternalNotification.serverDoesNotSupportCall.postOnDispatchQueue()
    }

    private func processCallerTurnCredentialsReceivedNotification(ownedIdentity: ObvCryptoId, uuidForWebRTC: UUID, turnCredentials: ObvTurnCredentials) {
        CallHelper.checkQueue() // OK
        let currentOutgoingCalls = self.currentCalls.compactMap({ $0 as? OutgoingWebRTCCall })
        guard let outgoingCall = currentOutgoingCalls.first(where: { $0.uuidForWebRTC == uuidForWebRTC }) else { return }
        outgoingCall.setTurnCredentials(turnCredentials: turnCredentials)
        outgoingCall.offerCall()
    }


    func processCallHasBeenUpdatedNotification(call: Call, updateKind: CallUpdateKind) {
        CallHelper.checkQueue() // OK
        switch updateKind {
        case .state:
            if call.state.isFinalState {
                removeCallFromCurrentCalls(call: call)
            }
        case .mute:
            break
        case .callParticipantChange:
            if call.callParticipants.isEmpty {
                call.endCall()
            }
        }
    }

}

// MARK: - PKPushRegistryDelegate

extension CallCoordinator: PKPushRegistryDelegate {

    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        CallHelper.checkQueue() // OK
        switch pushCredentials.type {
        case .voIP:
            let voipToken = pushCredentials.token
            os_log("☎️✅ We received a voip notification token: %{public}@", log: log, type: .info, voipToken.hexString())
            ObvPushNotificationManager.shared.currentVoipToken = voipToken
            ObvPushNotificationManager.shared.tryToRegisterToPushNotifications()
        case .complication, .fileProvider:
            assertionFailure()
        default:
            assertionFailure()
        }
    }


    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        CallHelper.checkQueue() // OK
        os_log("☎️❌ Push Registry did invalidate push token", log: log, type: .info)
        ObvPushNotificationManager.shared.currentVoipToken = nil
        ObvPushNotificationManager.shared.tryToRegisterToPushNotifications()
    }


    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        CallHelper.checkQueue() // OK

        guard type == .voIP else { completion(); assertionFailure(); return }
        os_log("☎️✅ We received a voip notification", log: log, type: .info)
        let log = self.log

        let myCompletion = {
            os_log("☎️ Calling the PushKit completion handler", log: log, type: .info)
            DispatchQueue.main.async {
                completion()
            }
        }

        guard let encryptedNotification = EncryptedPushNotification(dict: payload.dictionaryPayload) else {
            os_log("☎️ Could not extract encrypted notification", log: log, type: .fault)
            /// We are not be able to make a link between this call and the received IncomingCallMessageJSON , we report a cancelled call to respect PushKit constraints.
            self.provider(isCallKit: true).reportNewCancelledIncomingCall() {
                myCompletion()
            }
            assertionFailure()
            return
        }

        let incomingCall: IncomingCall
        if let _incomingCall = self.currentIncomingCalls.filter({ $0.messageIdentifierFromEngine == encryptedNotification.messageIdentifierFromEngine }).first {
            /// This happens in the case we already received the IncomingCallMessageJSON message
            os_log("☎️🐰 The incoming call already exists, the websocket was faster than the VoIP notification", log: log, type: .info)
            incomingCall = _incomingCall
            _incomingCall.pushKitNotificationReceived()
        } else if let _incomingCall = self.createIncomingCall(encryptedPushKitNotification: encryptedNotification) {
            /// The call does not exists, we create a call without information and wait for the IncomingCallMessageJSON to get the information
            os_log("☎️🐰 The incoming call does not exist yet, the VoIP notification was faster than the websocket", log: log, type: .info)
            incomingCall = _incomingCall
        } else {
            /// The call is already ended, we report a call to respect PushKit constraints
            os_log("☎️🐰 The call was already ended", log: log, type: .info)
            self.provider(isCallKit: true).reportNewCancelledIncomingCall() {
                myCompletion()
            }
            return
        }
        assert(incomingCall.usesCallKit)

        let update = ObvCallUpdateImpl.make(with: incomingCall, engine: self.obvEngine)
        os_log("☎️ Call to reportNewIncomingCall", log: log, type: .info)

        func decryptAndSendPushKitNotification() {
            DispatchQueue(label: "Queue for decrypting and encrypted PushKit notification").async {
                do {
                    let obvMessage = try self.obvEngine.decrypt(encryptedPushNotification: encryptedNotification)
                    /// We send the obvMessage to the PersistedDiscussionsUpdatesCoordinator, who will pass us back an IncomingCallMessageJSON
                    ObvMessengerInternalNotification.newObvMessageWasReceivedViaPushKitNotification(obvMessage: obvMessage).postOnDispatchQueue()
                } catch {
                    os_log("☎️ Could not decrypt received voip notification, the contained message has certainly been decrypted after being received by the webSocket", log: log, type: .info)
                    /// We do *not* call the completion. It will be called when the ringing message will be sent
                    return
                }
            }
        }

        self.provider(isCallKit: true).reportNewIncomingCall(with: incomingCall.uuid, update: update) { [weak self] (error) in
            guard let _self = self else { return }
            CallHelper.checkQueue() // OK
            os_log("☎️ Inside reportNewIncomingCall", log: log, type: .info)
            guard error == nil else {
                switch error! {
                case .unknown, .unentitled, .callUUIDAlreadyExists, .maximumCallGroupsReached:
                    os_log("☎️ reportNewIncomingCall failed -> ending call", log: log, type: .error)
                    assertionFailure()
                    myCompletion()
                    return
                case .filteredByDoNotDisturb, .filteredByBlockList:
                    if let callerInfo = incomingCall.callerCallParticipant?.info {
                        os_log("☎️ reportNewIncomingCall filtered (busy/blocked) -> ending call", log: log, type: .info)
                        self?.sendRejectMessageToContact(for: incomingCall)
                        incomingCall.setUnanswered()
                        incomingCall.endCall()
                        os_log("☎️ reportNewIncomingCall filtered (busy/blocked) -> report missed call", log: log, type: .info)
                        _self.report(call: incomingCall, report: .filteredIncomingCall(caller: callerInfo, participantCount: nil))
                    } else {
                        os_log("☎️ reportNewIncomingCall filtered (busy/blocked) -> set call has been filtered", log: log, type: .info)
                        incomingCall.callHasBeenFiltered = true
                        /// To be able to report the missing call  we need to decrypt the message to be able to know the caller
                        decryptAndSendPushKitNotification()
                    }
                    /// Do not inform the caller about DoNotDisturb/BlockList
                }
                myCompletion()
                /// REMARK requests EndCallAction here does not work with CallKit
                return
            }
            /// We store the completion handler and try to send the ringing message (which only succeeds if the incomingCall message was previously received and decrypted)
            _self.pushKitCompletionForIncomingCall[incomingCall.uuid] = myCompletion
            if incomingCall.ringingMessageShouldBeSent {
                if let ringingMessageWasSent = self?.sendRingingMessageToContactIfPossible(for: incomingCall), ringingMessageWasSent {
                    incomingCall.ringingMessageShouldBeSent = false
                }
            }
            /// In case the call to `sendRingingMessageToContactIfPossible` failed, we now try to decrypt the pushkit notification content.
            /// If this succeeds, we notify the call coordinator who will notify us back with a incomingCall JSON message that, when received by this coordinator, will trigger the `sendRingingMessageToContactIfPossible` again.
            decryptAndSendPushKitNotification()
        }
    }
    
}

// MARK: - Events leading to a new call

extension CallCoordinator {

    func processReceivedWebRTCMessage(messageType: WebRTCMessageJSON.MessageType, serializedMessagePayload: String, callIdentifier: UUID, contact: ParticipantId, messageUploadTimestampFromServer: Date, messageIdentifierFromEngine: Data?) {
        CallHelper.checkQueue() // OK
        os_log("☎️ We received %{public}@ message", log: log, type: .info, messageType.description)
        switch messageType {
        case .startCall:
            do {
                let incomingCallMessage = try IncomingCallMessageJSON.decode(serializedMessagePayload: serializedMessagePayload)
                processIncomingCallMessage(incomingCallMessage, uuidForWebRTC: callIdentifier, contact: contact, messageUploadTimestampFromServer: messageUploadTimestampFromServer, messageIdentifierFromEngine: messageIdentifierFromEngine)
            } catch {
                os_log("☎️ Could not parse start call message: %{public}@", log: log, type: .fault, error.localizedDescription)
            }
        case .answerCall:
            do {
                let answerIncomingCallMessage = try AnswerIncomingCallJSON.decode(serializedMessagePayload: serializedMessagePayload)
                processAnswerIncomingCallMessage(answerIncomingCallMessage, uuidForWebRTC: callIdentifier, contact: contact, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
            } catch {
                os_log("☎️ Could not parse answer call message: %{public}@", log: log, type: .fault, error.localizedDescription)
            }
        case .rejectCall:
            do {
                let rejectCallMessage = try RejectCallMessageJSON.decode(serializedMessagePayload: serializedMessagePayload)
                processRejectCallMessage(rejectCallMessage, uuidForWebRTC: callIdentifier, contact: contact, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
            } catch {
                os_log("☎️ Could not parse reject call message: %{public}@", log: log, type: .fault, error.localizedDescription)
            }
        case .hangedUp:
            do {
                let hangedUpMessage = try HangedUpMessageJSON.decode(serializedMessagePayload: serializedMessagePayload)
                processHangedUpMessage(hangedUpMessage, uuidForWebRTC: callIdentifier, contact: contact, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
            } catch {
                os_log("☎️ Could not parse hang up message: %{public}@", log: log, type: .fault, error.localizedDescription)
            }
        case .ringing:
            do {
                _ = try RingingMessageJSON.decode(serializedMessagePayload: serializedMessagePayload)
                processRingingMessageJSON(uuidForWebRTC: callIdentifier, contact: contact, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
            } catch {
                os_log("☎️ Could not parse ringing message: %{public}@", log: log, type: .fault, error.localizedDescription)
            }
        case .busy:
            do {
                _ = try BusyMessageJSON.decode(serializedMessagePayload: serializedMessagePayload)
                processBusyMessageJSON(uuidForWebRTC: callIdentifier, contact: contact, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
            } catch {
                os_log("☎️ Could not parse busy message: %{public}@", log: log, type: .fault, error.localizedDescription)
            }
        case .reconnect:
            do {
                let reconnectCallMessage = try ReconnectCallMessageJSON.decode(serializedMessagePayload: serializedMessagePayload)
                processReconnectCallMessageJSON(reconnectCallMessage, uuidForWebRTC: callIdentifier, contact: contact, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
            } catch {
                os_log("☎️ Could not parse reconnect call message: %{public}@", log: log, type: .fault, error.localizedDescription)
            }
        case .newParticipantAnswer:
            do {
                let newParticipantAnswer = try NewParticipantAnswerMessageJSON.decode(serializedMessagePayload: serializedMessagePayload)
                processNewParticipantAnswerMessageJSON(newParticipantAnswer, uuidForWebRTC: callIdentifier, contact: contact, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
            } catch {
                os_log("☎️ Could not parse new participant answer message: %{public}@", log: log, type: .fault, error.localizedDescription)
            }
        case .newParticipantOffer:
            do {
                let newParticipantOffer = try NewParticipantOfferMessageJSON.decode(serializedMessagePayload: serializedMessagePayload)
                processNewParticipantOfferMessageJSON(newParticipantOffer, uuidForWebRTC: callIdentifier, contact: contact, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
            } catch {
                os_log("☎️ Could not parse new participant offer message: %{public}@", log: log, type: .fault, error.localizedDescription)
            }
        case .kick:
            do {
                let kickMessage = try KickMessageJSON.decode(serializedMessagePayload: serializedMessagePayload)
                processKickMessageJSON(kickMessage, uuidForWebRTC: callIdentifier, contact: contact, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
            } catch {
                os_log("☎️ Could not parse kick message: %{public}@", log: log, type: .fault, error.localizedDescription)
            }
        }
    }


    /// This method processes a received IncomingCallMessageJSON. In case we use CallKit and Olvid is in the background, this message is probably first received first within a PushKit notification, that gets decrypted very fast, which eventually triggers this method. Note that
    /// since decrypting a notification does *not* delete the decryption key, it almost certain that this method will get called a second time: the message will be fetched from the server, decrypted as usual, which eventually triggers this method again.
    private func processIncomingCallMessage(_ incomingCallMessage: IncomingCallMessageJSON, uuidForWebRTC: UUID, contact: ParticipantId, messageUploadTimestampFromServer: Date, messageIdentifierFromEngine: Data?) {
        CallHelper.checkQueue() // OK
        let log = self.log

        guard !remotelyHangedUpCalls.contains(uuidForWebRTC) else {
            return
        }

        /// We check that the `IncomingCallMessageJSON` is not too old. If this is the case, we ignore it
        let timeInterval = Date().timeIntervalSince(messageUploadTimestampFromServer) // In seconds
        guard timeInterval < WebRTCCall.callTimeout else {
            os_log("☎️ We received an old IncomingCallMessageJSON, uploaded %{timeInterval}f seconds ago on the server. We ignore it.", log: log, type: .info, timeInterval)
            return
        }

        os_log("☎️ We received a fresh IncomingCallMessageJSON, uploaded %{timeInterval}f seconds ago on the server.", log: log, type: .info, timeInterval)

        guard case let .persisted(contactID) = contact else { assertionFailure(); return }
        guard let messageIdentifierFromEngine = messageIdentifierFromEngine else { assertionFailure(); return }

        let incomingCall: IncomingCall
        if let _incomingCall = currentIncomingCalls.filter({ $0.messageIdentifierFromEngine == messageIdentifierFromEngine }).first {
            incomingCall = _incomingCall
            incomingCall.setDecryptedElements(incomingCallMessage: incomingCallMessage, contactID: contactID, uuidForWebRTC: uuidForWebRTC)
            provider(isCallKit: incomingCall.usesCallKit).reportCall(with: incomingCall.uuid, updated: ObvCallUpdateImpl.make(with: incomingCall, engine: obvEngine))
        } else {
            do {
                incomingCall = try createIncomingCall(incomingCallMessage: incomingCallMessage, contactID: contactID, uuidForWebRTC: uuidForWebRTC, messageIdentifierFromEngine: messageIdentifierFromEngine, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
            } catch {
                os_log("☎️ Could not create new incoming call: %{public}@", log: log, type: .error, error.localizedDescription)
                return
            }
        }

        guard !incomingCall.usesCallKit else {
            /// REMARK the contactID may be undecrypted in `pushRegistry didReceiveIncomingPushWith`, we used this block to preform some tasks once the contactID is decrypted.
            if incomingCall.ringingMessageShouldBeSent {
                let ringingMessageWasSent = self.sendRingingMessageToContactIfPossible(for: incomingCall)
                if ringingMessageWasSent {
                    incomingCall.ringingMessageShouldBeSent = false
                }
            }

            if incomingCall.callHasBeenFiltered {
                self.sendRejectMessageToContact(for: incomingCall)
                os_log("☎️ processIncomingCallMessage: end the filtered call", log: log, type: .info)
                incomingCall.setUnanswered()
                incomingCall.endCall()
                if let callerInfo = incomingCall.callerCallParticipant?.info {
                    os_log("☎️ processIncomingCallMessage: report a filtered call", log: log, type: .info)
                    self.report(call: incomingCall, report: .filteredIncomingCall(caller: callerInfo, participantCount: incomingCallMessage.participantCount))
                }
                return
            }
            /// REMARK, this call will invalidate current timer. and replace it to have a better completion handler since we know the contactID
            incomingCall.scheduleCallTimeout()
            return
        }
        /// REMARK  In non callKit mode the contactID is decrypted

        provider(isCallKit: false).reportNewIncomingCall(with: incomingCall.uuid, update: ObvCallUpdateImpl.make(with: incomingCall, engine: obvEngine)) { [weak self] (error) in
            CallHelper.checkQueue() // OK

            guard error == nil else {
                switch error! {
                case .unknown, .unentitled, .callUUIDAlreadyExists, .filteredByDoNotDisturb, .filteredByBlockList:
                    os_log("☎️ reportNewIncomingCall failed -> ending call", log: log, type: .error)
                case .maximumCallGroupsReached:
                    os_log("☎️ reportNewIncomingCall maximumCallGroupsReached -> ending call", log: log, type: .error)
                    self?.sendBusyMessageToContact(for: incomingCall)
                    self?.report(call: incomingCall, report: .missedIncomingCall(caller: incomingCall.callerCallParticipant?.info, participantCount: incomingCallMessage.participantCount))
                }
                incomingCall.setUnanswered()
                incomingCall.endCall()
                return
            }
            ObvMessengerInternalNotification.showCallViewControllerForAnsweringNonCallKitIncomingCall(incomingCall: incomingCall).postOnDispatchQueue()
            let ringingMessageWasSent = self?.sendRingingMessageToContactIfPossible(for: incomingCall)
            if ringingMessageWasSent == true {
                incomingCall.ringingMessageShouldBeSent = false
            }
            incomingCall.scheduleCallTimeout()

        }

    }

    private func processAnswerIncomingCallMessage(_ answerIncomingCallMessage: AnswerIncomingCallJSON, uuidForWebRTC: UUID, contact: ParticipantId, messageUploadTimestampFromServer: Date) {
        CallHelper.checkQueue() // OK
        let log = self.log
        guard let outgoingCall = currentOutgoingCalls.first(where: { $0.uuidForWebRTC == uuidForWebRTC }) else { return }
        let outgoingCallUuid = outgoingCall.uuid
        guard let participant = outgoingCall.getParticipant(contact: contact) else { return }
        outgoingCall.processAnswerIncomingCallJSON(callParticipant: participant, answerIncomingCallMessage) {  [weak self] (error) in
            OperationQueue.main.addOperation {
                guard let call = self?.currentOutgoingCalls.first(where: { $0.uuid == outgoingCallUuid }) else { return }
                guard error == nil else {
                    os_log("Could not set remote description -> ending call", log: log, type: .fault)
                    participant.closeConnection()
                    assertionFailure()
                    return
                }
                self?.provider(isCallKit: call.usesCallKit).reportOutgoingCall(with: outgoingCallUuid, connectedAt: nil)
                self?.report(call: call, report: .acceptedOutgoingCall(from: participant.info))
            }
        }
    }


    private func processRejectCallMessage(_ rejectCallMessage: RejectCallMessageJSON, uuidForWebRTC: UUID, contact: ParticipantId, messageUploadTimestampFromServer: Date) {
        CallHelper.checkQueue() // OK
        guard let call = currentCalls.filter({ $0.uuidForWebRTC == uuidForWebRTC }).first else { return }
        guard let participant = call.getParticipant(contact: contact) else { return }
        guard call is OutgoingCall else { return }
        guard [.startCallMessageSent, .ringing].contains(participant.state) else { return }

        participant.setPeerState(to: .callRejected)
        report(call: call, report: .rejectedOutgoingCall(from: participant.info))
    }

    private func processHangedUpMessage(_ hangedUpMessage: HangedUpMessageJSON, uuidForWebRTC: UUID, contact: ParticipantId, messageUploadTimestampFromServer: Date) {
        CallHelper.checkQueue() // OK
        guard let call = currentCalls.filter({ $0.uuidForWebRTC == uuidForWebRTC }).first else {
            remotelyHangedUpCalls.insert(uuidForWebRTC)
            return
        }
        if let incomingCall = call as? IncomingCall, call.state == .initial {
            call.setUnanswered()
            report(call: call, report: .missedIncomingCall(caller: incomingCall.callerCallParticipant?.info, participantCount: incomingCall.initialParticipantCount))
        }
        guard let participant = call.getParticipant(contact: contact) else { return }

        participant.setPeerState(to: .hangedUp)
        call.updateStateFromPeerStates()
    }

    private func processBusyMessageJSON(uuidForWebRTC: UUID, contact: ParticipantId, messageUploadTimestampFromServer: Date) {
        CallHelper.checkQueue() // OK
        guard let call = currentCalls.filter({ $0.uuidForWebRTC == uuidForWebRTC }).first else { return }
        guard let participant = call.getParticipant(contact: contact) else { return }
        guard participant.state == .startCallMessageSent else { return }

        participant.setPeerState(to: .busy)
        report(call: call, report: .busyOutgoingCall(from: participant.info))
    }

    private func processRingingMessageJSON(uuidForWebRTC: UUID, contact: ParticipantId, messageUploadTimestampFromServer: Date) {
        CallHelper.checkQueue() // OK
        guard let outgoingCall = currentOutgoingCalls.first(where: { $0.uuidForWebRTC == uuidForWebRTC }) else { return }
        guard let participant = outgoingCall.getParticipant(contact: contact) else { return }
        guard participant.state == .startCallMessageSent else { return }

        participant.setPeerState(to: .ringing)
    }

    private func processReconnectCallMessageJSON(_ reconnectCallMessage: ReconnectCallMessageJSON, uuidForWebRTC: UUID, contact: ParticipantId, messageUploadTimestampFromServer: Date) {
        CallHelper.checkQueue() // OK
        guard let call = currentCalls.first(where: { $0.uuidForWebRTC == uuidForWebRTC }) else { return }
        guard let participant = call.getParticipant(contact: contact) else { return }
        call.handleReconnectCallMessage(callParticipant: participant, reconnectCallMessage)
    }

    private func processNewParticipantAnswerMessageJSON(_ newParticipantAnswer: NewParticipantAnswerMessageJSON, uuidForWebRTC: UUID, contact: ParticipantId, messageUploadTimestampFromServer: Date) {
        CallHelper.checkQueue() // OK
        guard let call = currentCalls.first(where: { $0.uuidForWebRTC == uuidForWebRTC }) else { return }
        guard let participant = call.getParticipant(contact: contact) else { return }
        guard participant.role == .recipient else { return }
        guard let contactIdentity = participant.contactIdentity else { assertionFailure(); return }
        guard call.shouldISendTheOfferToCallParticipant(contactIdentity: contactIdentity) else { return }
        participant.setRemoteDescription(sessionDescriptionType: newParticipantAnswer.sessionDescriptionType, sessionDescription: newParticipantAnswer.sessionDescription) { error in
            guard error == nil else { assertionFailure(); return }
        }
    }

    func processNewParticipantOfferMessageJSON(_ newParticipantOffer: NewParticipantOfferMessageJSON, uuidForWebRTC: UUID, contact: ParticipantId, messageUploadTimestampFromServer: Date) {
        CallHelper.checkQueue() // OK
                                /// We check that the `NewParticipantOfferMessageJSON` is not too old. If this is the case, we ignore it
        let timeInterval = Date().timeIntervalSince(messageUploadTimestampFromServer) // In seconds
        guard timeInterval < 30 else {
            os_log("☎️ We received an old NewParticipantOfferMessageJSON, uploaded %{timeInterval}f seconds ago on the server. We ignore it.", log: log, type: .info, timeInterval)
            return
        }

        guard let incomingCall = currentCalls.first(where: { $0.uuidForWebRTC == uuidForWebRTC }) as? IncomingCall else { return }
        guard let participant = incomingCall.getParticipant(contact: contact) else {
            // Put the message in queue as we might simply receive the update call participant message later
            incomingCall.receivedOfferMessages[contact] = (messageUploadTimestampFromServer, newParticipantOffer)
            return
        }
        guard participant.role == .recipient else { return }
        guard let contactIdentity = participant.contactIdentity else { assertionFailure(); return }
        guard !incomingCall.shouldISendTheOfferToCallParticipant(contactIdentity: contactIdentity) else { return }

        guard let turnCredentials = incomingCall.callerCallParticipant?.turnCredentials else { assertionFailure(); return }

        participant.updateRecipient(newParticipantOfferMessage: newParticipantOffer, turnCredentials: turnCredentials)
        participant.createAnswer()
    }

    private func processKickMessageJSON(_ kickMessage: KickMessageJSON, uuidForWebRTC: UUID, contact: ParticipantId, messageUploadTimestampFromServer: Date) {
        CallHelper.checkQueue() // OK
        guard let call = currentCalls.first(where: { $0.uuidForWebRTC == uuidForWebRTC }) else { return }
        guard let participant = call.getParticipant(contact: contact) else { return }
        guard participant.role == .caller else { return }
        os_log("☎️ We received an KickMessageJSON from caller", log: log, type: .info)

        call.setKicked()
        call.endCall()
    }

    private func processAppStateChangedNotification(currentState: AppState) {
        CallHelper.checkQueue() // OK
        guard currentState.isInitializedAndActive else { return }
        guard let (contactIDs, groupId) = callToPerformAfterAppStateBecomesActive else { return }
        callToPerformAfterAppStateBecomesActive = nil
        os_log("☎️ The app is now active and there is a saved call to perform", log: log, type: .info)
        processUserWantsToCallNotification(contactIDs: contactIDs, groupId: groupId)
    }

    private func processUserWantsToCallNotification(contactIDs: [TypeSafeManagedObjectID<PersistedObvContactIdentity>], groupId: (groupUid: UID, groupOwner: ObvCryptoId)?) {
        CallHelper.checkQueue() // OK

        guard AppStateManager.shared.currentState.isInitializedAndActive else {
            os_log("☎️ App is not yet active, save current call for the next app activation", log: log, type: .info)
            callToPerformAfterAppStateBecomesActive = (contactIDs, groupId)
            return
        }

        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] (granted) in
            guard granted else {
                ObvMessengerInternalNotification.outgoingCallFailedBecauseUserDeniedRecordPermission
                    .postOnDispatchQueue()
                return
            }
            OperationQueue.main.addOperation {
                self?.initiateCall(with: contactIDs, groupId: groupId)
            }
        }
    }

    private func processUserWantsToKickParticipant(call: Call, callParticipant: CallParticipant) {
        CallHelper.checkQueue() // OK
        guard let uuidForWebRTC = call.uuidForWebRTC else { return }
        guard let outgoingCall = currentOutgoingCalls.first(where: { $0.uuidForWebRTC == uuidForWebRTC }) else { return }
        guard let contactIdentity = callParticipant.contactIdentity else { return }
        guard let participant = outgoingCall.getParticipant(contact: .cryptoId(contactIdentity)) else { return }
        guard participant.role != .caller else { return }

        participant.setPeerState(to: .kicked)

        // Close the Connection
        participant.closeConnection()

        // Send kick to the kicked participant
        let kickMessage = KickMessageJSON()
        if let webrtcMessage = try? kickMessage.embedInWebRTCMessageJSON(callIdentifier: uuidForWebRTC) {
            outgoingCall.sendWebRTCMessage(to: participant, message: webrtcMessage, forStartingCall: false, completion: {})
        }

        // Update the participant list for the other
        let otherParticipants = call.callParticipants.filter({$0.uuid != callParticipant.uuid})
        let message: WebRTCDataChannelMessageJSON
        do {
            message = try UpdateParticipantsMessageJSON(callParticipants: otherParticipants).embedInWebRTCDataChannelMessageJSON()
        } catch {
            os_log("☎️ Could not send UpdateParticipantsMessageJSON: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }

        for otherParticipant in otherParticipants {
            try? otherParticipant.sendDataChannelMessage(message)
        }
    }

    private func processUserWantsToAddParticipants(call: Call, contactIDs: [TypeSafeManagedObjectID<PersistedObvContactIdentity>]) {
        CallHelper.checkQueue() // OK
        guard let uuidForWebRTC = call.uuidForWebRTC else { return }
        guard currentOutgoingCalls.first(where: { $0.uuidForWebRTC == uuidForWebRTC }) != nil else { return }
        guard let outgoingCall = call as? OutgoingCall else { return }

        outgoingCall.processUserWantsToAddParticipants(contactIDs: contactIDs)
    }
}

// MARK: - OutgoingWebRTCCallDelegate

extension CallCoordinator: IncomingWebRTCCallDelegate, OutgoingWebRTCCallDelegate {

    func answerCallCompleted(callUUID: UUID, result: Result<Void, Error>) {
        let log = self.log
        os_log("☎️ Within answerCallCompleted", log: log, type: .info)
        OperationQueue.main.addOperation { [weak self] in
            guard let _self = self else { return }
            let action = _self.currentAnswerCallActions.removeValue(forKey: callUUID)
            os_log("☎️ We retrieved the following ObvAnswerCallAction from the array of current ObvAnswerCallAction: %{public}@", log: log, type: .info, action?.debugDescription ?? "None")
            switch result {
            case .success:
                os_log("☎️ The newWebRTCMessageToSend was received by the server. Calling fulfill on the action %{public}@", log: log, type: .info, action?.debugDescription ?? "(nil)")
                action?.fulfill()
            case .failure:
                action?.fail()
            }
        }
    }


    func turnCredentialsRequiredByOutgoingCall(outgoingCallUuidForWebRTC: UUID, forOwnedIdentity ownedIdentityCryptoId: ObvCryptoId) {
        CallHelper.checkQueue() // OK
        obvEngine.getTurnCredentials(ownedIdenty: ownedIdentityCryptoId, callUuid: outgoingCallUuidForWebRTC)
    }

}

// MARK: - Helpers

extension CallCoordinator {


    /// This method sends a `RingingMessageJSON` to the caller, but only if both of these are true:
    /// - the incoming call message has already been decrypted, which we check by looking for the caller contactID and the uuid for webrtc
    /// - the pushkit notification has been received (when pushkit is enabled), which we check by looking for the pushkit compltion handler
    /// - Returns: Whether sending the message has succeeded.
    private func sendRingingMessageToContactIfPossible(for call: IncomingCall) -> Bool {
        CallHelper.checkQueue() // OK

        os_log("☎️ Within sendRingingMessageToContactIfPossible", log: log, type: .info)

        let log = self.log

        /// We check that we do know the callee, which can only happen if the incoming call JSON message was decrypted
        guard let caller = call.callerCallParticipant, case .known = caller.contactIdentificationStatus, let uuidForWebRTC = call.uuidForWebRTC else {
            os_log("☎️ Cannot notify contact that the phone is ringing, since the contact is not determined yet", log: log, type: .info)
            return false
        }

        /// In case we use CallKit, we check that we indeed received the pushkit notification, i.e., that the completion handler is set
        let completion: () -> Void
        if call.usesCallKit {
            guard let _completion = pushKitCompletionForIncomingCall.removeValue(forKey: call.uuid) else {
                os_log("☎️ Cannot notify contact that the phone is ringing, since the call kit completion handler is not available yet", log: log, type: .info)
                return false
            }
            completion = {
                _completion()
            }
        } else {
            completion = {
                os_log("☎️ CallKit is not active, no completion handler to call", log: log, type: .info)
            }
        }

        /// If we reach this point, it means that we decrypted the incoming call message *and* that we received the pushkit notification (or that pushkit is not active)
        /// We notify the caller that "we" are ringing. Note that the UI might not be shown yet, but it will soon
        do {
            let ringingMessage = RingingMessageJSON()
            let webrtcMessage = try ringingMessage.embedInWebRTCMessageJSON(callIdentifier: uuidForWebRTC)
            call.sendWebRTCMessage(to: caller, message: webrtcMessage, forStartingCall: false, completion: completion)
            os_log("☎️ newWebRTCMessageToSend was posted with a ringingMessage", log: log, type: .info)
            return true
        } catch {
            os_log("☎️ Could not notify the caller that the phone is ringing", log: log, type: .fault)
            assertionFailure()
            return false
        }
    }


    private func sendBusyMessageToContact(for call: IncomingCall) {
        CallHelper.checkQueue() // OK
        guard let caller = call.callerCallParticipant, let uuidForWebRTC = call.uuidForWebRTC else {
            os_log("☎️ Cannot notify contact that the phone is busy, since the contact is not determined yet", log: log, type: .error)
            return
        }
        do {
            let busyMessage = BusyMessageJSON()
            let webrtcMessage = try busyMessage.embedInWebRTCMessageJSON(callIdentifier: uuidForWebRTC)
            call.sendWebRTCMessage(to: caller, message: webrtcMessage, forStartingCall: false, completion: {})
        } catch {
            os_log("☎️ Could not notify the caller that the phone is busy", log: log, type: .fault)
            assertionFailure()
        }
    }

    private func sendRejectMessageToContact(for call: IncomingCall) {
        CallHelper.checkQueue() // OK
        guard let caller = call.callerCallParticipant, let uuidForWebRTC = call.uuidForWebRTC else {
            os_log("☎️ Cannot notify contact that the phone is busy, since the contact is not determined yet", log: log, type: .error)
            return
        }
        do {
            let rejectedMessage = RejectCallMessageJSON()
            let webrtcMessage = try rejectedMessage.embedInWebRTCMessageJSON(callIdentifier: uuidForWebRTC)
            call.sendWebRTCMessage(to: caller, message: webrtcMessage, forStartingCall: false, completion: {})
        } catch {
            os_log("☎️ Could not notify the caller that the call is rejected", log: log, type: .fault)
            assertionFailure()
        }
    }

    private func sendHangedUpMessageToContact(for call: Call) {
        CallHelper.checkQueue() // OK
        guard let uuidForWebRTC = call.uuidForWebRTC else { return }
        let hangedUpMessage = HangedUpMessageJSON()
        let webrtcMessage: WebRTCMessageJSON!
        do {
            webrtcMessage = try hangedUpMessage.embedInWebRTCMessageJSON(callIdentifier: uuidForWebRTC)
        } catch {
            os_log("☎️ Could not notify the caller that the call is HangedUp", log: log, type: .fault)
            os_log("☎️ Could not build HangedUpMessageJSON message", log: log, type: .fault)
            assertionFailure(); return
        }
        for callParticipant in call.callParticipants {
            call.sendWebRTCMessage(to: callParticipant, message: webrtcMessage, forStartingCall: false, completion: {})
        }
    }


    // MARK: Actions

    private func initiateCall(with contactIDs: [TypeSafeManagedObjectID<PersistedObvContactIdentity>],
                              groupId: (groupUid: UID, groupOwner: ObvCryptoId)?) {
        CallHelper.checkQueue() // OK

        assert(!contactIDs.isEmpty)

        os_log("☎️ initiateCall with %{public}@", log: log, type: .info, contactIDs.map { $0.debugDescription }.joined(separator: ", "))

        try? ObvAudioSessionUtils.shared.configureAudioSessionForMakingOrAnsweringCall()

        var contacts: [ContactInfo] = []
        for contactID in contactIDs {
            guard let contactInfo = CallHelper.getContactInfo(contactID) else {
                os_log("Could not find contact", log: log, type: .fault)
                assertionFailure()
                return
            }
            contacts += [contactInfo]
        }
        contacts.sort { $0.sortDisplayName < $1.sortDisplayName }

        let outgoingCall = createOutgoingCall(contactIDs: contacts.map { $0.objectID }, groupId: groupId)
        let firstContact = contacts.first!
        let contactsDisplayName = firstContact.customDisplayName ?? firstContact.fullDisplayName

        let outgoingCallUuid = outgoingCall.uuid
        let handleValue: String = String(outgoingCallUuid)

        outgoingCall.startCall(contactIdentifier: contactsDisplayName, handleValue: handleValue) { (error) in
            OperationQueue.main.addOperation { [weak self] in
                guard let _self = self else { return }
                guard _self.currentOutgoingCalls.first(where: { $0.uuid == outgoingCallUuid }) != nil else { return }
                if let error = error {
                    os_log("☎️ Start call failed: %{public}@", log: _self.log, type: .error, error.localizedDescription)
                    outgoingCall.setUnanswered()
                    outgoingCall.endCall()
                }
            }
        }
    }

    func report(call: Call, report: CallReport) {
        guard let ownedIdentity = call.ownedIdentity else { return }
        os_log("☎️📖 Report call to user as %{public}@", log: log, type: .info, report.description)
        ObvMessengerInternalNotification.reportCallEvent(callUUID: call.uuid, callReport: report, groupId: call.groupId, ownedCryptoId: ownedIdentity).postOnDispatchQueue()
    }

    func newParticipantWasAdded(call: Call, callParticipant: CallParticipant) {
        CallHelper.checkQueue() // OK
        if call is IncomingCall {
            report(call: call, report: .newParticipantInIncomingCall(callParticipant.info))
        } else {
            report(call: call, report: .newParticipantInOutgoingCall(callParticipant.info))
        }
        let callUpdate = ObvCallUpdateImpl.make(with: call, engine: self.obvEngine)
        self.provider(isCallKit: call.usesCallKit).reportCall(with: call.uuid, updated: callUpdate)
    }

}


// MARK: - ObvProviderDelegate

extension CallCoordinator: ObvProviderDelegate {

    func providerDidBegin() {
        os_log("☎️ Provider did begin", log: log, type: .info)
    }


    func providerDidReset() {
        os_log("☎️ Provider did reset", log: log, type: .info)
    }

    func provider(perform action: ObvStartCallAction) {
        CallHelper.checkQueue() // OK

        os_log("☎️ Provider perform action: %{public}@", log: log, type: .info, action.debugDescription)

        guard let outgoingCall = currentCalls.first(where: { $0.uuid == action.callUUID }) as? OutgoingWebRTCCall else {
            os_log("☎️ Could not start call, call not found", log: log, type: .fault)
            action.fail()
            assertionFailure()
            return
        }

        do {
            try outgoingCall.startCall()
        } catch(let error) {
            os_log("☎️ startCall failed: %{public}@", log: self.log, type: .fault, error.localizedDescription)
            outgoingCall.endCall()
            action.fail()
            assertionFailure()
            return
        }

        self.provider(isCallKit: outgoingCall.usesCallKit).reportOutgoingCall(with: outgoingCall.uuid, startedConnectingAt: nil)
        action.fulfill()

        // If we stop here, the name displayed within iOS call log is incorrect (it shows the CoreData instance's URI). Updating the call right now does the trick.
        let callUpdate = ObvCallUpdateImpl.make(with: outgoingCall, engine: self.obvEngine)
        self.provider(isCallKit: outgoingCall.usesCallKit).reportCall(with: outgoingCall.uuid, updated: callUpdate)
    }

    func provider(perform action: ObvAnswerCallAction) {
        CallHelper.checkQueue() // OK

        os_log("☎️ Provider perform answer call action", log: log, type: .info)

        guard let call = currentCalls.first(where: { $0.uuid == action.callUUID }) as? IncomingWebrtcCall else {
            os_log("☎️ Could not answer call: could not find the call within the current calls", log: log, type: .fault)
            action.fail()
            return
        }

        guard AVAudioSession.sharedInstance().recordPermission == .granted else {
            os_log("☎️ We reject the call since there is no record permission", log: log, type: .fault)
            call.rejectedBecauseOfMissingRecordPermission = true
            call.endCall()
            return
        }

        guard !call.userAnsweredIncomingCall else { return }

        /* Although https://www.youtube.com/watch?v=_64EiziqbuE @ 20:35 says that we should not configure
         * the audio here, we do so anyway. Otherwise, CallKit does not call the
         * func provider(didActivate audioSession: AVAudioSession)
         * delegate method in the case the call is received when the screen is locked.
         */
        do {
            try ObvAudioSessionUtils.shared.configureAudioSessionForMakingOrAnsweringCall()
        } catch {
            os_log("☎️🎵 Could not configure the audio session: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
        }

        // Trigger the call to be answered via the underlying network service.
        os_log("☎️ Adding the following ObvAnswerCallAction in the list of currentAnswerCallActions: %{public}@", log: log, type: .info, action.debugDescription)
        currentAnswerCallActions[call.uuid] = action
        call.answerWebRTCCall()

        call.invalidateCallTimeout()

        report(call: call, report: .acceptedIncomingCall(caller: call.callerCallParticipant?.info))
    }


    func provider(perform action: ObvEndCallAction) {
        CallHelper.checkQueue() // OK

        os_log("☎️ Provider perform end call action for call with UUID %{public}@", log: log, type: .info, action.callUUID as CVarArg)

        guard let call = currentCalls.first(where: { $0.uuid == action.callUUID }) as? WebRTCCall else { action.fail(); return }

        /// Clean all timeouts
        call.invalidateCallTimeout()
        for callParticipant in call.callParticipants {
            callParticipant.invalidateTimeout()
        }

        let state = call.state

        switch state {
        case .callRejected, .hangedUp:
            action.fulfill()
        case .kicked:
            call.endWebRTCCallByHangingUp { action.fulfill() }
            self.provider(isCallKit: call.usesCallKit).reportCall(with: action.callUUID, endedAt: nil, reason: .remoteEnded)
        case .permissionDeniedByServer, .callInitiationNotSupported:
            sendHangedUpMessageToContact(for: call)
            call.endWebRTCCallByHangingUp { action.fulfill() }
            self.provider(isCallKit: call.usesCallKit).reportCall(with: action.callUUID, endedAt: nil, reason: .failed)
        case .ringing, .gettingTurnCredentials, .initializingCall, .userAnsweredIncomingCall:
            sendHangedUpMessageToContact(for: call)
            call.endWebRTCCallByHangingUp { action.fulfill() }
            self.provider(isCallKit: call.usesCallKit).reportCall(with: action.callUUID, endedAt: nil, reason: .remoteEnded)
            self.report(call: call, report: .uncompletedOutgoingCall(with: call.callParticipants.map { $0.info }))
        case .callInProgress:
            sendHangedUpMessageToContact(for: call)
            call.endWebRTCCallByHangingUp { action.fulfill() }
            self.provider(isCallKit: call.usesCallKit).reportCall(with: action.callUUID, endedAt: nil, reason: .remoteEnded)
        case .initial:
            if let incomingCall = call as? IncomingWebrtcCall {
                sendRejectMessageToContact(for: incomingCall)
                call.endWebRTCCallByRejectingCall { action.fulfill() }
                self.provider(isCallKit: call.usesCallKit).reportCall(with: action.callUUID, endedAt: nil, reason: .unanswered)
                if incomingCall.rejectedBecauseOfMissingRecordPermission {
                    self.report(call: call, report: .rejectedIncomingCallBecauseOfDeniedRecordPermission(caller: incomingCall.callerCallParticipant?.info, participantCount: incomingCall.initialParticipantCount))
                } else {
                    self.report(call: call, report: .rejectedIncomingCall(caller: incomingCall.callerCallParticipant?.info, participantCount: incomingCall.initialParticipantCount))
                }
            } else if call is OutgoingCall {
                sendHangedUpMessageToContact(for: call)
                call.endWebRTCCallByHangingUp { action.fulfill() }
                self.provider(isCallKit: call.usesCallKit).reportCall(with: action.callUUID, endedAt: nil, reason: .remoteEnded)
                self.report(call: call, report: .uncompletedOutgoingCall(with: call.callParticipants.map { $0.info }))
            }
        case .unanswered:
            sendHangedUpMessageToContact(for: call)
            call.endWebRTCCallByHangingUp { action.fulfill() }
            self.provider(isCallKit: call.usesCallKit).reportCall(with: action.callUUID, endedAt: nil, reason: .unanswered)
        }
    }

    func provider(perform action: ObvSetHeldCallAction) {
        CallHelper.checkQueue() // OK

        os_log("☎️ Provider perform set held call action", log: log, type: .info)
        action.fulfill()
        assertionFailure("Not implemented")
    }

    func provider(perform action: ObvSetMutedCallAction) {
        CallHelper.checkQueue() // OK

        os_log("☎️ Provider perform set muted call action", log: log, type: .info)
        guard let call = currentCalls.first(where: { $0.uuid == action.callUUID }) as? WebRTCCall else { action.fail(); return }

        if action.isMuted {
            call.mute()
        } else {
            call.unmute()
        }

        action.fulfill()
    }

    func provider(perform action: ObvPlayDTMFCallAction) {
        CallHelper.checkQueue() // OK
        os_log("☎️ Provider perform play DTMF action", log: log, type: .info)
        action.fulfill()
    }


    func provider(timedOutPerforming action: ObvAction) {
        CallHelper.checkQueue() // OK
        os_log("☎️ Provider timed out performing action %{public}@", log: log, type: .info, action.debugDescription)
    }


    func provider(didActivate audioSession: AVAudioSession) {
        CallHelper.checkQueue() // OK
                                // See https://stackoverflow.com/a/55781328
        os_log("☎️🎵 Provider did activate audioSession %{public}@", log: log, type: .info, audioSession.description)
        RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
        RTCAudioSession.sharedInstance().isAudioEnabled = true
    }


    func provider(didDeactivate audioSession: AVAudioSession) {
        CallHelper.checkQueue() // OK
        os_log("☎️🎵 Provider did deactivate audioSession %{public}@", log: log, type: .info, audioSession.description)
        RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
        RTCAudioSession.sharedInstance().isAudioEnabled = false
    }

}


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
                  maskingUID: maskingUID,
                  messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                  localDownloadTimestamp: Date())

    }

}


fileprivate extension ObvCallUpdateImpl {

    static func make(with call: Call, engine: ObvEngine) -> ObvCallUpdate {
        CallHelper.checkQueue() // OK
        var update = ObvCallUpdateImpl()
        let sortedContacts: [(isCaller: Bool, displayName: String)] = call.callParticipants.compactMap {
            guard let displayName = $0.displayName else { return nil }
            return ($0.role == .caller, displayName)
        }.sorted {
            if $0.isCaller { return true }
            if $1.isCaller { return false }
            return $0.displayName < $1.displayName
        }

        update.remoteHandle_ = ObvHandleImpl(type_: .generic, value: String(call.uuid))
        if let incomingCall = call as? IncomingCall, sortedContacts.count == 1 {
            let participantsCount = incomingCall.initialParticipantCount
            update.localizedCallerName = sortedContacts.first?.displayName
            if let participantCount = participantsCount, participantCount > 1 {
                update.localizedCallerName! += " + \(participantCount - 1)"
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

}

struct ContactInfoImpl: ContactInfo {
    var objectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>
    var ownedIdentity: ObvCryptoId?
    var cryptoId: ObvCryptoId?
    var fullDisplayName: String
    var customDisplayName: String?
    var sortDisplayName: String
    var photoURL: URL?
    var identityColors: (background: UIColor, text: UIColor)?

    init(contact persistedContactIdentity: PersistedObvContactIdentity) {
        self.objectID = persistedContactIdentity.typedObjectID
        self.ownedIdentity = persistedContactIdentity.ownedIdentity?.cryptoId
        self.cryptoId = persistedContactIdentity.cryptoId
        self.fullDisplayName = persistedContactIdentity.fullDisplayName
        self.customDisplayName = persistedContactIdentity.customDisplayName
        self.sortDisplayName = persistedContactIdentity.sortDisplayName
        self.photoURL = persistedContactIdentity.customPhotoURL ?? persistedContactIdentity.photoURL
        self.identityColors = persistedContactIdentity.cryptoId.colors
    }
}

struct CallHelper {
    private init() {}
    static func checkQueue() {
        AssertCurrentQueue.onQueue(.main)
    }

    static func getContactInfo(_ contactID: TypeSafeManagedObjectID<PersistedObvContactIdentity>) -> ContactInfo? {
        var contact: ContactInfo?
        ObvStack.shared.viewContext.performAndWait {
            if let persistedContact = try? PersistedObvContactIdentity.get(objectID: contactID, within: ObvStack.shared.viewContext) {
                contact = ContactInfoImpl(contact: persistedContact)
            }
        }
        return contact
    }
}
