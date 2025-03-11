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
import SwiftUI
import Combine
import os.log
import CallKit
import WebRTC
import ObvTypes
import ObvUICoreData
import ObvAppCoreConstants
import ObvCrypto


protocol OlvidCallDelegate: AnyObject {
    func newWebRTCMessageToSendToAllContactDevices(webrtcMessage: ObvUICoreData.WebRTCMessageJSON, contactIdentifier: ObvContactIdentifier, forStartingCall: Bool) async
    func newWebRTCMessageToSendToSingleContactDevice(webrtcMessage: WebRTCMessageJSON, contactDeviceIdentifier: ObvContactDeviceIdentifier) async
    //func newWebRTCMessageToSend(webrtcMessage: WebRTCMessageJSON, contactID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, forStartingCall: Bool) async
    func newParticipantWasAdded(call: OlvidCall, callParticipant: OlvidCallParticipant) async
    func receivedRelayedMessage(call: OlvidCall, messageType: WebRTCMessageJSON.MessageType, serializedMessagePayload: String, uuidForWebRTC: UUID, fromOlvidUser: OlvidUserId) async
    func receivedHangedUpMessage(call: OlvidCall, serializedMessagePayload: String, uuidForWebRTC: UUID, fromOlvidUser: OlvidUserId) async
    func requestTurnCredentialsForCall(call: OlvidCall, ownedIdentityForRequestingTurnCredentials: ObvCryptoId) async throws -> ObvTurnCredentials
    func incomingWasNotAnsweredToAndTimedOut(call: OlvidCall) async
    func outgoingWasNotAnsweredToAndTimedOut(call: OlvidCall) async
    func callDidChangeState(call: OlvidCall, previousState: OlvidCall.State, newState: OlvidCall.State)
    func shouldRequestCXCallUpdate(call: OlvidCall) async
}


final class OlvidCall: ObservableObject {
    
    private static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "OlvidCall")
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "OlvidCall")

    let uuidForCallKit: UUID
    let uuidForWebRTC: UUID
    let groupId: GroupIdentifier?
    let ownedCryptoId: ObvCryptoId
    /// Used for an outgoing call. If the owned identity making the call is allowed to do so, this is set to this owned identity. If she is not, this is set to some other owned identity on this device that is allowed to make calls.
    /// This makes it possible to make secure outgoing calls available to all profiles on this device as soon as one profile is allowed to make secure outgoing calls.
    let ownedIdentityForRequestingTurnCredentials: ObvCryptoId? // Only for outgoing calls
    private var turnCredentials: ObvTurnCredentials? // Only for outgoing calls
    let turnCredentialsReceivedFromCaller: TurnCredentials? // Only for incoming calls
    let direction: Direction
    let initialParticipantCount: Int
    private var pendingIceCandidates = [ObvCryptoId: [IceCandidateJSON]]()
    /// If we are a call participant, we might receive relayed WebRTC messages from the caller (in the case another participant is not "known" to us, i.e., we have not secure channel with her).
    /// We may receive those messages before we are aware of this participant. When this happens, we add those messages to `pendingReceivedRelayedMessages`.
    /// These messages will be used as soon as we are aware of this participant.
    private var pendingReceivedRelayedMessages = [ObvCryptoId: [(messageType: WebRTCMessageJSON.MessageType, messagePayload: String)]]()
    private(set) var receivedOfferMessages: [ObvCryptoId: (OlvidUserId, NewParticipantOfferMessageJSON)] = [:]
    private let rtcPeerConnectionQueue: OperationQueue
    @Published private(set) var otherParticipants: [OlvidCallParticipant]
    @Published private(set) var state = State.initial
    @Published private(set) var dateWhenCallSwitchedToInProgress: Date?
    @Published private(set) var persistedObvOwnedIdentity: PersistedObvOwnedIdentity
    
    @Published private(set) var localPreviewVideoTrack: RTCVideoTrack?
    @Published private(set) var currentCameraPosition: AVCaptureDevice.Position?
    @Published private(set) var selfVideoSize: CGSize?
    @Published private(set) var atLeastOneOtherParticipantHasCameraEnabled = false
    @Published private var hasVideo = false // true iff one of the participants (including self) has a video track
    private var userWantsToStreamSelfVideo = false

    private let factory: ObvPeerConnectionFactory
    
    /* Variables used for audio */

    @Published private(set) var selfIsMuted = false
    @Published private(set) var availableAudioOptions: [OlvidCallAudioOption]? // Nil if the available options cannot be determined yet
    @Published private(set) var currentAudioOptions: [OlvidCallAudioOption] // Empty if the current option cannot be determined yet
    @Published private(set) var isSpeakerEnabled: Bool
    private var isSpeakerEnabledValueChosenByUser: Bool? // Nil unless the user manually decided to activate/deactivate the speaker. This allows to reflect the user choice even if the audio choices are not yet available.
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect() // Allows to keep availableAudioOptions up-to-date
    private var cancellables = Set<AnyCancellable>()
    private var cancellablesForWatchingOtherParticipants = Set<AnyCancellable>()

    /// When receiving an incoming call, we let some time to the user to answer the call. After that, we end it automatically.
    private static let ringingTimeoutInterval: TimeInterval = 50

    /// This task allows to implement the mechanism allowing to wait until ``currentlyCreatingPeerConnection``
    /// is set back to false before proceeding with a negotiation.
    private var sleepingTasksToCancelWhenEndingCallParticipantsModification = [Task<Void, Error>]()

    /// This Boolean is set to `true` when entering a method that could end up modifying the set of call participants.
    /// It is set back to `false` whenever this method is done.
    /// It allows to implement a mechanism preventing two distinct methods to interfere when both can end up modifying the set of call participants.
    private var aTaskIsCurrentlyModifyingCallParticipants = false {
        didSet {
            guard !aTaskIsCurrentlyModifyingCallParticipants else { return }
            oneOfTheTaskCurrentlyModifyingCallParticipantsIsDone()
        }
    }

    private weak var delegate: OlvidCallDelegate?
    

    private init(ownedCryptoId: ObvCryptoId, persistedObvOwnedIdentity: PersistedObvOwnedIdentity, callIdentifierForCallKit: UUID, otherParticipants: [OlvidCallParticipant], ownedIdentityForRequestingTurnCredentials: ObvCryptoId?, direction: Direction, uuidForWebRTC: UUID, initialParticipantCount: Int, groupId: GroupIdentifier?, turnCredentialsReceivedFromCaller: TurnCredentials?, rtcPeerConnectionQueue: OperationQueue, factory: ObvPeerConnectionFactory, delegate: OlvidCallDelegate) {
        self.ownedCryptoId = ownedCryptoId
        self.uuidForCallKit = callIdentifierForCallKit
        self.otherParticipants = otherParticipants
        self.ownedIdentityForRequestingTurnCredentials = ownedIdentityForRequestingTurnCredentials
        self.direction = direction
        self.uuidForWebRTC = uuidForWebRTC
        self.initialParticipantCount = initialParticipantCount
        self.groupId = groupId
        self.turnCredentialsReceivedFromCaller = turnCredentialsReceivedFromCaller
        self.rtcPeerConnectionQueue = rtcPeerConnectionQueue
        self.factory = factory
        self.delegate = delegate
        self.availableAudioOptions = Self.getAvailableOlvidCallAudioOption()
        self.currentAudioOptions = RTCAudioSession.sharedInstance().session.currentRoute.inputs.map({ .init(portDescription: $0) })
        self.isSpeakerEnabled = false // The currentRoute.outputs always contain the builtInSpeaker speaker at this point, although we know it won't be activated. We set this value to false by default.
        self.persistedObvOwnedIdentity = persistedObvOwnedIdentity
        regularlyUpdatePublishedAudioInformations()
        reactToAppLifecycleNotifications()
        continuouslyWatchOtherParticipantsVideoEnabled()
        keepHasVideoValueUpToDate()
        notifyDelegateWhenCXCallUpdateShouldBeRequested()
        postUserNotificationWhenAtLeastOneOtherParticipantHasCameraEnabled()
    }
    
    
    /// Called during the initialization, and each time the set of identities of the other participants changes.
    /// This allows to watch the enabling/disabling of the other participants camera, so as to update the `atLeastOneOtherParticipantHasCameraEnabled` published property.
    /// If this method is called twice, is first cancels the result of the previous call, and re-watches all participants.
    private func continuouslyWatchOtherParticipantsVideoEnabled() {
        
        cancellablesForWatchingOtherParticipants.forEach({ $0.cancel() })
        
        let currentOtherParticipantsIdentities = Set(self.otherParticipants.map({ $0.cryptoId }))
        
        for participant in self.otherParticipants {
            Publishers.CombineLatest(participant.$remoteCameraVideoTrackIsEnabled, participant.$remoteScreenCastVideoTrackIsEnabled)
                .receive(on: OperationQueue.main)
                .sink { [weak self] _, _ in
                    guard let self else { return }
                    let newAtLeastOneOtherParticipantHasCameraEnabled = evaluateIfAtLeastOneOtherParticipantHasCameraEnabled()
                    if self.atLeastOneOtherParticipantHasCameraEnabled != newAtLeastOneOtherParticipantHasCameraEnabled {
                        self.atLeastOneOtherParticipantHasCameraEnabled = newAtLeastOneOtherParticipantHasCameraEnabled
                    }
                }
                .store(in: &cancellablesForWatchingOtherParticipants)
        }
        
        // If the list of other participants is updated, we need to call this method again to make sure we watch the current participants
        $otherParticipants
            .map({ Set($0.map({ $0.cryptoId })) })
            .removeDuplicates()
            .receive(on: OperationQueue.main)
            .sink { [weak self] newOtherParticipantsIdentities in
                guard currentOtherParticipantsIdentities != newOtherParticipantsIdentities else { return }
                self?.continuouslyWatchOtherParticipantsVideoEnabled()
            }
            .store(in: &cancellablesForWatchingOtherParticipants)
        
    }
    
    
    /// Helper method for the ``continuouslyWatchOtherParticipantsVideoEnabled()`` method.
    private func evaluateIfAtLeastOneOtherParticipantHasCameraEnabled() -> Bool {
        return self.otherParticipants.first(where: { $0.remoteCameraVideoTrackIsEnabled || $0.remoteScreenCastVideoTrackIsEnabled }) != nil
    }
    
    
    deinit {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        cancellables.forEach { $0.cancel() }
        cancellablesForWatchingOtherParticipants.forEach { $0.cancel() }
        os_log("☎️ OlvidCall deinit", log: Self.log, type: .debug)
    }
    
    
    static func createIncomingCall(callIdentifierForCallKit: UUID, uuidForWebRTC: UUID, callerDeviceIdentifier: ObvContactDeviceIdentifier, startCallMessage: StartCallMessageJSON, rtcPeerConnectionQueue: OperationQueue, factory: ObvPeerConnectionFactory, delegate: OlvidCallDelegate) async throws -> OlvidCall {
        
        let shouldISendTheOfferToCallParticipant = Self.shouldISendTheOfferToCallParticipant(ownedCryptoId: callerDeviceIdentifier.ownedCryptoId, cryptoId: callerDeviceIdentifier.contactCryptoId)
        
        let caller = try await OlvidCallParticipant.createCallerOfIncomingCall(
            callerDeviceIdentifier: callerDeviceIdentifier,
            startCallMessage: startCallMessage,
            shouldISendTheOfferToCallParticipant: shouldISendTheOfferToCallParticipant,
            rtcPeerConnectionQueue: rtcPeerConnectionQueue,
            factory: factory)
        
        let persistedObvOwnedIdentity = try await fetchPersistedObvOwnedIdentity(ownedCryptoId: callerDeviceIdentifier.ownedCryptoId)
        
        let incomingCall = OlvidCall(
            ownedCryptoId: callerDeviceIdentifier.ownedCryptoId,
            persistedObvOwnedIdentity: persistedObvOwnedIdentity,
            callIdentifierForCallKit: callIdentifierForCallKit,
            otherParticipants: [caller],
            ownedIdentityForRequestingTurnCredentials: nil,
            direction: .incoming,
            uuidForWebRTC: uuidForWebRTC,
            initialParticipantCount: startCallMessage.participantCount,
            groupId: startCallMessage.groupIdentifier,
            turnCredentialsReceivedFromCaller: startCallMessage.turnCredentials, 
            rtcPeerConnectionQueue: rtcPeerConnectionQueue,
            factory: factory,
            delegate: delegate)
        
        await caller.setDelegate(to: incomingCall)
        
        await incomingCall.sendRingingMessageToCallerAndScheduleTimeout()
        
        return incomingCall
        
    }
    

    @MainActor
    static func fetchPersistedObvOwnedIdentity(ownedCryptoId: ObvCryptoId) async throws -> PersistedObvOwnedIdentity {
        guard let persistedObvOwnedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: ObvStack.shared.viewContext) else {
            throw ObvError.couldNotFindOwnedIdentity
        }
        return persistedObvOwnedIdentity
    }
    
    
    @MainActor
    static func createOutgoingCall(ownedCryptoId: ObvCryptoId, contactCryptoIds: Set<ObvCryptoId>, ownedIdentityForRequestingTurnCredentials: ObvCryptoId, groupId: GroupIdentifier?, rtcPeerConnectionQueue: OperationQueue, factory: ObvPeerConnectionFactory, delegate: OlvidCallDelegate) async throws -> OlvidCall {
        
        let callIdentifierForCallKitAndWebRTC = UUID()

        var callees = [OlvidCallParticipant]()
        for contactCryptoId in contactCryptoIds {
            let shouldISendTheOfferToCallParticipant = Self.shouldISendTheOfferToCallParticipant(ownedCryptoId: ownedCryptoId, cryptoId: contactCryptoId)
            let contactId = ObvContactIdentifier(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
            let callee = try await OlvidCallParticipant.createCalleeOfOutgoingCall(
                calleeId: contactId,
                shouldISendTheOfferToCallParticipant: shouldISendTheOfferToCallParticipant,
                rtcPeerConnectionQueue: rtcPeerConnectionQueue,
                factory: factory)
            callees.append(callee)
        }
        
        callees.sort(by: \.displayName)
        
        let persistedObvOwnedIdentity = try await fetchPersistedObvOwnedIdentity(ownedCryptoId: ownedCryptoId)

        let outgoingCall = OlvidCall(
            ownedCryptoId: ownedCryptoId,
            persistedObvOwnedIdentity: persistedObvOwnedIdentity,
            callIdentifierForCallKit: callIdentifierForCallKitAndWebRTC,
            otherParticipants: callees,
            ownedIdentityForRequestingTurnCredentials: ownedIdentityForRequestingTurnCredentials, 
            direction: .outgoing,
            uuidForWebRTC: callIdentifierForCallKitAndWebRTC, 
            initialParticipantCount: contactCryptoIds.count, 
            groupId: groupId, 
            turnCredentialsReceivedFromCaller: nil, 
            rtcPeerConnectionQueue: rtcPeerConnectionQueue,
            factory: factory,
            delegate: delegate)
        
        for otherParticipant in outgoingCall.otherParticipants {
            await otherParticipant.setDelegate(to: outgoingCall)
        }
        
        return outgoingCall
        
    }

    
    private var callerOfIncomingCall: OlvidCallParticipant? {
        return otherParticipants.first(where: { $0.isCallerOfIncomingCall })
    }
    

    /// Given the information available for this call, this method returns the most up-to-date `CXCallUpdate` possible.
    @MainActor
    func createUpToDateCXCallUpdate() async -> CXCallUpdate {
        let update = CXCallUpdate()
        let sortedContacts: [(isCaller: Bool, displayName: String)] = otherParticipants.map {
            let displayName = $0.displayName
            return ($0.isCallerOfIncomingCall, displayName)
        }.sorted {
            if $0.isCaller { return true }
            if $1.isCaller { return false }
            return $0.displayName < $1.displayName
        }
        
        if self.direction == .incoming && sortedContacts.count == 1 {
            update.localizedCallerName = sortedContacts.first?.displayName
            if initialParticipantCount > 1 {
                update.localizedCallerName! += " + \(initialParticipantCount - 1)"
            }
        } else if sortedContacts.count > 0 {
            let contactName = ListFormatter.localizedString(byJoining: sortedContacts.map({ $0.displayName }))
            update.localizedCallerName = contactName
        } else {
            update.localizedCallerName = "..."
        }
        update.remoteHandle = .init(type: .generic, value: uuidForCallKit.uuidString)
        update.hasVideo = self.hasVideo
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsHolding = false
        update.supportsDTMF = false
        return update
    }
    
    
    static func shouldISendTheOfferToCallParticipant(ownedCryptoId: ObvTypes.ObvCryptoId, cryptoId: ObvTypes.ObvCryptoId) -> Bool {
        /// REMARK it should be the same as io.olvid.messenger.webrtc.WebrtcCallService#shouldISendTheOfferToCallParticipant in java
        return ownedCryptoId > cryptoId
    }

}


