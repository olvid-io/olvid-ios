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
import os.log
import WebRTC
import ObvTypes
import ObvUICoreData
import ObvAppCoreConstants
import ObvCrypto


protocol OlvidCallParticipantDelegate: AnyObject {
    
    func participantWasUpdated(callParticipant: OlvidCallParticipant, updateKind: OlvidCallParticipant.UpdateKind) async

    func connectionIsChecking(for callParticipant: OlvidCallParticipant)
    func connectionIsConnected(for callParticipant: OlvidCallParticipant, oldParticipantState: OlvidCallParticipant.State) async
    func connectionWasClosed(for callParticipant: OlvidCallParticipant) async

    func dataChannelIsOpened(for callParticipant: OlvidCallParticipant) async

    func updateParticipants(with allCallParticipants: [ContactBytesAndNameJSON]) async throws
    func relay(from: ObvCryptoId, to: ObvCryptoId, messageType: WebRTCMessageJSON.MessageType, messagePayload: String) async
    func receivedRelayedMessage(from: ObvCryptoId, messageType: WebRTCMessageJSON.MessageType, messagePayload: String) async
    func receivedHangedUpMessage(from callParticipant: OlvidCallParticipant, messagePayload: String) async
    
    func localVideoTrackWasAdded(for callParticipant: OlvidCallParticipant, videoTrack: RTCVideoTrack) async
    func reevalutateScreenDimming() async

    func sendStartCallMessage(to callParticipant: OlvidCallParticipant, sessionDescription: RTCSessionDescription, turnCredentials: TurnCredentials) async throws
    func sendAnswerCallMessage(to callParticipant: OlvidCallParticipant, sessionDescription: RTCSessionDescription) async throws
    func sendNewParticipantOfferMessage(to callParticipant: OlvidCallParticipant, sessionDescription: RTCSessionDescription) async throws
    func sendNewParticipantAnswerMessage(to callParticipant: OlvidCallParticipant, sessionDescription: RTCSessionDescription) async throws
    func sendReconnectCallMessage(to callParticipant: OlvidCallParticipant, sessionDescription: RTCSessionDescription, reconnectCounter: Int, peerReconnectCounterToOverride: Int) async throws
    func sendNewIceCandidateMessage(to callParticipant: OlvidCallParticipant, iceCandidate: RTCIceCandidate) async throws
    func sendRemoveIceCandidatesMessages(to callParticipant: OlvidCallParticipant, candidates: [RTCIceCandidate]) async throws

}


final class OlvidCallParticipant: ObservableObject {
    