// MARK: - Video

extension OlvidCall {
    
    @MainActor
    func userWantsToStartVideoCamera(preferredPosition: AVCaptureDevice.Position) async throws {
        userWantsToStreamSelfVideo = true
        try await startVideoCamera(preferredPosition: preferredPosition)
    }
    
    
    @MainActor
    func userWantsToStopVideoCamera() async {
        userWantsToStreamSelfVideo = false
        await stopVideoCamera()
    }
        
    @MainActor
    private func startVideoCamera(preferredPosition: AVCaptureDevice.Position) async throws {
        
        // Make sure the number of other participants is acceptable
        
        guard otherParticipants.count <= ObvMessengerConstants.maxOtherParticipantCountForVideoCalls else {
            throw ObvError.maxOtherParticipantCountForVideoCallsExceeded
        }

        let (newLocalPreviewVideoTrack, newCurrentCameraPosition, newSelfVideoSize) = try await factory.startCaptureLocalVideo(preferredPosition: preferredPosition)
        if self.localPreviewVideoTrack != newLocalPreviewVideoTrack {
            // If we are just starting the video (not changing position), start the speaker if appropriate
            if self.localPreviewVideoTrack == nil {
                Task { [weak self] in await self?.startSpeakerOnCameraStartIfAppropriate() }
            }
            // For some reason, the following code is required if we want the camera position change to work properly at the UI level
            self.localPreviewVideoTrack = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300)) { [weak self] in
                guard let self else { return }
                self.localPreviewVideoTrack = newLocalPreviewVideoTrack
                Task { [weak self] in await self?.reevalutateScreenDimming() } // Prevent the screen for dimming
            }
        }
        if self.currentCameraPosition != newCurrentCameraPosition {
            self.currentCameraPosition = newCurrentCameraPosition
        }
        if self.selfVideoSize != newSelfVideoSize {
            self.selfVideoSize = newSelfVideoSize
        }
        for otherParticipant in self.otherParticipants {
            try? await otherParticipant.setLocalVideoTrack(isEnabled: true)
        }
        
    }
    
    
    func callViewDidDisappear() async {
        await stopVideoCamera()
    }
    
    
    func callViewDidAppear() async {
        os_log("☎️ callViewDidDisappear", log: Self.log, type: .info)
        try? await Task.sleep(milliseconds: 500) // Required to make things work when entering foreground
        guard userWantsToStreamSelfVideo else { return }
        do {
            try await startVideoCamera(preferredPosition: currentCameraPosition ?? .front)
        } catch {
            assertionFailure()
        }
    }
    
    
    @MainActor
    private func stopVideoCamera() async {
        
        withAnimation {
            self.localPreviewVideoTrack = nil
            self.currentCameraPosition = nil
        }
        await reevalutateScreenDimming() // Stop preventing the screen for dimming
        await factory.stopCaptureLocalVideo()
        for otherParticipant in self.otherParticipants {
            try? await otherParticipant.setLocalVideoTrack(isEnabled: false)
        }

    }
    
    
    @MainActor
    private func startSpeakerOnCameraStartIfAppropriate() async {
        guard !isSpeakerEnabled else { return }
        if currentAudioOptions.count == 1, let currentAudioOption = currentAudioOptions.first, currentAudioOption.portType == .builtInMic {
            try? await userWantsToChangeSpeaker(to: true)
        }
    }
    
    
    /// Each time we start/stop streaming our own video, or when another participant starts/stop her video, we check if it is appropriate for the system to dim the screen.
    @MainActor
    func reevalutateScreenDimming() async {
        if self.localPreviewVideoTrack != nil {
            UIApplication.shared.isIdleTimerDisabled = true
        } else if otherParticipants.first(where: { $0.remoteCameraVideoTrackIsEnabled || $0.remoteScreenCastVideoTrackIsEnabled }) != nil {
            UIApplication.shared.isIdleTimerDisabled = true
        } else {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    
    
}


// MARK: - Audio

extension OlvidCall {
    
    /// This method is *not* called from the UI but from the coordinator, as a response to our request made in
    /// ``func userRequestedToToggleAudio() async``
    func setMuteSelfForOtherParticipants(muted: Bool) async throws {
        for participant in self.otherParticipants {
            try await participant.setMuteSelf(muted: muted)
        }
        await setSelfIsMuted(to: muted)
        for participant in self.otherParticipants {
            Task { await participant.sendMutedMessageJSON() }
        }
    }

    /// We set the ``selfIsMuted`` propery on the main actor as it is a published property, used at the UI level.
    @MainActor
    private func setSelfIsMuted(to newSelfIsMuted: Bool) async {
        withAnimation {
            self.selfIsMuted = newSelfIsMuted
        }
    }
    
    
    func userWantsToChangeSpeaker(to isSpeakerEnabled: Bool) async throws {
        isSpeakerEnabledValueChosenByUser = isSpeakerEnabled
        let rtcAudioSession = RTCAudioSession.sharedInstance()
        rtcAudioSession.lockForConfiguration()
        try rtcAudioSession.overrideOutputAudioPort(isSpeakerEnabled ? .speaker : .none)
        rtcAudioSession.unlockForConfiguration()
    }

    
    func userWantsToActivateAudioOption(_ audioOption: OlvidCallAudioOption) async throws {
        let rtcAudioSession = RTCAudioSession.sharedInstance()
        rtcAudioSession.lockForConfiguration()
        do {
            if let portDescription = audioOption.portDescription {
                isSpeakerEnabledValueChosenByUser = false
                try rtcAudioSession.overrideOutputAudioPort(.none)
                try rtcAudioSession.setPreferredInput(portDescription)
            } else {
                isSpeakerEnabledValueChosenByUser = true
                try rtcAudioSession.overrideOutputAudioPort(.speaker)
            }
        } catch {
            rtcAudioSession.unlockForConfiguration()
            throw error
        }
        rtcAudioSession.unlockForConfiguration()
        updatePublishedAudioInformations()
    }
    

    /// Returns `nil` if the options are not yet known (e.g., at the very begining of an outgoing call).
    private static func getAvailableOlvidCallAudioOption() -> [OlvidCallAudioOption]? {
        let rtcAudioSession = RTCAudioSession.sharedInstance()
        guard let availableInputs = rtcAudioSession.session.availableInputs else { return nil }
        var inputs: [OlvidCallAudioOption] = availableInputs.map({ .init(portDescription: $0) })
        inputs.append(OlvidCallAudioOption.builtInSpeaker())
        return inputs
    }
    
    
    /// Called during init, so as to make sure the ``availableAudioOptions`` stay up-to-date.
    private func regularlyUpdatePublishedAudioInformations() {
        timer
            .sink { [weak self] _ in
                self?.updatePublishedAudioInformations()
            }
            .store(in: &cancellables)
    }
    
    
    private func reactToAppLifecycleNotifications() {
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                Task { [weak self] in await self?.stopVideoCamera() }
            }
            .store(in: &cancellables)
    }
    
    
    /// When one of the participants of the call turns her camera on or off, we might need to update the value of ``hasVideo``.
    /// To do so, we observe the modifications made to ``atLeastOneOtherParticipantHasCameraEnabled`` and of ``localPreviewVideoTrack``.
    private func keepHasVideoValueUpToDate() {
        Publishers.CombineLatest($atLeastOneOtherParticipantHasCameraEnabled, $localPreviewVideoTrack)
            .map { (atLeastOneOtherParticipantHasCameraEnabled, localPreviewVideoTrack) in
                let newHasVideo = atLeastOneOtherParticipantHasCameraEnabled || (localPreviewVideoTrack != nil)
                return newHasVideo
            }
            .removeDuplicates()
            .receive(on: OperationQueue.main)
            .sink { [weak self] newHasVideo in
                self?.hasVideo = newHasVideo
            }
            .store(in: &cancellables)
    }
    
    
    /// Whenever a participant activates her camera, we might need to post a user notification allowing the local user to be notified.
    private func postUserNotificationWhenAtLeastOneOtherParticipantHasCameraEnabled() {
        $atLeastOneOtherParticipantHasCameraEnabled
            .receive(on: OperationQueue.main)
            .sink { [weak self] atLeastOneOtherParticipantHasCameraEnabled in
                guard let self else { return }
                guard atLeastOneOtherParticipantHasCameraEnabled else { return }
                let otherParticipantNames = otherParticipants
                    .filter { $0.remoteCameraVideoTrackIsEnabled || $0.remoteScreenCastVideoTrackIsEnabled }
                    .map { $0.displayName }
                VoIPNotification.anotherCallParticipantStartedCamera(otherParticipantNames: otherParticipantNames)
                    .postOnDispatchQueue()
            }
            .store(in: &cancellables)
    }
    
    
    /// When the list of participants changes, or when the audio call turns into a video call, we want to update the CallKit UI.
    /// To do so, we notify our delegate, which will  update the CallKit UI.
    private func notifyDelegateWhenCXCallUpdateShouldBeRequested() {
        Publishers.CombineLatest($otherParticipants, $hasVideo)
            .sink { [weak self] _ in
                Task { [weak self] in
                    guard let self, let delegate else { return }
                    await delegate.shouldRequestCXCallUpdate(call: self)
                }
            }
            .store(in: &cancellables)
    }
    

    private func updatePublishedAudioInformations() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let rtcAudioSession = RTCAudioSession.sharedInstance()
            let newAvailableAudioOptions = Self.getAvailableOlvidCallAudioOption()
            if self.availableAudioOptions != newAvailableAudioOptions {
                self.availableAudioOptions = newAvailableAudioOptions
            }
            let newCurrentAudioOptions = rtcAudioSession.currentRoute.inputs.map({ OlvidCallAudioOption(portDescription: $0) })
            if self.currentAudioOptions != newCurrentAudioOptions {
                self.currentAudioOptions = newCurrentAudioOptions
            }
            let newIsSpeakerEnabled: Bool
            if currentAudioOptions.isEmpty {
                // The available audio options are not yet available (typicall at the very begining of an outgoing call)
                // We set the isSpeakerEnabled to the value manually chosen by the user (if any) or to false otherwise
                newIsSpeakerEnabled = isSpeakerEnabledValueChosenByUser ?? false
            } else {
                // Typical case during a call. We don't use the value chosen by the user as we want the UI to reflect the "true"
                // state of the speaker, now that we are able to determine it.
                newIsSpeakerEnabled = rtcAudioSession.currentRoute.outputs.contains(where: { $0.portType == .builtInSpeaker })
            }
            if self.isSpeakerEnabled != newIsSpeakerEnabled {
                self.isSpeakerEnabled = newIsSpeakerEnabled
            }
        }
    }

}

// MARK: - For incoming calls

extension OlvidCall {
    
    /// This method is called by the ``OlvidCallManager`` immediately after the local user accepted an incoming call from the in-house UI.
    /// This allows to quickly switch the call state (and thus, allows to have a responsive UI).
    /// Note that the call manager will still have to notify the call acceptance to the call controller. Eventually, this will trigger the
    /// ``localUserWantsToAnswerThisIncomingCall()`` method.
    /// Note that if the user accepts an incoming call from the CallKit UI, this method is not called, but the ``localUserWantsToAnswerThisIncomingCall()`` is always called.
    func localUserAcceptedIncomingCallFromInHouseUI() async {
        assert(self.direction == .incoming)
        await setCallState(to: .userAnsweredIncomingCall)
    }
    
    
    /// This is called from the `OlvidCallManager` when the local user accepted an incoming call (either on the CallKit interface or on the Olvid UI).
    /// Returns the caller infos.
    func localUserWantsToAnswerThisIncomingCall() async throws -> OlvidCallParticipantInfo? {
        os_log("☎️ Call to localUserWantsToAnswerThisIncomingCall()", log: Self.log, type: .info)
        await setCallState(to: .userAnsweredIncomingCall)
        guard let callerOfIncomingCall else {
            assertionFailure()
            throw ObvError.callerIsNotSet
        }
        try await callerOfIncomingCall.localUserAcceptedIncomingCallFromThisCallParticipant()
        return callerOfIncomingCall.info
    }
    
    
    func endBecauseOfDeniedRecordPermission() async throws -> (callReport: CallReport?, cxCallEndedReason: CXCallEndedReason?) {
        return await endWebRTCCall(reason: .deniedRecordPermission)
    }
    
    
    /// This called from the ``OlvidCallManager`` when the user ends an incoming call (either on the CallKit interface or on the Olvid UI).
    func endWasRequestedByLocalUser() async -> CallReport? {
        os_log("☎️🔚 Call to endWasRequestedByLocalUser()", log: Self.log, type: .info)
        let values = await endWebRTCCall(reason: .localUserRequest)
        assert(values.cxCallEndedReason == nil, "Since the end of this call was request by the local user, it does not make sense to have a CXCallEndedReason")
        return values.callReport
    }
 
    
    func processNewParticipantOfferMessageJSONFromContact(_ contact: OlvidUserId, _ newParticipantOffer: NewParticipantOfferMessageJSON) async throws {
        let participant: OlvidCallParticipant?
        if let deviceUID = contact.contactDeviceIdentifier?.deviceUID {
            participant = await setDeviceUIDOfParticipant(remoteCryptoId: contact.remoteCryptoId, deviceUID: deviceUID)
        } else {
            Self.logger.fault("☎️ We received a NewParticipantOfferMessageJSON message, which should contain the information about the remote device")
            assertionFailure()
            participant = await getParticipant(remoteCryptoId: contact.remoteCryptoId)
            await participant?.destinationDeviceIsKnownOrWillNotBeKnown()
        }
        guard let participant else {
            // Put the message in queue as we might simply receive the update call participant message later
            await addPendingOffer((contact, newParticipantOffer), from: contact.remoteCryptoId)
            return
        }
        guard !Self.shouldISendTheOfferToCallParticipant(ownedCryptoId: ownedCryptoId, cryptoId: contact.remoteCryptoId) else { assertionFailure(); return }
        guard let turnCredentialsReceivedFromCaller else { assertionFailure(); throw ObvError.noTurnCredentialsFound }
        try await participant.updateRecipient(newParticipantOfferMessage: newParticipantOffer, turnCredentials: turnCredentialsReceivedFromCaller)
    }

    
    func processKickMessageJSONFromContact(_ contact: OlvidUserId) async throws -> (callReport: CallReport?, cxCallEndedReason: CXCallEndedReason?) {
        guard direction == .incoming else { assertionFailure(); return (nil, nil) }
        guard let participant = await getParticipant(remoteCryptoId: contact.remoteCryptoId) else { assertionFailure(); return (nil, nil) }
        guard participant.isCallerOfIncomingCall else { assertionFailure(); return (nil, nil) }
        os_log("☎️ We received an KickMessageJSON from caller", log: Self.log, type: .info)
        return await endWebRTCCall(reason: .kicked)
    }
    
    
    func processAnsweredOrRejectedOnOtherDeviceMessage(answered: Bool) async -> (callReport: CallReport?, cxCallEndedReason: CXCallEndedReason?) {
        guard direction == .incoming else { assertionFailure(); return (nil, nil) }
        switch self.state {
        case .initial, .ringing, .outgoingCallIsConnecting, .hangedUp, .kicked, .callRejected, .unanswered, .answeredOnAnotherDevice:
            return await endWebRTCCall(reason: .answeredOrRejectedOnOtherDevice(answered: answered))
        case .userAnsweredIncomingCall, .gettingTurnCredentials, .initializingCall, .callInProgress, .reconnecting:
            // This can exceptionally occur if the other owned device is not informed that we have answered the call
            // on the current device, and the user physically ends the call on the other device. In such a scenario,
            // we do not wish to terminate the call on the current device.
            return (nil, nil)
        }
    }
    
    
    /// Called when creating an incoming call
    func sendRingingMessageToCallerAndScheduleTimeout() async {
        
        assert(direction == .incoming)
        
        guard let caller = self.callerOfIncomingCall else {
            os_log("☎️ Could not send ringing message as the caller is not set", log: Self.log, type: .fault)
            assertionFailure()
            return
        }
        
        // Send a RingingMessageJSON
        
        let rejectedMessage = RingingMessageJSON()
        do {
            try await sendWebRTCMessage(to: caller, innerMessage: rejectedMessage, forStartingCall: false)
        } catch {
            os_log("☎️ Failed to send a RejectCallMessageJSON to the caller: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure() // Continue anyway
        }
        
        // Schedule a timeout after which this incoming call should be automatically ended
        
        Task { [weak self] in
            try? await Task.sleep(for: Self.ringingTimeoutInterval)
            guard let self else { return }
            guard state == .initial else { return }
            // The following call will eventually call us back, with the endIncomingCallAsItTimedOut() method.
            // We don't call it directly since ending the call is not enough (we have to remove it from the call manager, etc.)
            await delegate?.incomingWasNotAnsweredToAndTimedOut(call: self)
        }
        
    }

    
}


// MARK: - For outgoing calls

extension OlvidCall {
    