    private static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "OlvidCallParticipant")
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "OlvidCallParticipant")

    // Can only be updated to set a deviceUID
    private(set) var kind: Kind
    private let peerConnectionHolder: OlvidCallParticipantPeerConnectionHolder
    let displayName: String
    let isOneToOne: Bool
    @Published private(set) var state = State.initial
    private static let connectingTimeoutInterval: TimeInterval = 15.0 // 15 seconds
    private var turnCredentials: TurnCredentials?
    let shouldISendTheOfferToCallParticipant: Bool
    @Published private(set) var contactIsMuted = false
    private var callParticipantDestinationDeviceStatusManager = CallParticipantDestinationDeviceStatusManager()

    private(set) var supportsVideo = false // Set to true if we receive a VideoSupportedJSON from this participant on the data channel
    @Published private(set) var remoteCameraVideoTrackIsEnabled = false
    @Published private(set) var remoteScreenCastVideoTrackIsEnabled = false
    @Published private(set) var remoteCameraVideoTrack: RTCVideoTrack?
    @Published private(set) var remoteScreenCastVideoTrack: RTCVideoTrack?

    private weak var delegate: OlvidCallParticipantDelegate?

    var cryptoId: ObvCryptoId {
        switch kind {
        case .otherParticipantOfIncomingCall(knownOrUnknown: let knownOrUnknown):
            switch knownOrUnknown {
            case .known(contactObjectID: _, contactIdentifier: let contactIdentifier, contactDeviceUID: _):
                return contactIdentifier.contactCryptoId
            case .unknown(remoteCryptoId: let remoteCryptoId):
                return remoteCryptoId
            }
        case .callerOfIncomingCall(contactObjectID: _, contactIdentifier: let contactIdentifier, contactDeviceUID: _):
            return contactIdentifier.contactCryptoId
        case .calleeOfOutgoingCall(contactObjectID: _, contactIdentifier: let contactIdentifier, contactDeviceUID: _):
            return contactIdentifier.contactCryptoId
        }
    }

    private init(kind: Kind, peerConnectionHolder: OlvidCallParticipantPeerConnectionHolder, cryptoId: ObvCryptoId, displayName: String, isOneToOne: Bool, shouldISendTheOfferToCallParticipant: Bool) {
        self.kind = kind
        self.peerConnectionHolder = peerConnectionHolder
        self.displayName = displayName
        self.shouldISendTheOfferToCallParticipant = shouldISendTheOfferToCallParticipant
        self.isOneToOne = isOneToOne
    }
    

    @MainActor
    static func createCallerOfIncomingCall(callerDeviceIdentifier: ObvContactDeviceIdentifier, startCallMessage: StartCallMessageJSON, shouldISendTheOfferToCallParticipant: Bool, rtcPeerConnectionQueue: OperationQueue, factory: ObvPeerConnectionFactory) async throws -> OlvidCallParticipant {
        guard let persistedContact = try PersistedObvContactIdentity.get(persisted: callerDeviceIdentifier.contactIdentifier, whereOneToOneStatusIs: .any, within: ObvStack.shared.viewContext) else {
            throw ObvError.couldNotFindContact
        }
        let peerConnectionHolder = OlvidCallParticipantPeerConnectionHolder(
            startCallMessage: startCallMessage,
            shouldISendTheOfferToCallParticipant: shouldISendTheOfferToCallParticipant,
            rtcPeerConnectionQueue: rtcPeerConnectionQueue,
            factory: factory)
        let caller = OlvidCallParticipant(
            kind: .callerOfIncomingCall(contactObjectID: persistedContact.typedObjectID, contactIdentifier: callerDeviceIdentifier.contactIdentifier, contactDeviceUID: callerDeviceIdentifier.deviceUID),
            peerConnectionHolder: peerConnectionHolder,
            cryptoId: persistedContact.cryptoId, 
            displayName: persistedContact.customOrNormalDisplayName,
            isOneToOne: persistedContact.isOneToOne,
            shouldISendTheOfferToCallParticipant: shouldISendTheOfferToCallParticipant)
        assert(caller.kind.contactDeviceUID != nil)
        await caller.callParticipantDestinationDeviceStatusManager.destinationDeviceIsKnownOrWillNotBeKnown() // The device the caller is known
        return caller
    }
    
    
    /// After calling this method, we should immediately call ``setDelegate(to:)``.
    @MainActor
    static func createCalleeOfOutgoingCall(calleeId: ObvContactIdentifier, shouldISendTheOfferToCallParticipant: Bool, rtcPeerConnectionQueue: OperationQueue, factory: ObvPeerConnectionFactory) async throws -> OlvidCallParticipant {
        guard let persistedContact = try PersistedObvContactIdentity.get(persisted: calleeId, whereOneToOneStatusIs: .any, within: ObvStack.shared.viewContext) else {
            throw ObvError.couldNotFindContact
        }
        let gatheringPolicy: OlvidCallGatheringPolicy = persistedContact.supportsCapability(.webrtcContinuousICE) ? .gatherContinually : .gatherOnce
        let peerConnectionHolder = OlvidCallParticipantPeerConnectionHolder(
            gatheringPolicy: gatheringPolicy,
            shouldISendTheOfferToCallParticipant: shouldISendTheOfferToCallParticipant,
            rtcPeerConnectionQueue: rtcPeerConnectionQueue,
            factory: factory)
        let callee = OlvidCallParticipant(
            kind: .calleeOfOutgoingCall(contactObjectID: persistedContact.typedObjectID, contactIdentifier: calleeId, contactDeviceUID: nil),
            peerConnectionHolder: peerConnectionHolder,
            cryptoId: persistedContact.cryptoId, 
            displayName: persistedContact.customOrNormalDisplayName, 
            isOneToOne: persistedContact.isOneToOne,
            shouldISendTheOfferToCallParticipant: shouldISendTheOfferToCallParticipant)
        await callee.peerConnectionHolder.setDelegate(to: callee)
        // We cannot call callee.callParticipantDestinationDeviceStatusManager.destinationDeviceIsKnownOrWillNotBeKnown(). We wait until the receiption of the answerCall message
        // to determine the remote device of the callee.
        return callee
    }
    
    
    @MainActor
    static func createOtherParticipantOfIncomingCall(ownedCryptoId: ObvCryptoId, remoteCryptoId: ObvCryptoId, gatheringPolicy: OlvidCallGatheringPolicy, displayName: String, shouldISendTheOfferToCallParticipant: Bool, rtcPeerConnectionQueue: OperationQueue, factory: ObvPeerConnectionFactory) async throws -> OlvidCallParticipant {
        let knownOrUnknown: KnownOrUnknown
        let usedDisplayName: String
        let isOneToOne: Bool
        if let persistedContact = try PersistedObvContactIdentity.get(contactCryptoId: remoteCryptoId, ownedIdentityCryptoId: ownedCryptoId, whereOneToOneStatusIs: .any, within: ObvStack.shared.viewContext) {
            knownOrUnknown = .known(contactObjectID: persistedContact.typedObjectID, contactIdentifier: try persistedContact.contactIdentifier, contactDeviceUID: nil)
            usedDisplayName = persistedContact.customOrNormalDisplayName
            isOneToOne = persistedContact.isOneToOne
        } else {
            knownOrUnknown = .unknown(remoteCryptoId: remoteCryptoId)
            usedDisplayName = displayName
            isOneToOne = false
        }
        let peerConnectionHolder = OlvidCallParticipantPeerConnectionHolder(
            gatheringPolicy: gatheringPolicy,
            shouldISendTheOfferToCallParticipant: shouldISendTheOfferToCallParticipant,
            rtcPeerConnectionQueue: rtcPeerConnectionQueue,
            factory: factory)
        let otherParticipant = OlvidCallParticipant(
            kind: .otherParticipantOfIncomingCall(knownOrUnknown: knownOrUnknown),
            peerConnectionHolder: peerConnectionHolder,
            cryptoId: remoteCryptoId,
            displayName: usedDisplayName, 
            isOneToOne: isOneToOne,
            shouldISendTheOfferToCallParticipant: shouldISendTheOfferToCallParticipant)
        await peerConnectionHolder.setDelegate(to: otherParticipant)
        switch knownOrUnknown {
        case .known:
            break
            // We cannot call otherParticipant.callParticipantDestinationDeviceStatusManager.destinationDeviceIsKnownOrWillNotBeKnown(). We wait until the reception of the answerCall message
            // to determine the remote device of the other participant.
        case .unknown:
            // The device of this other participant will never be known
            await otherParticipant.callParticipantDestinationDeviceStatusManager.destinationDeviceIsKnownOrWillNotBeKnown()
        }
        return otherParticipant
    }
    
    
    @MainActor
    func setDelegate(to delegate: OlvidCallParticipantDelegate) async {
        self.delegate = delegate
    }

    
    func userWantsToChatWithThisParticipant(ownedCryptoId: ObvCryptoId) async throws {
        
        let contactCryptoId = self.cryptoId
        
        ObvStack.shared.performBackgroundTask { context in
            do {
                guard let contact = try PersistedObvContactIdentity.get(contactCryptoId: contactCryptoId, ownedIdentityCryptoId: ownedCryptoId, whereOneToOneStatusIs: .oneToOne, within: context),
                      let oneToOneDiscussion = contact.oneToOneDiscussion else { return }
                let discussionPermanentID = oneToOneDiscussion.discussionPermanentID
                let deepLink = ObvDeepLink.singleDiscussion(ownedCryptoId: ownedCryptoId, objectPermanentID: discussionPermanentID)
                ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                    .postOnDispatchQueue()
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
        
    }
    
}

// MARK: - Set the device of the participant

extension OlvidCallParticipant {
    
    func setDeviceUID(_ newContactDeviceUID: UID) {
        defer {
            Task { await self.callParticipantDestinationDeviceStatusManager.destinationDeviceIsKnownOrWillNotBeKnown() }
        }
        switch kind {
        case .otherParticipantOfIncomingCall(knownOrUnknown: let knownOrUnknown):
            switch knownOrUnknown {
            case .known(contactObjectID: let contactObjectID, contactIdentifier: let contactIdentifier, contactDeviceUID: let contactDeviceUID):
                guard contactDeviceUID == nil || contactDeviceUID == newContactDeviceUID else { assertionFailure(); return }
                self.kind = .otherParticipantOfIncomingCall(knownOrUnknown: .known(contactObjectID: contactObjectID, contactIdentifier: contactIdentifier, contactDeviceUID: newContactDeviceUID))
            case .unknown(remoteCryptoId: _):
                assertionFailure("Trying to set a contact device on an unknown participant. This should be investigated.")
                return
            }
        case .callerOfIncomingCall(contactObjectID: let contactObjectID, contactIdentifier: let contactIdentifier, contactDeviceUID: let contactDeviceUID):
            guard contactDeviceUID == nil || contactDeviceUID == newContactDeviceUID else { assertionFailure(); return }
            self.kind = .callerOfIncomingCall(contactObjectID: contactObjectID, contactIdentifier: contactIdentifier, contactDeviceUID: newContactDeviceUID)
        case .calleeOfOutgoingCall(contactObjectID: let contactObjectID, contactIdentifier: let contactIdentifier, contactDeviceUID: let contactDeviceUID):
            guard contactDeviceUID == nil || contactDeviceUID == newContactDeviceUID else { assertionFailure(); return }
            self.kind = .calleeOfOutgoingCall(contactObjectID: contactObjectID, contactIdentifier: contactIdentifier, contactDeviceUID: newContactDeviceUID)
        }
    }
    
    func destinationDeviceIsKnownOrWillNotBeKnown() async {
        await self.callParticipantDestinationDeviceStatusManager.destinationDeviceIsKnownOrWillNotBeKnown()
    }
    
}

// MARK: - Video

extension OlvidCallParticipant {
    
    func setLocalVideoTrack(isEnabled: Bool) async throws {
        
        guard self.supportsVideo else { return }
        
        os_log("☎️🎥 Will set isEnable=%{public}@ for a video track", log: Self.log, type: .info, isEnabled.description)

        try await peerConnectionHolder.setLocalVideoTrack(isEnabled: isEnabled)

        os_log("☎️🎥 Will send a VideoCameraEnabledJSON", log: Self.log, type: .info, isEnabled.description)

        await sendVideoEnabledJSON(isEnabled: isEnabled, forScreenCast: false)
        
    }

}


// MARK: - Audio

extension OlvidCallParticipant {
    
    var selfIsMuted: Bool {
        get async throws {
            try await !peerConnectionHolder.isAudioTrackEnabled
        }
    }

    func setMuteSelf(muted: Bool) async throws {
        try await peerConnectionHolder.setAudioTrack(isEnabled: !muted)
    }

    
}


// MARK: - Implementing OlvidCallParticipantPeerConnectionHolderDelegate

extension OlvidCallParticipant: OlvidCallParticipantPeerConnectionHolderDelegate {
    
    @MainActor
    func peerConnectionStateDidChange(newState: RTCIceConnectionState) async {
        switch newState {
        case .new: return
        case .checking:
            delegate?.connectionIsChecking(for: self)
        case .connected:
            let oldState = self.state
            setPeerState(to: .connected)
            await delegate?.connectionIsConnected(for: self, oldParticipantState: oldState)
        case .failed, .disconnected:
            await reconnectAfterConnectionLoss()
        case .closed:
            await delegate?.connectionWasClosed(for: self)
        case .completed, .count:
            return
        @unknown default:
            assertionFailure()
        }
    }
    
    
    @MainActor
    func dataChannel(of peerConnectionHolder: OlvidCallParticipantPeerConnectionHolder, didReceiveMessage message: WebRTCDataChannelMessageJSON) async {
        do {
            switch message.messageType {
                
            case .muted:
                let mutedMessage = try MutedMessageJSON.jsonDecode(serializedMessage: message.serializedMessage)
                os_log("☎️ MutedMessageJSON received on data channel", log: Self.log, type: .info)
                await processMutedMessageJSON(message: mutedMessage)
                
            case .updateParticipant:
                let updateParticipantsMessage = try UpdateParticipantsMessageJSON.jsonDecode(serializedMessage: message.serializedMessage)
                os_log("☎️ UpdateParticipantsMessageJSON received on data channel", log: Self.log, type: .info)
                try await processUpdateParticipantsMessageJSON(message: updateParticipantsMessage)
                
            case .relayMessage:
                let relayMessage = try RelayMessageJSON.jsonDecode(serializedMessage: message.serializedMessage)
                os_log("☎️ RelayMessageJSON received on data channel", log: Self.log, type: .info)
                await processRelayMessageJSON(message: relayMessage)
                
            case .relayedMessage:
                let relayedMessage = try RelayedMessageJSON.jsonDecode(serializedMessage: message.serializedMessage)
                os_log("☎️ RelayedMessageJSON received on data channel", log: Self.log, type: .info)
                await processRelayedMessageJSON(message: relayedMessage)
                
            case .hangedUpMessage:
                os_log("☎️ HangedUpDataChannelMessageJSON received on data channel", log: Self.log, type: .info)
                // We want hangedUpMessage received on the data channel and on the WebSocket to receive the same treatment.
                // So we don't process the this message here, and report to our delegate
                let messagePayload = message.serializedMessage
                await delegate?.receivedHangedUpMessage(from: self, messagePayload: messagePayload)
                
            case .videoSupported:
                let videoSupportedMessage = try VideoSupportedJSON.jsonDecode(serializedMessage: message.serializedMessage)
                os_log("☎️ videoSupported received on data channel", log: Self.log, type: .info)
                try await processVideoSupportedJSON(message: videoSupportedMessage)
                
            case .videoCameraEnabled:
                let videoCameraEnabledMessage = try VideoCameraEnabledJSON.jsonDecode(serializedMessage: message.serializedMessage)
                os_log("☎️ videoCameraEnabledMessage received on data channel", log: Self.log, type: .info)
                self.remoteCameraVideoTrackIsEnabled = videoCameraEnabledMessage.isVideoCameraEnabled
                await delegate?.reevalutateScreenDimming()

            case .videoScreencastEnabled:
                let videoScreencastEnabledMessage = try VideoScreencastEnabledJSON.jsonDecode(serializedMessage: message.serializedMessage)
                os_log("☎️ videoScreencastEnabledMessage received on data channel", log: Self.log, type: .info)
                self.remoteScreenCastVideoTrackIsEnabled = videoScreencastEnabledMessage.isVideoScreencastEnabled
                await delegate?.reevalutateScreenDimming()

            }
        } catch {
            os_log("☎️ Failed to parse or process WebRTCDataChannelMessageJSON: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }
    
    
    private func processRelayedMessageJSON(message: RelayedMessageJSON) async {

        guard isCallerOfIncomingCall else { assertionFailure(); return }

        do {
            let fromId = try ObvCryptoId(identity: message.from)
            guard let messageType = WebRTCMessageJSON.MessageType(rawValue: message.relayedMessageType) else { assertionFailure(); throw ObvError.couldNotParseWebRTCMessageJSONMessageType }
            let messagePayload = message.serializedMessagePayload
            await delegate?.receivedRelayedMessage(from: fromId, messageType: messageType, messagePayload: messagePayload)
        } catch {
            os_log("☎️ Could not read received RelayedMessageJSON: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }
    }
    
    
    private func processRelayMessageJSON(message: RelayMessageJSON) async {
        guard !isCallerOfIncomingCall else { assertionFailure(); return }

        do {
            let fromId = self.cryptoId
            let toId = try ObvCryptoId(identity: message.to)
            guard let messageType = WebRTCMessageJSON.MessageType(rawValue: message.relayedMessageType) else { assertionFailure(); throw ObvError.couldNotParseWebRTCMessageJSONMessageType }
            let messagePayload = message.serializedMessagePayload
            await delegate?.relay(from: fromId, to: toId, messageType: messageType, messagePayload: messagePayload)
        } catch {
            os_log("☎️ Could not read received RelayMessageJSON: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }
    }

    
    private func processUpdateParticipantsMessageJSON(message: UpdateParticipantsMessageJSON) async throws {
       // Check that the participant list is indeed sent by the caller (and thus, not by a "simple" participant).
        guard isCallerOfIncomingCall else {
            assertionFailure()
            return
        }
        try await delegate?.updateParticipants(with: message.callParticipants)
    }
    
    
    private func processVideoSupportedJSON(message: VideoSupportedJSON) async throws {
        guard supportsVideo != message.isVideoSupported else { return }
        supportsVideo = message.isVideoSupported
        if supportsVideo && shouldISendTheOfferToCallParticipant {
            try await peerConnectionHolder.createAndAddLocalVideoAndScreencastTracks()
        }
    }
    
    
    /// Dispatching on the main actor as we are setting a published variable, used at the UI level
    @MainActor
    private func processMutedMessageJSON(message: MutedMessageJSON) async {
        guard contactIsMuted != message.muted else { return }
        contactIsMuted = message.muted
        await delegate?.participantWasUpdated(callParticipant: self, updateKind: .contactMuted)
    }

    
    func dataChannel(of peerConnectionHolder: OlvidCallParticipantPeerConnectionHolder, didChangeState state: RTCDataChannelState) async {
        os_log("☎️ Data channel changed state. New state is %{public}@", log: Self.log, type: .info, state.description)
        switch state {
        case .open:
            await delegate?.dataChannelIsOpened(for: self)
            await sendMutedMessageJSON()
            await sendVideoSupportedMessageJSON()
        case .connecting, .closing, .closed:
            break
        @unknown default:
            assertionFailure()
        }
    }
    
    
    func sendVideoSupportedMessageJSON() async {
        let message: WebRTCDataChannelMessageJSON
        do {
            message = try VideoSupportedJSON(isVideoSupported: true).embedInWebRTCDataChannelMessageJSON()
        } catch {
            os_log("☎️ Could not create VideoSupportedJSON: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }
        do {
            try await peerConnectionHolder.sendDataChannelMessage(message)
        } catch {
            os_log("☎️ Could not send WebRTCDataChannelMessageJSON data channel message: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            return
        }
    }
    
    
    /// This message is sent to the participant when the local user activates her local video stream (screencast or camera). Thanks to this information, the participant will decide to activate a remote video track.
    func sendVideoEnabledJSON(isEnabled: Bool, forScreenCast: Bool) async {
        assert(!forScreenCast, "At this time, this implementation does not support sending a screencast")
        let message: WebRTCDataChannelMessageJSON
        do {
            if forScreenCast {
                message = try VideoScreencastEnabledJSON(isVideoScreencastEnabled: isEnabled).embedInWebRTCDataChannelMessageJSON()
            } else {
                message = try VideoCameraEnabledJSON(isVideoCameraEnabled: isEnabled).embedInWebRTCDataChannelMessageJSON()
            }
        } catch {
            os_log("☎️ Could not create WebRTCDataChannelMessageJSON: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }
        do {
            try await peerConnectionHolder.sendDataChannelMessage(message)
        } catch {
            os_log("☎️ Could not send WebRTCDataChannelMessageJSON data channel message: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            return
        }
    }

    
    func sendMutedMessageJSON() async {
        let message: WebRTCDataChannelMessageJSON
        do {
            message = try await MutedMessageJSON(muted: selfIsMuted).embedInWebRTCDataChannelMessageJSON()
        } catch {
            os_log("☎️ Could not create MutedMessageJSON: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }
        do {
            try await peerConnectionHolder.sendDataChannelMessage(message)
        } catch {
            os_log("☎️ Could not send WebRTCDataChannelMessageJSON data channel message: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            return
        }
    }


    func sendNewIceCandidateMessage(candidate: RTCIceCandidate) async throws {
        guard !state.isFinalState else { return }
        guard let delegate else { return }
        Self.logger.info("☎️ Will await until destination device of call participant is either known, or will never be known for candidate \(candidate.debugDescription)")
        await self.callParticipantDestinationDeviceStatusManager.awaitUntilDestinationDeviceIsKnownOrWillNotBeKnown()
        Self.logger.info("☎️ Did await until destination device of call participant is either known, or will never be known for candidate \(candidate.debugDescription)")
        try await delegate.sendNewIceCandidateMessage(to: self, iceCandidate: candidate)
    }
    
    
    func sendRemoveIceCandidatesMessages(candidates: [RTCIceCandidate]) async throws {
        guard let delegate else { assertionFailure(); return }
        try await delegate.sendRemoveIceCandidatesMessages(to: self, candidates: candidates)
    }
    
    
    /// Sends the local description to the call participant corresponding to `self`
    @MainActor
    func sendLocalDescription(sessionDescription: RTCSessionDescription, reconnectCounter: Int, peerReconnectCounterToOverride: Int) async {

        os_log("☎️ Calling sendLocalDescription for a participant", log: Self.log, type: .info)
        
        guard let delegate else {
            // This typically happen when the call has been deallocated as it reached a final state
            return
        }
        
        do {
            switch self.state {
            case .initial:
                if isCallOutgoing {
                    guard let turnCredentials else { assertionFailure(); throw ObvError.turnCredentialsRequired }
                    try await delegate.sendStartCallMessage(to: self, sessionDescription: sessionDescription, turnCredentials: turnCredentials)
                    setPeerState(to: .startCallMessageSent)
                } else {
                    if self.isCallerOfIncomingCall {
                        try await delegate.sendAnswerCallMessage(to: self, sessionDescription: sessionDescription)
                        setPeerState(to: .connectingToPeer)
                    } else {
                        if shouldISendTheOfferToCallParticipant {
                            try await delegate.sendNewParticipantOfferMessage(to: self, sessionDescription: sessionDescription)
                            setPeerState(to: .startCallMessageSent)
                        } else {
                            try await delegate.sendNewParticipantAnswerMessage(to: self, sessionDescription: sessionDescription)
                            setPeerState(to: .connectingToPeer)
                        }
                    }
                }
            case .connected, .reconnecting:
                os_log("☎️ Sending peer a restart SDP", log: Self.log, type: .info)
                try await delegate.sendReconnectCallMessage(to: self, sessionDescription: sessionDescription, reconnectCounter: reconnectCounter, peerReconnectCounterToOverride: peerReconnectCounterToOverride)
            case .startCallMessageSent, .ringing, .busy, .callRejected, .connectingToPeer, .hangedUp, .kicked, .failed, .connectionTimeout:
                os_log("☎️ Not sending peer the restart SDP as we are in state %{public}@", log: Self.log, type: .info, self.state.debugDescription)
                break // Do nothing
            }
        } catch {
            setPeerState(to: .failed)
            assertionFailure()
            return
        }

    }
    
    
    @MainActor
    func peerConnectionHolder(_ peerConnectionHolder: OlvidCallParticipantPeerConnectionHolder, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) async {
        
        guard let newRemoteVideoTrack = rtpReceiver.track as? RTCVideoTrack else {
            return
        }
        
        if mediaStreams.contains(where: { $0.streamId == ObvMessengerConstants.StreamId.video }) {
            self.remoteCameraVideoTrack = newRemoteVideoTrack
        } else if mediaStreams.contains(where: { $0.streamId == ObvMessengerConstants.StreamId.screencast }) {
            self.remoteScreenCastVideoTrack = newRemoteVideoTrack
        } else {
            assertionFailure()
        }
        
    }
    
    
    func peerConnectionHolder(_ peerConnectionHolder: OlvidCallParticipantPeerConnectionHolder, didAddLocalVideoTrack videoTrack: RTCVideoTrack) async {
        assert(self.supportsVideo, "We shouldn't have added a local video track since this participant does not appear to support video calls")
        Task { await delegate?.localVideoTrackWasAdded(for: self, videoTrack: videoTrack) }
    }
    
}


// MARK: - Turn credentials

extension OlvidCallParticipant {
    
    /// This method is two situations:
    /// - During an outgoing call, when setting the turn credential of a call participant.
    /// - During a multi-users incoming call, when we are in charge of sending the offer to another recipient (who isn't the caller).
    func setTurnCredentialsAndCreateUnderlyingPeerConnection(turnCredentials: TurnCredentials) async throws {
        assert(self.isOtherParticipantOfIncomingCall || self.isCalleeOfOutgoingCall)
        self.turnCredentials = turnCredentials
        try await self.peerConnectionHolder.setTurnCredentialsAndCreateUnderlyingPeerConnectionIfRequired(turnCredentials)
    }
    
}


// MARK: - Methods called when this participant is the caller of an incoming call

extension OlvidCallParticipant {
    
    func localUserAcceptedIncomingCallFromThisCallParticipant() async throws {
        assert(self.isCallerOfIncomingCall)
        assert(!self.isCallOutgoing)
        try await peerConnectionHolder.createPeerConnectionIfRequiredAfterAcceptingAnIncomingCall(delegate: self)
    }
    
    
    /// Called by ``OlvidCall`` when the local user is the caller, and decided to kick this participant.
    @MainActor
    func callerKicksThisParticipant() async {
        await peerConnectionHolder.close()
        setPeerState(to: .kicked)
    }
    
}


// MARK: - Methods for outgoing calls

extension OlvidCallParticipant {
    
    /// Called by the associated `OlvidCall` when we received a message indicating that this participant rejected our outgoing call.
    @MainActor
    func rejectedOutgoingCall() async {
        guard [.startCallMessageSent, .ringing].contains(self.state) else {
            // This could exceptionally happen if the participant responds to the call on any one of their devices,
            // but manually hangs up from another owned device before said device is notified that the call was answered to.
            return
        }
        setPeerState(to: .callRejected)
    }
 

    /// Called by the associated `OlvidCall` when we received a message indicating that this participant is ringing.
    @MainActor
    func isRinging() async {
        guard state == .startCallMessageSent else { return }
        setPeerState(to: .ringing)
    }
    
}


// MARK: - Methods for processing participants actions

extension OlvidCallParticipant {
    
    @MainActor
    func didHangUp() async {
        setPeerState(to: .hangedUp)
    }
    
    
    @MainActor
    func isBusy() async {
        guard state == .startCallMessageSent else { assertionFailure(); return }
        setPeerState(to: .busy)
    }
    
}



// MARK: - Distinguishing between known (i.e., contacts) and unknown participants

extension OlvidCallParticipant {
    
    enum KnownOrUnknown {
        case known(contactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, contactIdentifier: ObvContactIdentifier, contactDeviceUID: UID?)
        case unknown(remoteCryptoId: ObvCryptoId)
    }

    var knownOrUnknown: KnownOrUnknown {
        switch self.kind {
        case .otherParticipantOfIncomingCall(knownOrUnknown: let knownOrUnknown):
            return knownOrUnknown
        case .callerOfIncomingCall(contactObjectID: let contactObjectID, contactIdentifier: let contactIdentifier, contactDeviceUID: let contactDeviceUID),
                .calleeOfOutgoingCall(contactObjectID: let contactObjectID, contactIdentifier: let contactIdentifier, contactDeviceUID: let contactDeviceUID):
            return .known(contactObjectID: contactObjectID, contactIdentifier: contactIdentifier, contactDeviceUID: contactDeviceUID)
        }
    }
    
}


// MARK: - Participant kind and data extracted from its kind

extension OlvidCallParticipant {
    
    enum Kind {
        
        case otherParticipantOfIncomingCall(knownOrUnknown: KnownOrUnknown)
        case callerOfIncomingCall(contactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, contactIdentifier: ObvContactIdentifier, contactDeviceUID: UID?)
        case calleeOfOutgoingCall(contactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, contactIdentifier: ObvContactIdentifier, contactDeviceUID: UID?)
        
        var contactDeviceUID: UID? {
            switch self {
            case .otherParticipantOfIncomingCall(knownOrUnknown: let knownOrUnknown):
                switch knownOrUnknown {
                case .known(contactObjectID: _, contactIdentifier: _, contactDeviceUID: let contactDeviceUID):
                    return contactDeviceUID
                case .unknown:
                    return nil
                }
            case .callerOfIncomingCall(contactObjectID: _, contactIdentifier: _, contactDeviceUID: let contactDeviceUID),
                    .calleeOfOutgoingCall(contactObjectID: _, contactIdentifier: _, contactDeviceUID: let contactDeviceUID):
                return contactDeviceUID
            }
        }
    }
    
    
    var isCallerOfIncomingCall: Bool {
        switch kind {
        case .callerOfIncomingCall:
            return true
        default:
            return false
        }
    }
    
    
    private var isOtherParticipantOfIncomingCall: Bool {
        switch kind {
        case .otherParticipantOfIncomingCall:
            return true
        default:
            return false
        }
    }
    
    
    private var isCalleeOfOutgoingCall: Bool {
        switch kind {
        case .calleeOfOutgoingCall:
            return true
        default:
            return false
        }
    }

    
    private var isCallOutgoing: Bool {
        switch kind {
        case .calleeOfOutgoingCall:
            return true
        case .callerOfIncomingCall, .otherParticipantOfIncomingCall:
            return false
        }
    }
    
}


// MARK: - Reconnecting

extension OlvidCallParticipant {
    
    @MainActor
    func reconnectAfterConnectionLoss() async {
        guard [State.connectingToPeer, .connected, .reconnecting].contains(self.state) else { return }
        setPeerState(to: .connectionTimeout)
        setPeerState(to: .reconnecting)
    }
    
}


// MARK: - Peer connection

extension OlvidCallParticipant {
    
    func closeConnection() async throws {
        os_log("☎️🛑 Closing peer connection", log: Self.log, type: .info)
        await peerConnectionHolder.close()
    }
    
    var gatheringPolicy: OlvidCallGatheringPolicy {
        get async {
            await peerConnectionHolder.gatheringPolicy
        }
    }

    
    func setRemoteDescription(sessionDescription: RTCSessionDescription) async throws {
        os_log("☎️ Will call setRemoteDescription on the peerConnectionHolder", log: Self.log, type: .info)
        try await peerConnectionHolder.setRemoteDescription(sessionDescription)
    }
    
    
    func handleReceivedRestartSdp(sessionDescription: RTCSessionDescription, reconnectCounter: Int, peerReconnectCounterToOverride: Int) async throws {
        os_log("☎️ Will call handleReceivedRestartSdp on the peerConnectionHolder", log: Self.log, type: .info)
        try await peerConnectionHolder.handleReceivedRestartSdp(
            sessionDescription: sessionDescription,
            reconnectCounter: reconnectCounter,
            peerReconnectCounterToOverride: peerReconnectCounterToOverride, 
            shouldISendTheOfferToCallParticipant: shouldISendTheOfferToCallParticipant)
    }

    
    /// Called when we receive a `NewParticipantAnswerMessageJSON` from this participant and when we determined that we must set a remote description
    func processNewParticipantAnswerMessageJSON(sessionDescription: RTCSessionDescription) async throws {
        guard self.isCalleeOfOutgoingCall || self.isOtherParticipantOfIncomingCall else { assertionFailure(); return }
        os_log("☎️ Will call setRemoteDescription on the peerConnectionHolder", log: Self.log, type: .info)
        try await peerConnectionHolder.setRemoteDescription(sessionDescription)
    }
    
}


// MARK: - Participant state

extension OlvidCallParticipant {
    
    private func setPeerState(to newState: State) {
        
        // We want to make sure we are on the main thread since we are modifying a published value
        assert(Thread.isMainThread)
        
        guard newState != self.state else { return }
        
        os_log("☎️ WebRTCCall participant will change state: %{public}@ --> %{public}@", log: Self.log, type: .info, self.state.debugDescription, newState.debugDescription)
        self.state = newState
        
        if self.state.isFinalState {
            Task {
                try await closeConnection()
            }
        }

        Task {
            await delegate?.participantWasUpdated(callParticipant: self, updateKind: .state(newState: state))
        }
    }

    
    enum State: Hashable, CustomDebugStringConvertible {
        case initial
        // States for the caller only (during this time, the recipient stays in the initial state)
        case startCallMessageSent
        case ringing
        case busy
        case callRejected
        // States common to the caller and the recipient
        case connectingToPeer
        case connected
        case reconnecting
        case connectionTimeout
        case hangedUp
        case kicked
        case failed

        var debugDescription: String {
            switch self {
            case .initial: return "initial"
            case .startCallMessageSent: return "startCallMessageSent"
            case .busy: return "busy"
            case .reconnecting: return "reconnecting"
            case .connectionTimeout: return "connectionTimeout"
            case .ringing: return "ringing"
            case .callRejected: return "callRejected"
            case .connectingToPeer: return "connectingToPeer"
            case .connected: return "connected"
            case .hangedUp: return "hangedUp"
            case .kicked: return "kicked"
            case .failed: return "failed"
            }
        }

        var isFinalState: Bool {
            switch self {
            case .callRejected, .hangedUp, .kicked, .failed: return true
            case .initial, .startCallMessageSent, .ringing, .busy, .connectingToPeer, .connected, .reconnecting, .connectionTimeout: return false
            }
        }

        var localizedString: String {
            switch self {
            case .initial: return NSLocalizedString("CALL_STATE_NEW", comment: "")
            case .startCallMessageSent: return NSLocalizedString("CALL_STATE_INCOMING_CALL_MESSAGE_WAS_POSTED", comment: "")
            case .ringing: return NSLocalizedString("CALL_STATE_RINGING", comment: "")
            case .busy: return NSLocalizedString("CALL_STATE_BUSY", comment: "")
            case .callRejected: return NSLocalizedString("CALL_STATE_CALL_REJECTED", comment: "")
            case .connectingToPeer: return NSLocalizedString("CALL_STATE_CONNECTING_TO_PEER", comment: "")
            case .connected: return NSLocalizedString("SECURE_CALL_IN_PROGRESS", comment: "")
            case .reconnecting: return NSLocalizedString("CALL_STATE_RECONNECTING", comment: "")
            case .connectionTimeout: return NSLocalizedString("CALL_STATE_CONNECTION_TIMEOUT", comment: "")
            case .hangedUp: return NSLocalizedString("CALL_STATE_HANGED_UP", comment: "")
            case .kicked: return NSLocalizedString("CALL_STATE_KICKED", comment: "")
            case .failed: return NSLocalizedString("FAILED", comment: "")
            }
        }

    }

}


// MARK: - Update kind

extension OlvidCallParticipant {
    
    enum UpdateKind {
        case state(newState: State)
        case contactID
        case contactMuted
    }
    
}


// MARK: - Offers

extension OlvidCallParticipant {
    
    /// Update a recipient in a multi-user incoming call where we also are a recipient (not the caller), and not in charge of the offer.
    func updateRecipient(newParticipantOfferMessage: NewParticipantOfferMessageJSON, turnCredentials: TurnCredentials) async throws {
        assert(!self.isCallerOfIncomingCall)
        self.turnCredentials = turnCredentials
        try await self.peerConnectionHolder.setRemoteDescriptionAndTurnCredentialsThenCreateTheUnderlyingPeerConnectionIfRequired(newParticipantOfferMessage: newParticipantOfferMessage, turnCredentials: turnCredentials)
    }
    
}


// MARK: - Sending WebRTC messages

extension OlvidCallParticipant {
    
    func sendDataChannelMessage(_ message: WebRTCDataChannelMessageJSON) async throws {
        try await peerConnectionHolder.sendDataChannelMessage(message)
    }
        
}


// MARK: - Informations for call reports

extension OlvidCallParticipant {
    
    var info: OlvidCallParticipantInfo? {
        switch knownOrUnknown {
        case .known(contactObjectID: let contactObjectID, contactIdentifier: let contactIdentifier, contactDeviceUID: _):
            return .init(contactObjectID: contactObjectID,
                         contactIdentifier: contactIdentifier,
                         isCaller: isCallerOfIncomingCall)
        case .unknown:
            return nil
        }
    }

}


// MARK: ICE candidates

extension OlvidCallParticipant {
    
    func processIceCandidatesJSON(message: IceCandidateJSON) async throws {
        try await peerConnectionHolder.addIceCandidate(iceCandidate: message.iceCandidate)
    }


    func processRemoveIceCandidatesMessageJSON(message: RemoveIceCandidatesMessageJSON) async {
        await peerConnectionHolder.removeIceCandidates(iceCandidates: message.iceCandidates)
    }

}


// MARK: - Errors

extension OlvidCallParticipant {
    
    enum ObvError: Error, CustomDebugStringConvertible {
        
        case turnCredentialsRequired
        case couldNotParseWebRTCMessageJSONMessageType
        case couldNotFindContact
                
        var debugDescription: String {
            switch self {
            case .turnCredentialsRequired: return "Turn credentials are required"
            case .couldNotParseWebRTCMessageJSONMessageType: return "Could not parse WebRTCMessageJSON.MessageType"
            case .couldNotFindContact: return "Could not find contact"
            }
        }

    }
    
}


// MARK: - Helpers

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


// MARK: - ICE candidate debouncer

private actor CallParticipantDestinationDeviceStatusManager {
    
    private enum DestinationDeviceStatus {
        case toBeDetermined
        case kwnownOrWillNotBeKnown
    }

    private var status: DestinationDeviceStatus = .toBeDetermined
    
    private var pendingContinuations: [CheckedContinuation<Void, Never>] = []
    
    func awaitUntilDestinationDeviceIsKnownOrWillNotBeKnown() async {
        switch status {
        case .kwnownOrWillNotBeKnown:
            return
        case .toBeDetermined:
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                switch status {
                case .kwnownOrWillNotBeKnown:
                    return continuation.resume()
                case .toBeDetermined:
                    pendingContinuations.insert(continuation, at: 0)
                }
            }
        }
    }

    
    func destinationDeviceIsKnownOrWillNotBeKnown() {
        self.status = .kwnownOrWillNotBeKnown
        while let continuation = pendingContinuations.popLast() {
            continuation.resume()
        }
    }
    
}