    func startOutgoingCall() async throws {
        
        guard let delegate else {
            assertionFailure()
            throw ObvError.delegateIsNil
        }
        
        guard let ownedIdentityForRequestingTurnCredentials else {
            assertionFailure()
            throw ObvError.ownedIdentityForRequestingTurnCredentialsIsNil
        }
        
        // Will will request turn credentials, we want the outgoing call to reflect that
        await setCallState(to: .gettingTurnCredentials)

        assert(self.turnCredentials == nil)
        let turnCredentials = try await delegate.requestTurnCredentialsForCall(call: self, ownedIdentityForRequestingTurnCredentials: ownedIdentityForRequestingTurnCredentials)
        
        self.turnCredentials = turnCredentials
        for otherParticipant in self.otherParticipants {
            try await otherParticipant.setTurnCredentialsAndCreateUnderlyingPeerConnection(turnCredentials: turnCredentials.turnCredentialsForRecipient)
            try? await Task.sleep(milliseconds: 300) // 300 ms, dirty trick, required to prevent a deadlock of the WebRTC library
        }
        await setCallState(to: .initializingCall)
        
    }


    func processAnswerCallJSONFromContact(_ contact: OlvidUserId, _ answerCallMessage: AnswerCallJSON) async throws -> OlvidCallParticipantInfo? {
        guard self.direction == .outgoing else { assertionFailure(); throw ObvError.notOutgoingCall }
        await setCallState(to: .outgoingCallIsConnecting)
        let participant: OlvidCallParticipant?
        if let deviceUID = contact.contactDeviceIdentifier?.deviceUID {
            participant = await setDeviceUIDOfParticipant(remoteCryptoId: contact.remoteCryptoId, deviceUID: deviceUID)
        } else {
            assertionFailure("We received anAnswerCall message, which should contain the information about the remote device")
            participant = await getParticipant(remoteCryptoId: contact.remoteCryptoId)
        }
        guard let participant else { assertionFailure(); throw ObvError.couldNotFindParticipant }
        let sessionDescription = RTCSessionDescription(type: answerCallMessage.sessionDescriptionType, sdp: answerCallMessage.sessionDescription)
        do {
            try await participant.setRemoteDescription(sessionDescription: sessionDescription)
        } catch {
            try await participant.closeConnection()
            throw error
        }
        return participant.info
    }

    
    /// Returns `nil` if the call did not reach a final state.
    func processRejectCallMessageFromContact(_ contact: OlvidUserId) async -> OlvidCallParticipantInfo? {
        guard self.direction == .outgoing else { assertionFailure(); return nil }
        guard let participant = await getParticipant(remoteCryptoId: contact.remoteCryptoId) else { return nil }
        await participant.rejectedOutgoingCall()
        guard participant.state.isFinalState else { return nil }
        await updateStateFromPeerStates()
        return participant.info
    }

    
    func processRingingMessageJSONFromContact(_ contact: OlvidUserId) async {
        guard self.direction == .outgoing else { assertionFailure(); return }
        guard let participant = await getParticipant(remoteCryptoId: contact.remoteCryptoId) else { return }
        await participant.isRinging()
    }
    
    
    /// Dispatching on the main actor as we modify a published variable used at the UI level.
    @MainActor
    func userWantsToAddParticipantsToThisOutgoingCall(participantsToAdd: Set<ObvCryptoId>) async throws {
        
        guard self.direction == .outgoing else {
            assertionFailure()
            throw ObvError.notOutgoingCall
        }
        
        guard let turnCredentials else {
            assertionFailure()
            throw ObvError.noTurnCredentialsFound
        }
                
        var callees = [OlvidCallParticipant]()
        for contactCryptoId in participantsToAdd {
            guard otherParticipants.first(where: { $0.cryptoId == contactCryptoId }) == nil else { assertionFailure(); continue }
            let shouldISendTheOfferToCallParticipant = Self.shouldISendTheOfferToCallParticipant(ownedCryptoId: ownedCryptoId, cryptoId: contactCryptoId)
            let contactId = ObvContactIdentifier(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
            let callee = try await OlvidCallParticipant.createCalleeOfOutgoingCall(
                calleeId: contactId,
                shouldISendTheOfferToCallParticipant: shouldISendTheOfferToCallParticipant,
                rtcPeerConnectionQueue: rtcPeerConnectionQueue,
                factory: factory)
            callees.append(callee)
        }

        callees.sort(by: \.displayName)
        
        var newOtherParticipants = callees + self.otherParticipants
        newOtherParticipants.sort(by: \.displayName)
        
        // Before setting the new list of participants, we stop our own video stream if the number of participants is too large
        
        if newOtherParticipants.count > ObvMessengerConstants.maxOtherParticipantCountForVideoCalls {
            await userWantsToStopVideoCamera()
        }
        
        // We can now set the new list of participants
        
        withAnimation {
            self.otherParticipants = newOtherParticipants
        }
        
        // If we were muted, we must make sure we stay muted for all participant, including the new ones
        
        try await setMuteSelfForOtherParticipants(muted: selfIsMuted)

        for newParticipant in callees {
            try? await Task.sleep(milliseconds: 300) // 300 ms, dirty trick, required to prevent a deadlock of the WebRTC library
            await newParticipant.setDelegate(to: self)
            do {
                try await newParticipant.setTurnCredentialsAndCreateUnderlyingPeerConnection(turnCredentials: turnCredentials.turnCredentialsForRecipient)
            } catch {
                assertionFailure(error.localizedDescription)
                continue
            }
            await delegate?.newParticipantWasAdded(call: self, callParticipant: newParticipant)
        }
        
    }
    
    
    func userWantsToRemoveParticipantFromThisOutgoingCall(cryptoId: ObvCryptoId) async throws {
        
        guard self.direction == .outgoing else {
            assertionFailure()
            throw ObvError.notOutgoingCall
        }

        guard let participantToKick = otherParticipants.first(where: { $0.cryptoId == cryptoId }) else { assertionFailure(); return }
        
        await participantToKick.callerKicksThisParticipant()

        // Send kick to the kicked participant
        
        let kickMessage = KickMessageJSON()
        do {
            try await sendWebRTCMessage(to: participantToKick, innerMessage: kickMessage, forStartingCall: false)
        } catch {
            os_log("☎️ Could not send KickMessageJSON to kicked contact: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
            // Continue anyway
        }

    }
    
    
    func userWantsToChatWithParticipant(participant: ObvCryptoId) async throws {
        
        guard let participant = otherParticipants.first(where: { $0.cryptoId == participant }) else { return }
        
        try await participant.userWantsToChatWithThisParticipant(ownedCryptoId: self.ownedCryptoId)
        
    }
    
}


// MARK: - Processing messages received by the CallProviderDelegate

extension OlvidCall {

    func callParticipantDidHangUp(participantId: OlvidUserId) async throws -> OlvidCallParticipantInfo? {
        guard let participant = await getParticipant(remoteCryptoId: participantId.remoteCryptoId) else { return nil }
        await participant.didHangUp()
        assert(participant.state.isFinalState)
        await updateStateFromPeerStates()
        return participant.info
    }
    
    
    func processBusyMessageJSONFromContact(_ contact: OlvidUserId) async -> OlvidCallParticipantInfo? {
        guard let participant = await getParticipant(remoteCryptoId: contact.remoteCryptoId) else { assertionFailure(); return nil }
        await participant.isBusy()
        return participant.info
    }
    
    
    func processReconnectCallMessageJSONFromContact(_ contact: OlvidUserId, _ reconnectCallMessage: ReconnectCallMessageJSON) async throws {
        guard !self.state.isFinalState else { return }
        guard let participant = await getParticipant(remoteCryptoId: contact.remoteCryptoId) else {
            // Happens when receiving a message from a kicked participant
            return
        }
        let sessionDescription = RTCSessionDescription(type: reconnectCallMessage.sessionDescriptionType, sdp: reconnectCallMessage.sessionDescription)
        try await participant.handleReceivedRestartSdp(
            sessionDescription: sessionDescription,
            reconnectCounter: reconnectCallMessage.reconnectCounter ?? 0,
            peerReconnectCounterToOverride: reconnectCallMessage.peerReconnectCounterToOverride ?? 0)
    }
    
    
    func processNewParticipantAnswerMessageJSONFromContact(_ contact: OlvidUserId, _ newParticipantAnswer: NewParticipantAnswerMessageJSON) async throws {
        let participant: OlvidCallParticipant?
        if let deviceUID = contact.contactDeviceIdentifier?.deviceUID {
            participant = await setDeviceUIDOfParticipant(remoteCryptoId: contact.remoteCryptoId, deviceUID: deviceUID)
        } else {
            Self.logger.fault("☎️ We received a NewParticipantAnswerMessageJSON message, which should contain the information about the remote device")
            assertionFailure()
            participant = await getParticipant(remoteCryptoId: contact.remoteCryptoId)
            await participant?.destinationDeviceIsKnownOrWillNotBeKnown()
        }
        guard let participant else { assertionFailure(); return }
        guard Self.shouldISendTheOfferToCallParticipant(ownedCryptoId: ownedCryptoId, cryptoId: contact.remoteCryptoId) else { return }
        let sessionDescription = RTCSessionDescription(type: newParticipantAnswer.sessionDescriptionType, sdp: newParticipantAnswer.sessionDescription)
        try await participant.processNewParticipantAnswerMessageJSON(sessionDescription: sessionDescription)
    }
    
}


// MARK: - Ending a call

extension OlvidCall {
    
    
    /// Called from the ``OlvidCallManager`` when an incoming call times out because the user did not answer it
    func endIncomingCallAsItTimedOut() async -> (callReport: CallReport?, cxCallEndedReason: CXCallEndedReason?) {
        guard direction == .incoming else {
            assertionFailure()
            return (nil, nil)
        }
        guard state == .initial else {
            assertionFailure()
            return (nil, nil)
        }
        let values = await endWebRTCCall(reason: .callTimedOut)
        assert(values.cxCallEndedReason == .unanswered)
        return values
    }

    
    /// Called from the ``OlvidCallManager`` when an outgoing call times out because the remote user did not answer it
    func endOutgoingCallAsItTimedOut() async -> (callReport: CallReport?, cxCallEndedReason: CXCallEndedReason?) {
        guard direction == .outgoing else {
            assertionFailure()
            return (nil, nil)
        }
        guard state == .ringing else {
            assertionFailure()
            return (nil, nil)
        }
        let values = await endWebRTCCall(reason: .callTimedOut)
        assert(values.cxCallEndedReason == .unanswered)
        return values
    }

    
    /// This method is eventually called when ending a call, either because the local user requested to end the call, or the remote user hanged up,
    /// Or because some error occured, etc. It perfoms final important steps before settting the call into an appropriate final state.
    /// This is the only method that actually sets the call state to a final state.
    private func endWebRTCCall(reason: EndCallReason) async -> (callReport: CallReport?, cxCallEndedReason: CXCallEndedReason?) {
        
        assert(delegate != nil)
        
        guard !state.isFinalState else { return (nil, nil) }
        
        // Potentially send a hangup/reject call message to the other participants or to the caller
        
        await sendAppropriateMessageOnEndCall(reason: reason)
                        
        // Change the call state

        let finalStateToSet = getFinalStateToSetOnEndCall(reason: reason)
        assert(finalStateToSet.isFinalState)
        await setCallState(to: finalStateToSet)

        // In the end, we might have to report to our delegate

        let callReport = getEndCallReport(reason: reason)
        
        // Get appropriate end reason
        
        let cxCallEndedReason = getEndCallReasonForOurDelegate(reason: reason)

        // Return values
        
        return (callReport, cxCallEndedReason)
        
    }
    
    
    private func getFinalStateToSetOnEndCall(reason: EndCallReason) -> State {
    
        switch reason {

        case .callTimedOut:
            return .unanswered
            
        case .localUserRequest:
            switch direction {
            case .outgoing:
                return .hangedUp
            case .incoming:
                switch state {
                case .initial, .ringing, .initializingCall:
                    return .callRejected
                case .userAnsweredIncomingCall, .callInProgress, .outgoingCallIsConnecting, .reconnecting:
                    return .hangedUp
                case .gettingTurnCredentials, .hangedUp, .kicked, .callRejected, .unanswered, .answeredOnAnotherDevice:
                    assertionFailure()
                    return .callRejected
                }
            }
            
        case .kicked:
            assert(direction == .incoming)
            return .kicked

        case .allOtherParticipantsLeft:
            if state == .initial {
                return .unanswered
            } else {
                return .hangedUp
            }
            
        case .answeredOrRejectedOnOtherDevice(answered: _):
            assert(direction == .incoming)
            return .answeredOnAnotherDevice
            
        case .deniedRecordPermission:
            return .unanswered
            
        }

    }
    
    
    /// Exclusively called from ``endWebRTCCall(reason:)``
    private func getEndCallReasonForOurDelegate(reason: EndCallReason) -> CXCallEndedReason? {
        switch reason {
        case .callTimedOut:
            return .unanswered
        case .localUserRequest:
            return nil
        case .kicked:
            assert(direction == .incoming)
            return .remoteEnded
        case .allOtherParticipantsLeft:
            if state == .initial {
                return .unanswered
            } else {
                return .remoteEnded
            }
        case .answeredOrRejectedOnOtherDevice(answered: let answered):
            assert(direction == .incoming)
            return answered ? .answeredElsewhere : .declinedElsewhere
        case .deniedRecordPermission:
            return .failed
        }
    }

    
    /// Exclusively called from ``endWebRTCCall(reason:)``
    private func sendAppropriateMessageOnEndCall(reason: EndCallReason) async {
        
        switch reason {

        case .callTimedOut:
            break // 2024-06-25 We used to call sendLocalUserHangedUpMessageToAllParticipants() here
            
        case .localUserRequest:
            switch direction {
            case .outgoing:
                await sendLocalUserHangedUpMessageToAllParticipants()
            case .incoming:
                switch state {
                case .initial, .ringing, .initializingCall:
                    await sendRejectIncomingCallToCaller()
                case .userAnsweredIncomingCall, .callInProgress, .outgoingCallIsConnecting, .reconnecting:
                    await sendLocalUserHangedUpMessageToAllParticipants()
                case .gettingTurnCredentials, .hangedUp, .kicked, .callRejected, .unanswered:
                    assertionFailure()
                    await sendRejectIncomingCallToCaller()
                case .answeredOnAnotherDevice:
                    assertionFailure()
                    break
                }
            }
            
        case .kicked:
            assert(direction == .incoming) // No need to send reject/hangup message

        case .allOtherParticipantsLeft:
            break // No need to send reject/hangup message

        case .answeredOrRejectedOnOtherDevice(answered: _):
            assert(direction == .incoming) // No need to send reject/hangup message

        case .deniedRecordPermission:
            await sendRejectIncomingCallToCaller()
        }
        
    }
    
    
    /// Exclusively called from ``endWebRTCCall(reason:)``
    private func getEndCallReport(reason: EndCallReason) -> CallReport? {
        
        switch reason {
        case .callTimedOut:
            switch direction {
            case .incoming:
                return .missedIncomingCall(caller: callerOfIncomingCall?.info, initialOtherParticipantsCount: self.initialParticipantCount)
            case .outgoing:
                return .unansweredOutgoingCall(with: otherParticipants.map({ $0.info }))
            }
        case .localUserRequest:
            switch direction {
            case .incoming:
                switch state {
                case .initial, .ringing, .initializingCall, .callRejected:
                    return .rejectedIncomingCall(caller: callerOfIncomingCall?.info, participantCount: initialParticipantCount)
                case .userAnsweredIncomingCall, .callInProgress, .hangedUp, .outgoingCallIsConnecting, .reconnecting:
                    return nil
                case .gettingTurnCredentials, .kicked, .unanswered, .answeredOnAnotherDevice:
                    assertionFailure()
                    return .rejectedIncomingCall(caller: callerOfIncomingCall?.info, participantCount: initialParticipantCount)
                }
            case .outgoing:
                return .uncompletedOutgoingCall(with: otherParticipants.map({ $0.info }))
            }
        case .kicked:
            assert(direction == .incoming)
            return nil
        case .allOtherParticipantsLeft:
            return nil
        case .answeredOrRejectedOnOtherDevice(let answered):
            assert(direction == .incoming)
            assert(callerOfIncomingCall?.info != nil)
            return .answeredOrRejectedOnOtherDevice(caller: callerOfIncomingCall?.info, answered: answered)
        case .deniedRecordPermission:
            return .rejectedIncomingCallBecauseOfDeniedRecordPermission(caller: callerOfIncomingCall?.info, participantCount: initialParticipantCount)
        }
        
    }
    
    
    private func sendLocalUserHangedUpMessageToAllParticipants() async {
        let hangedUpMessage = HangedUpMessageJSON()
        for participant in self.otherParticipants {
            do {
                try await sendWebRTCMessage(to: participant, innerMessage: hangedUpMessage, forStartingCall: false)
            } catch {
                os_log("☎️ Failed to send a HangedUpMessageJSON to a participant: %{public}@", log: Self.log, type: .error, error.localizedDescription)
                assertionFailure() // Continue anyway
            }
        }
    }

    
    private func sendRejectIncomingCallToCaller() async {
        assert(direction == .incoming)
        guard let caller = self.callerOfIncomingCall else {
            os_log("Could not find caller", log: Self.log, type: .fault)
            assertionFailure()
            return
        }
        let rejectedMessage = RejectCallMessageJSON()
        do {
            try await sendWebRTCMessage(to: caller, innerMessage: rejectedMessage, forStartingCall: false)
        } catch {
            os_log("Failed to send a RejectCallMessageJSON to the caller: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure() // Continue anyway
        }
    }
    
    
    private func sendBusyMessageToCaller() async {
        assert(direction == .incoming)
        guard let caller = self.callerOfIncomingCall else {
            os_log("Could not find caller", log: Self.log, type: .fault)
            assertionFailure()
            return
        }
        let rejectedMessage = BusyMessageJSON()
        do {
            try await sendWebRTCMessage(to: caller, innerMessage: rejectedMessage, forStartingCall: false)
        } catch {
            os_log("Failed to send a BusyMessageJSON to the caller: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure() // Continue anyway
        }
    }
    

    enum EndCallReason {
        case callTimedOut
        case localUserRequest
        case kicked // incoming call only
        case allOtherParticipantsLeft
        case answeredOrRejectedOnOtherDevice(answered: Bool)
        case deniedRecordPermission
    }

    
}


// MARK: - Sending WebRTC (and other) messages

extension OlvidCall {
    
    private func sendWebRTCMessage(to: OlvidCallParticipant, innerMessage: WebRTCInnerMessageJSON, forStartingCall: Bool) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        let message = try innerMessage.embedInWebRTCMessageJSON(callIdentifier: uuidForWebRTC)
        if case .hangedUp = message.messageType {
            // Also send message on the data channel, if the caller is gone
            do {
                let hangedUpDataChannel = try HangedUpDataChannelMessageJSON().embedInWebRTCDataChannelMessageJSON()
                try await to.sendDataChannelMessage(hangedUpDataChannel)
            } catch {
                os_log("☎️ Could not send HangedUpDataChannelMessageJSON: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                // Continue anyway
            }
        }
        switch to.knownOrUnknown {
        case .known(contactObjectID: _, contactIdentifier: let contactIdentifier, contactDeviceUID: let contactDeviceUID):
            if let contactDeviceUID {
                let contactDeviceIdentifier = ObvContactDeviceIdentifier(contactIdentifier: contactIdentifier, deviceUID: contactDeviceUID)
                await delegate.newWebRTCMessageToSendToSingleContactDevice(webrtcMessage: message, contactDeviceIdentifier: contactDeviceIdentifier)
            } else {
                await delegate.newWebRTCMessageToSendToAllContactDevices(webrtcMessage: message, contactIdentifier: contactIdentifier, forStartingCall: forStartingCall)
            }
        case .unknown(remoteCryptoId: let remoteCryptoId):
            guard message.messageType.isAllowedToBeRelayed else { assertionFailure(); return }
            guard self.direction == .incoming else { assertionFailure(); return }
            guard let caller = self.callerOfIncomingCall else {
                // This happen if the caller quit the call before we did, and we continued the call with a user who is not a contact
                return
            }
            let toContactIdentity = remoteCryptoId.getIdentity()

            do {
                let dataChannelMessage = try RelayMessageJSON(to: toContactIdentity, relayedMessageType: message.messageType.rawValue, serializedMessagePayload: message.serializedMessagePayload).embedInWebRTCDataChannelMessageJSON()
                try await caller.sendDataChannelMessage(dataChannelMessage)
            } catch {
                assertionFailure()
                os_log("☎️ Could not send RelayMessageJSON: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                return
            }
        }
    }
    
}


// MARK: - Implementing CallParticipantDelegate

extension OlvidCall: OlvidCallParticipantDelegate {
    
    func localVideoTrackWasAdded(for callParticipant: OlvidCallParticipant, videoTrack: RTCVideoTrack) async {
        if self.localPreviewVideoTrack != nil {
            let forScreenCast: Bool
            switch videoTrack.trackId {
            case ObvMessengerConstants.TrackId.video:
                forScreenCast = false
            case ObvMessengerConstants.TrackId.screencast:
                forScreenCast = true
            default:
                assertionFailure()
                return
            }
            assert(!forScreenCast, "We do not expect a local screencast track")
            do {
                try await callParticipant.setLocalVideoTrack(isEnabled: true)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }
    
    
    func participantWasUpdated(callParticipant: OlvidCallParticipant, updateKind: OlvidCallParticipant.UpdateKind) async {
        
        guard self.otherParticipants.firstIndex(where: { $0.cryptoId == callParticipant.cryptoId }) != nil else {
            // Happens when the participant was kicked
            return
        }
        
        switch updateKind {
        case .state(newState: let newState):
            switch newState {
            case .initial:
                break
            case .startCallMessageSent:
                break
            case .ringing:
                guard self.direction == .outgoing else { return }
                guard [State.initializingCall, .gettingTurnCredentials, .initial].contains(state) else { return }
                await setCallState(to: .ringing)
            case .busy:
                await removeParticipant(callParticipant: callParticipant)
            case .connectingToPeer:
                guard state == .userAnsweredIncomingCall else { return }
                await setCallState(to: .initializingCall)
            case .connected:
                guard state != .callInProgress else { return }
                await setCallState(to: .callInProgress)
            case .reconnecting:
                // If the call is not in a final state and
                // if all other participants are in a reconnecting state, play a sound
                if !state.isFinalState {
                    let allOtherParticipantsAreReconnecting = otherParticipants.allSatisfy({ $0.state == .reconnecting })
                    if allOtherParticipantsAreReconnecting {
                        await setCallState(to: .reconnecting)
                    }
                }
            case .callRejected, .hangedUp, .kicked, .failed, .connectionTimeout:
                break
            }
        case .contactID:
            break
        case .contactMuted:
            break
        }
    }
    
    
    func connectionIsChecking(for callParticipant: OlvidCallParticipant) {
        // Task { await CallSounds.shared.prepareFeedback() }
    }
    
    
    func connectionIsConnected(for callParticipant: OlvidCallParticipant, oldParticipantState: OlvidCallParticipant.State) async {
        
        do {
            if self.direction == .outgoing && oldParticipantState != .connected && oldParticipantState != .reconnecting {
                let message = try await UpdateParticipantsMessageJSON(callParticipants: otherParticipants).embedInWebRTCDataChannelMessageJSON()
                let callParticipantsToNotify = otherParticipants.filter({ $0.cryptoId != callParticipant.cryptoId })
                for callParticipant in callParticipantsToNotify {
                    try await callParticipant.sendDataChannelMessage(message)
                }
            }
        } catch {
            os_log("We failed to notify the other participants about the new participants list: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
            // Continue anyway
        }
        
        // If the current state is not already "callInProgress", it means that the first participant
        // just joined to call. We want to change the state to "callInProgress" (which will play the
        // appropriate sounds, etc.).
        
        await setCallState(to: .callInProgress)
    }
    
    
    func connectionWasClosed(for callParticipant: OlvidCallParticipant) async {
        await removeParticipant(callParticipant: callParticipant)
        await updateStateFromPeerStates()
    }
    
    
    func dataChannelIsOpened(for callParticipant: OlvidCallParticipant) async {
        guard self.direction == .outgoing else { return }
        do {
            let message = try await UpdateParticipantsMessageJSON(callParticipants: otherParticipants).embedInWebRTCDataChannelMessageJSON()
            try await callParticipant.sendDataChannelMessage(message)
        } catch {
            os_log("We failed to notify the participant about the new participants list: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }
    
    
    func updateParticipants(with allCallParticipants: [ContactBytesAndNameJSON]) async throws {
        
        os_log("☎️ Entering updateParticipants(with allCallParticipants: [ContactBytesAndNameJSON])", log: Self.log, type: .info)
        os_log("☎️ The latest list of call participants contains %d participant(s)", log: Self.log, type: .info, allCallParticipants.count)
        os_log("☎️ Before processing this list, we consider there are %d participant(s) in this call", log: Self.log, type: .info, otherParticipants.count)
        
        // In case of large group calls, we can encounter race conditions. We prevent that by waiting until it is safe to process the new participants list

        await waitUntilItIsSafeToModifyParticipants()
        
        // Now that it is our turn to potentially modify the participants set, we must make sure no other task will interfere.
        // The mechanism allowing to do so requires to set the following Boolean to true now, and to false when we are done.
        
        aTaskIsCurrentlyModifyingCallParticipants = true
        defer { aTaskIsCurrentlyModifyingCallParticipants = false }

        // We can proceed
        
        guard direction == .incoming else {
            assertionFailure()
            throw ObvError.selfIsNotIncomingCall
        }
        guard let turnCredentials = self.turnCredentialsReceivedFromCaller else {
            assertionFailure()
            throw ObvError.noTurnCredentialsFound
        }
        
        let selfIsMuted = self.selfIsMuted

        // Remove our own identity from the list of call participants.
        
        let allCallParticipants = allCallParticipants.filter({ $0.byteContactIdentity != ownedCryptoId.getIdentity() })

        // Determine the CryptoIds of the local list of participants and of the reveived version of the list
        
        let currentIdsOfParticipants = Set(otherParticipants.compactMap({ $0.cryptoId }))
        let updatedIdsOfParticipants = Set(allCallParticipants.compactMap({ try? ObvCryptoId(identity: $0.byteContactIdentity) }))
        
        // Determine the participants to add to the local list, and those that should be removed
        
        let idsOfParticipantsToAdd = updatedIdsOfParticipants.subtracting(currentIdsOfParticipants)
        let idsOfParticipantsToRemove = currentIdsOfParticipants.subtracting(updatedIdsOfParticipants)

        // Perform the necessary steps to add the participants

        os_log("☎️ We have %d participant(s) to add", log: Self.log, type: .info, idsOfParticipantsToAdd.count)
        
        for remoteCryptoId in idsOfParticipantsToAdd {
            
            let gatheringPolicy = allCallParticipants
                .first(where: { $0.byteContactIdentity == remoteCryptoId.getIdentity() })
                .map({ $0.gatheringPolicy ?? .gatherOnce }) ?? .gatherOnce
            
            let displayName = allCallParticipants
                .first(where: { $0.byteContactIdentity == remoteCryptoId.getIdentity() })
                .map({ $0.displayName }) ?? "-"
            
            let shouldISendTheOfferToCallParticipant = Self.shouldISendTheOfferToCallParticipant(ownedCryptoId: ownedCryptoId, cryptoId: remoteCryptoId)
                        
            let callParticipant = try await OlvidCallParticipant.createOtherParticipantOfIncomingCall(
                ownedCryptoId: ownedCryptoId,
                remoteCryptoId: remoteCryptoId,
                gatheringPolicy: gatheringPolicy,
                displayName: displayName,
                shouldISendTheOfferToCallParticipant: shouldISendTheOfferToCallParticipant, 
                rtcPeerConnectionQueue: rtcPeerConnectionQueue,
                factory: factory)
                        
            await addParticipant(callParticipant: callParticipant)
            await delegate?.newParticipantWasAdded(call: self, callParticipant: callParticipant)

            if shouldISendTheOfferToCallParticipant {
                os_log("☎️ Will set credentials for offer to a call participant", log: Self.log, type: .info)
                try await callParticipant.setTurnCredentialsAndCreateUnderlyingPeerConnection(turnCredentials: turnCredentials)
            } else {
                os_log("☎️ No need to send offer to the call participant", log: Self.log, type: .info)
                /// check if we already received the offer the CallParticipant is supposed to send us
                if let (user, newParticipantOfferMessage) = self.receivedOfferMessages.removeValue(forKey: remoteCryptoId) {
                    try await processNewParticipantOfferMessageJSONFromContact(user, newParticipantOfferMessage)
                }
            }

        }

        // If we were muted, we must make sure we stay muted for all participant, including the new ones
        
        try await setMuteSelfForOtherParticipants(muted: selfIsMuted)

        // Perform the necessary steps to remove the participants.
        // Note that we know the caller is among the participants and we do not want to remove her here.

        os_log("☎️ We have %d participant(s) to remove (unless one if the caller)", log: Self.log, type: .info, idsOfParticipantsToRemove.count)

        for remoteCryptoId in idsOfParticipantsToRemove {
            guard let participant = otherParticipants.first(where: { $0.cryptoId == remoteCryptoId }) else { continue }
            guard !participant.isCallerOfIncomingCall else { continue }
            try await participant.closeConnection()
            await removeParticipant(callParticipant: participant)
        }

    }
    
    
    func relay(from: ObvTypes.ObvCryptoId, to: ObvTypes.ObvCryptoId, messageType: ObvUICoreData.WebRTCMessageJSON.MessageType, messagePayload: String) async {
        
        guard messageType.isAllowedToBeRelayed else { assertionFailure(); return }

        guard let participant = otherParticipants.first(where: { $0.cryptoId == to }) else { assertionFailure(); return }
        let message: WebRTCDataChannelMessageJSON
        do {
            message = try RelayedMessageJSON(from: from.getIdentity(), relayedMessageType: messageType.rawValue, serializedMessagePayload: messagePayload).embedInWebRTCDataChannelMessageJSON()
        } catch {
            os_log("☎️ Could not send UpdateParticipantsMessageJSON: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }
        do {
            try await participant.sendDataChannelMessage(message)
        } catch {
            os_log("☎️ Could not send data channel message: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            return
        }
    }
    
    
    
    /// Called by an `OlvidCallParticipant` when receiving a hanged up message. Since we want this message (received on the WebRTC data channel) to receive the same
    /// treatment as the one we can received on the WebSocket, we notify our delegate.
    @MainActor
    func receivedHangedUpMessage(from callParticipant: OlvidCallParticipant, messagePayload: String) async {
        let fromOlvidUser: OlvidUserId
        switch callParticipant.knownOrUnknown {
        case .known(contactObjectID: let contactObjectID, contactIdentifier: let contactIdentifier, contactDeviceUID: let contactDeviceUID):
            do {
                guard let contact = try PersistedObvContactIdentity.get(objectID: contactObjectID.objectID, within: ObvStack.shared.viewContext) else {
                    assertionFailure()
                    os_log("☎️ Could not find the contact to whom we should relay the message", log: Self.log, type: .error)
                    return
                }
                fromOlvidUser = .known(contactObjectID: contactObjectID, contactIdentifier: contactIdentifier, contactDeviceUID: contactDeviceUID, displayName: contact.customOrNormalDisplayName)
            } catch {
                assertionFailure()
                return
            }
        case .unknown:
            fromOlvidUser = .unknown(ownCryptoId: ownedCryptoId, remoteCryptoId: callParticipant.cryptoId, displayName: callParticipant.displayName)
        }
        await delegate?.receivedHangedUpMessage(
            call: self,
            serializedMessagePayload: messagePayload,
            uuidForWebRTC: uuidForWebRTC,
            fromOlvidUser: fromOlvidUser)
    }
    
    
    /// Processes a messages that was relayed by the caller but originally sent by the `from`
    @MainActor
    func receivedRelayedMessage(from: ObvTypes.ObvCryptoId, messageType: ObvUICoreData.WebRTCMessageJSON.MessageType, messagePayload: String) async {
        os_log("☎️ Call to receivedRelayedMessage", log: Self.log, type: .info)
        guard let callParticipant = otherParticipants.first(where: { $0.cryptoId == from }) else {
            os_log("☎️ Could not find the call participant in receivedRelayedMessage. We store the relayed message for later", log: Self.log, type: .info)
            if var previous = pendingReceivedRelayedMessages[from] {
                previous.append((messageType, messagePayload))
                pendingReceivedRelayedMessages[from] = previous
            } else {
                pendingReceivedRelayedMessages[from] = [(messageType, messagePayload)]
            }
            return
        }
        let fromOlvidUser: OlvidUserId
        switch callParticipant.knownOrUnknown {
        case .known(contactObjectID: let contactObjectID, contactIdentifier: let contactIdentifier, contactDeviceUID: let contactDeviceUID):
            do {
                guard let contact = try PersistedObvContactIdentity.get(objectID: contactObjectID.objectID, within: ObvStack.shared.viewContext) else {
                    assertionFailure()
                    os_log("☎️ Could not find the contact to whom we should relay the message", log: Self.log, type: .error)
                    return
                }
                fromOlvidUser = .known(contactObjectID: contactObjectID, contactIdentifier: contactIdentifier, contactDeviceUID: contactDeviceUID, displayName: contact.customOrNormalDisplayName)
            } catch {
                assertionFailure()
                return
            }
        case .unknown(remoteCryptoId: let remoteCryptoId):
            os_log("☎️ Receiving a message from a participant that is not a contact. The message was relayed by the caller", log: Self.log, type: .error)
            fromOlvidUser = .unknown(ownCryptoId: ownedCryptoId, remoteCryptoId: remoteCryptoId, displayName: callParticipant.displayName)
        }
        await delegate?.receivedRelayedMessage(
            call: self,
            messageType: messageType,
            serializedMessagePayload: messagePayload,
            uuidForWebRTC: uuidForWebRTC,
            fromOlvidUser: fromOlvidUser)
    }

    
    @MainActor
    func sendStartCallMessage(to callParticipant: OlvidCallParticipant, sessionDescription: RTCSessionDescription, turnCredentials: TurnCredentials) async throws {
        
        let gatheringPolicy = await callParticipant.gatheringPolicy
        
        guard let turnServers = turnCredentials.turnServers else {
            assertionFailure()
            os_log("☎️ The turn servers are not set, which is unexpected at this point", log: Self.log, type: .fault)
            throw ObvError.noTurnServersFound
        }

        var filteredGroupId: GroupIdentifier?
        switch groupId {
        case .groupV1(groupV1Identifier: let groupV1Identifier):
            do {
                guard let contactGroup = try? PersistedContactGroup.getContactGroup(groupIdentifier: groupV1Identifier, ownedCryptoId: ownedCryptoId, within: ObvStack.shared.viewContext) else {
                    os_log("☎️ Could not find contactGroup", log: Self.log, type: .fault)
                    return
                }
                let groupMembers = Set(contactGroup.contactIdentities.map { $0.cryptoId })
                if groupMembers.contains(callParticipant.cryptoId) {
                    filteredGroupId = .groupV1(groupV1Identifier: groupV1Identifier)
                }
            }
        case .groupV2(groupV2Identifier: let groupV2Identifier):
            do {
                guard let group = try? PersistedGroupV2.get(ownIdentity: ownedCryptoId, appGroupIdentifier: groupV2Identifier, within: ObvStack.shared.viewContext) else {
                    os_log("☎️ Could not find PersistedGroupV2", log: Self.log, type: .fault)
                    return
                }
                let groupMembers = Set(group.otherMembers.compactMap({ $0.cryptoId }))
                if groupMembers.contains(callParticipant.cryptoId) {
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
            participantCount: otherParticipants.count,
            groupIdentifier: filteredGroupId,
            gatheringPolicy: gatheringPolicy)
        
        try await sendWebRTCMessage(to: callParticipant, innerMessage: message, forStartingCall: true)
        
    }
    
    
    func sendAnswerCallMessage(to callParticipant: OlvidCallParticipant, sessionDescription: RTCSessionDescription) async throws {
        
        let message: WebRTCInnerMessageJSON
        let messageDescripton = callParticipant.isCallerOfIncomingCall ? "AnswerIncomingCall" : "NewParticipantAnswerMessage"
        do {
            if callParticipant.isCallerOfIncomingCall {
                message = try AnswerCallJSON(sessionDescriptionType: RTCSessionDescription.string(for: sessionDescription.type), sessionDescription: sessionDescription.sdp)
            } else {
                message = try NewParticipantAnswerMessageJSON(sessionDescriptionType: RTCSessionDescription.string(for: sessionDescription.type), sessionDescription: sessionDescription.sdp)
            }
        } catch {
            os_log("Could not create and send %{public}@: %{public}@", log: Self.log, type: .fault, messageDescripton, error.localizedDescription)
            assertionFailure()
            throw error
        }
        try await sendWebRTCMessage(to: callParticipant, innerMessage: message, forStartingCall: false)
    }
    
    
    func sendNewParticipantOfferMessage(to callParticipant: OlvidCallParticipant, sessionDescription: RTCSessionDescription) async throws {
        let message = try await NewParticipantOfferMessageJSON(
            sessionDescriptionType: RTCSessionDescription.string(for: sessionDescription.type),
            sessionDescription: sessionDescription.sdp,
            gatheringPolicy: callParticipant.gatheringPolicy)
        try await sendWebRTCMessage(to: callParticipant, innerMessage: message, forStartingCall: false)
    }
    
    
    func sendNewParticipantAnswerMessage(to callParticipant: OlvidCallParticipant, sessionDescription: RTCSessionDescription) async throws {
        let message = try NewParticipantAnswerMessageJSON(
            sessionDescriptionType: RTCSessionDescription.string(for: sessionDescription.type),
            sessionDescription: sessionDescription.sdp)
        try await sendWebRTCMessage(to: callParticipant, innerMessage: message, forStartingCall: false)
    }
    
    
    func sendReconnectCallMessage(to callParticipant: OlvidCallParticipant, sessionDescription: RTCSessionDescription, reconnectCounter: Int, peerReconnectCounterToOverride: Int) async throws {
        let message = try ReconnectCallMessageJSON(
            sessionDescriptionType: RTCSessionDescription.string(for: sessionDescription.type),
            sessionDescription: sessionDescription.sdp,
            reconnectCounter: reconnectCounter,
            peerReconnectCounterToOverride: peerReconnectCounterToOverride)
        try await sendWebRTCMessage(to: callParticipant, innerMessage: message, forStartingCall: false)
    }
    
    
    func sendNewIceCandidateMessage(to callParticipant: OlvidCallParticipant, iceCandidate: RTCIceCandidate) async throws {
        let message = IceCandidateJSON(sdp: iceCandidate.sdp, sdpMLineIndex: iceCandidate.sdpMLineIndex, sdpMid: iceCandidate.sdpMid)
        try await sendWebRTCMessage(to: callParticipant, innerMessage: message, forStartingCall: false)
    }
    
    
    func sendRemoveIceCandidatesMessages(to callParticipant: OlvidCallParticipant, candidates: [RTCIceCandidate]) async throws {
        let message = RemoveIceCandidatesMessageJSON(candidates: candidates.map({ IceCandidateJSON(sdp: $0.sdp, sdpMLineIndex: $0.sdpMLineIndex, sdpMid: $0.sdpMid) }))
        try await sendWebRTCMessage(to: callParticipant, innerMessage: message, forStartingCall: false)
    }
    
}


// MARK: - Helpers for managing participants

extension OlvidCall {
    
    @MainActor
    private func addParticipant(callParticipant: OlvidCallParticipant) async {
        await callParticipant.setDelegate(to: self)
        guard otherParticipants.firstIndex(where: { $0.cryptoId == callParticipant.cryptoId }) == nil else {
            os_log("☎️ The participant already exists in the set, we should never happen since we have an anti-race mechanism", log: Self.log, type: .fault)
            assertionFailure()
            return
        }
        withAnimation {
            otherParticipants.append(callParticipant)
            otherParticipants.sort(by: \.displayName)
        }
        let iceCandidates = pendingIceCandidates.removeValue(forKey: callParticipant.cryptoId) ?? []
        for iceCandidate in iceCandidates {
            try? await callParticipant.processIceCandidatesJSON(message: iceCandidate)
        }
        // Process the messages from this participant that were relayed by the caller that were received before we were aware of this participant.
        if let relayedMessagesToProcess = pendingReceivedRelayedMessages.removeValue(forKey: callParticipant.cryptoId) {
            for relayedMsg in relayedMessagesToProcess {
                os_log("☎️ Processing a relayed message received while we were not aware of this call participant", log: Self.log, type: .info)
                await receivedRelayedMessage(from: callParticipant.cryptoId, messageType: relayedMsg.messageType, messagePayload: relayedMsg.messagePayload)
            }
        }
    }

    
    @MainActor
    func setDeviceUIDOfParticipant(remoteCryptoId: ObvCryptoId, deviceUID: UID) async -> OlvidCallParticipant? {
        let participant = getParticipant(remoteCryptoId: remoteCryptoId)
        participant?.setDeviceUID(deviceUID)
        return participant
    }
    
    
    @MainActor
    func getParticipant(remoteCryptoId: ObvCryptoId) -> OlvidCallParticipant? {
        return otherParticipants.first(where: { $0.cryptoId == remoteCryptoId })
    }

    
    @MainActor
    func addPendingOffer(_ receivedOfferMessage: (OlvidUserId, NewParticipantOfferMessageJSON), from remoteCryptoId: ObvCryptoId) async {
        assert(receivedOfferMessages[remoteCryptoId] == nil)
        receivedOfferMessages[remoteCryptoId] = receivedOfferMessage
    }

    
    @MainActor
    private func removeParticipant(callParticipant: OlvidCallParticipant) async {
        
        guard let index = otherParticipants.firstIndex(where: { $0.cryptoId == callParticipant.cryptoId }) else { return }
        otherParticipants.remove(at: index)
        
        if otherParticipants.isEmpty {
            _ = await endWebRTCCall(reason: .allOtherParticipantsLeft)
        }
        
        // If we are the caller (i.e., if this is an outgoing call) and if the call is not over, we send an updated list of participants to the remaining participants
        
        if direction == .outgoing && !state.isFinalState {
            let message: WebRTCDataChannelMessageJSON
            do {
                message = try await UpdateParticipantsMessageJSON(callParticipants: otherParticipants).embedInWebRTCDataChannelMessageJSON()
            } catch {
                os_log("☎️ Could not send UpdateParticipantsMessageJSON: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
            for otherParticipant in otherParticipants {
                try? await otherParticipant.sendDataChannelMessage(message)
            }
        }

    }
    
    
    private func updateStateFromPeerStates() async {
        for callParticipant in otherParticipants {
            guard callParticipant.state.isFinalState else { return }
        }
        // If we reach this point, all call participants are in a final state, we can end the call.
        _ = await endWebRTCCall(reason: .allOtherParticipantsLeft)
    }

    
    /// This method allows to make sure we are not risking race conditions when updating the list of participants.
    private func waitUntilItIsSafeToModifyParticipants() async {
        while aTaskIsCurrentlyModifyingCallParticipants {
            os_log("☎️ Since we are already currently modifying call participants, we must wait", log: Self.log, type: .info)
            let sleepTask: Task<Void, Error> = Task { try? await Task.sleep(seconds: 60) }
            sleepingTasksToCancelWhenEndingCallParticipantsModification.insert(sleepTask, at: 0) // First in, first out
            try? await sleepTask.value // Note the "try?": we don't want to throw when the task is cancelled
        }
    }

    
    private func oneOfTheTaskCurrentlyModifyingCallParticipantsIsDone() {
        assert(!aTaskIsCurrentlyModifyingCallParticipants)
        while let sleepingTask = sleepingTasksToCancelWhenEndingCallParticipantsModification.popLast() {
            os_log("☎️ Since a task potentially modifying the set of call participants is done, we can proceed with the next one", log: Self.log, type: .info)
            sleepingTask.cancel()
        }
    }

}


// MARK: - ICE candidates

extension OlvidCall {
    
    @MainActor
    func processIceCandidatesJSON(iceCandidate: IceCandidateJSON, participantId: OlvidUserId) async throws {
        if let callParticipant = otherParticipants.first(where: { $0.cryptoId == participantId.remoteCryptoId }) {
            try await callParticipant.processIceCandidatesJSON(message: iceCandidate)
        } else {
            if var previousCandidates = pendingIceCandidates[participantId.remoteCryptoId] {
                previousCandidates.append(iceCandidate)
                pendingIceCandidates[participantId.remoteCryptoId] = previousCandidates
            } else {
                pendingIceCandidates[participantId.remoteCryptoId] = [iceCandidate]
            }
        }
    }

    
    @MainActor
    func removeIceCandidatesJSON(removeIceCandidatesJSON: RemoveIceCandidatesMessageJSON, participantId: OlvidUserId) async throws {
        if let callParticipant = otherParticipants.first(where: { $0.cryptoId == participantId.remoteCryptoId }) {
            await callParticipant.processRemoveIceCandidatesMessageJSON(message: removeIceCandidatesJSON)
        } else {
            if var candidates = pendingIceCandidates[participantId.remoteCryptoId] {
                candidates.removeAll(where: { removeIceCandidatesJSON.candidates.contains($0) })
                pendingIceCandidates[participantId.remoteCryptoId] = candidates
            }
        }
    }

    
}


// MARK: - Errors

extension OlvidCall {
    
    enum ObvError: Error {
        case delegateIsNil
        case couldNotFindCallerAmongContacts
        case callerIsNotSet
        case tryingToStartOutgoingCallAlthoughItIsNotInInitalState
        case selfIsNotIncomingCall
        case noTurnCredentialsFound
        case noTurnServersFound
        case notOutgoingCall
        case couldNotFindParticipant
        case ownedIdentityForRequestingTurnCredentialsIsNil
        case maxOtherParticipantCountForVideoCallsExceeded
        case couldNotFindOwnedIdentity
        case contactDeviceIdentifierWasNotReceived
    }
        
}

extension OlvidCall: CustomDebugStringConvertible {
    
    var debugDescription: String {
        "OlvidCall<callIdentifierForCallKit:\(uuidForCallKit.debugDescription),uuidForWebRTC:\(uuidForWebRTC)>"
    }
    
}

// MARK: - State management

extension OlvidCall {
    
    enum State: Hashable, CustomDebugStringConvertible {
        
        case initial
        case userAnsweredIncomingCall
        case gettingTurnCredentials // Only for outgoing calls
        case initializingCall
        case ringing
        case outgoingCallIsConnecting
        case callInProgress
        case reconnecting

        case hangedUp
        case kicked
        case callRejected

        case unanswered
        case answeredOnAnotherDevice

        var debugDescription: String {
            switch self {
            case .outgoingCallIsConnecting: return "outgoingCallIsConnecting"
            case .kicked: return "kicked"
            case .userAnsweredIncomingCall: return "userAnsweredIncomingCall"
            case .gettingTurnCredentials: return "gettingTurnCredentials"
            case .initializingCall: return "initializingCall"
            case .ringing: return "ringing"
            case .initial: return "initial"
            case .callRejected: return "callRejected"
            case .callInProgress: return "callInProgress"
            case .hangedUp: return "hangedUp"
            case .unanswered: return "unanswered"
            case .answeredOnAnotherDevice: return "answeredOnAnotherDevice"
            case .reconnecting: return "reconnecting"
            }
        }

        var isFinalState: Bool {
            switch self {
            case .callRejected, .hangedUp, .unanswered, .kicked, .answeredOnAnotherDevice:
                return true
            case .gettingTurnCredentials, .userAnsweredIncomingCall, .initializingCall, .ringing, .initial, .callInProgress, .outgoingCallIsConnecting, .reconnecting:
                return false
            }
        }

    }
    

    @MainActor
    private func setCallState(to newState: State) async {
        
        guard state != newState else { return }
        guard !state.isFinalState else { return }

        let previousState = state

        if previousState == .callInProgress && newState == .ringing { return }
        
        // Going back to the initializingCall state from the ringing state is not allowed
        if previousState == .ringing && newState == .initializingCall { return }
        
        // An outgoing call can move to the outgoingCallIsConnecting state from the ringing state only.
        if newState == .outgoingCallIsConnecting && previousState != .ringing { return }

        os_log("☎️ OlvidCall will change state: %{public}@ --> %{public}@", log: Self.log, type: .info, previousState.debugDescription, newState.debugDescription)

        self.state = newState
        
        await performPostStateChangeActions(previousState: previousState, newState: newState)
        
        Task { [weak self] in
            guard let self else { return }
            delegate?.callDidChangeState(call: self, previousState: previousState, newState: newState)
        }
        
    }
    
    
    private func performPostStateChangeActions(previousState: State, newState: State) async {
        
        if newState == .ringing {
            assert(self.direction == .outgoing)
            // Schedule a timeout after which this outgoing call should be automatically ended
            Task { [weak self] in
                os_log("☎️ Calling outgoingWasNotAnsweredToAndTimedOut", log: Self.log, type: .debug)
                try? await Task.sleep(for: Self.ringingTimeoutInterval)
                os_log("☎️ Ending ringingTimeoutInterval for outgoing call", log: Self.log, type: .debug)
                guard let self else {
                    return
                }
                guard state == .ringing else {
                    os_log("☎️ The incoming is not in the ringing state anymore, but in the %{public}@ state", log: Self.log, type: .debug, state.debugDescription)
                    return
                }
                // The following call will eventually call us back, with the endOutgoingCallAsItTimedOut() method.
                // We don't call it directly since ending the call is not enough (we have to remove it from the call manager, etc.)
                os_log("☎️ Calling outgoingWasNotAnsweredToAndTimedOut", log: Self.log, type: .debug)
                await delegate?.outgoingWasNotAnsweredToAndTimedOut(call: self)
            }
        }
        
        if newState == .callInProgress && self.dateWhenCallSwitchedToInProgress == nil {
            Task { await setDateWhenCallSwitchedToInProgressToNow() }
        }
        
        if newState.isFinalState {
            cancellables.forEach { $0.cancel() }
        }
        
        // When the local user starts an outgoing call, she might decide to switch on the speaker before the call
        // is connected. Without the following lines, WebRTC (?) automatically overrides the output audio port
        // to .none (i.e., removes the speaker). Here, we make sure that the choice of the user is maintained.
        // Note that isSpeakerEnabledValueChosenByUser is nil if the user did not touch the speaker button so, in
        // most cases, the following code does nothing.
        if let isSpeakerEnabledValueChosenByUser, newState == .callInProgress {
            let rtcAudioSession = RTCAudioSession.sharedInstance()
            rtcAudioSession.lockForConfiguration() 
            try? rtcAudioSession.overrideOutputAudioPort(isSpeakerEnabledValueChosenByUser ? .speaker : .none)
            rtcAudioSession.unlockForConfiguration()
        }
        
    }
    
    
    @MainActor
    private func setDateWhenCallSwitchedToInProgressToNow() async {
        assert(self.dateWhenCallSwitchedToInProgress == nil)
        self.dateWhenCallSwitchedToInProgress = Date.now
    }
    
        
}


// MARK: - Call Direction

extension OlvidCall {
    
    enum Direction {
        case incoming
        case outgoing
    }
    
}


// MARK: - Utils

fileprivate extension UpdateParticipantsMessageJSON {
    
    init(callParticipants: [OlvidCallParticipant]) async {
        var callParticipants_: [ContactBytesAndNameJSON] = []
        for callParticipant in callParticipants {
            let callParticipantState = callParticipant.state
            guard callParticipantState == .connected || callParticipantState == .reconnecting else { continue }
            let remoteCryptoId = callParticipant.cryptoId
            let displayName = callParticipant.displayName
            let gatheringPolicy = await callParticipant.gatheringPolicy
            callParticipants_.append(ContactBytesAndNameJSON(byteContactIdentity: remoteCryptoId.getIdentity(), displayName: displayName, gatheringPolicy: gatheringPolicy))
        }
        self.callParticipants = callParticipants_
    }
    
}


fileprivate extension AVAudioSessionPortDescription {
    
    var detailedDebugDescription: String {
        var values = [String]()
        values.append(self.portName)
        values.append(self.portType.rawValue.description)
        values.append(self.uid)
        let concat = values.joined(separator: ",")
        return "AVAudioSessionPortDescription<\(concat)>"
    }
    
}
