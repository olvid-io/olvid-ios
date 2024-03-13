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
import WebRTC
import os.log
import OlvidUtils


/// An instance of this class is a wrapper around a WebRTC `RTCPeerConnection` object. It ensures all the calls made to this wrapped object are made on the same internal serial queue.
final class ObvPeerConnection: NSObject {


    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: ObvPeerConnection.self))
    
    private let factory: ObvPeerConnectionFactory
    private let peerConnection: RTCPeerConnection
    private var dataChannel: RTCDataChannel?
    private var localAudioTrack: RTCAudioTrack?
    private var localVideoTrack: RTCVideoTrack?
    private var localScreencastTrack: RTCVideoTrack?

    private(set) var connectionState: RTCPeerConnectionState = .new
    private(set) var signalingState: RTCSignalingState = .stable
    private(set) var iceConnectionState: RTCIceConnectionState = .new
    
    private weak var delegate: ObvPeerConnectionDelegate?
    private weak var dataChannelDelegate: ObvDataChannelDelegate?

    
    init(with configuration: RTCConfiguration, constraints: RTCMediaConstraints, factory: ObvPeerConnectionFactory, delegate: ObvPeerConnectionDelegate) async throws {
        self.delegate = delegate
        self.peerConnection = try await factory.createPeerConnection(with: configuration, constraints: constraints)
        self.factory = factory
        super.init()
        self.peerConnection.delegate = self
    }


    func close() async {
        return await withCheckedContinuation { cont in
            factory.webRTCQueue.async {
                os_log("☎️🔌 peerConnection.close()", log: Self.log, type: .info)
                self.peerConnection.close()
                cont.resume()
            }
        }
    }

    
    var localDescription: RTCSessionDescription? {
        get async {
            return await withCheckedContinuation { cont in
                factory.webRTCQueue.async {
                    cont.resume(returning: self.peerConnection.localDescription)
                }
            }
        }

    }


    func offer(for mediaConstraints: RTCMediaConstraints) async throws -> RTCSessionDescription {
        return try await withCheckedThrowingContinuation({ cont in
            factory.webRTCQueue.async {
                os_log("☎️🔌 peerConnection.peerConnection.offer", log: Self.log, type: .info)
                self.peerConnection.offer(for: mediaConstraints) { rtcSessionDescription, error in
                    if let error = error {
                        cont.resume(throwing: error)
                    } else if let rtcSessionDescription = rtcSessionDescription {
                        cont.resume(returning: rtcSessionDescription)
                    } else {
                        cont.resume(throwing: ObvError.sdpOfferGenerationFailed)
                    }
                }
            }
        })
    }

    
    func answer(for mediaConstraints: RTCMediaConstraints) async throws -> RTCSessionDescription {
        return try await withCheckedThrowingContinuation({ cont in
            factory.webRTCQueue.async {
                os_log("☎️🔌 peerConnection.peerConnection.answer", log: Self.log, type: .info)
                self.peerConnection.answer(for: mediaConstraints) { localRTCSessionDescription, error in
                    if let error = error {
                        cont.resume(throwing: error)
                    } else if let localRTCSessionDescription = localRTCSessionDescription {
                        cont.resume(returning: localRTCSessionDescription)
                    } else {
                        cont.resume(throwing: ObvError.sdpAnswerGenerationFailed)
                    }
                }
            }
        })
    }

    
    func setLocalDescription(_ sessionDescription: RTCSessionDescription) async throws {
        return try await withCheckedThrowingContinuation { cont in
            factory.webRTCQueue.async {
                //os_log("☎️ Setting the local description with sdp: %{public}@", log: Self.log, type: .info, sessionDescription.sdp)
                os_log("☎️ Setting the local description", log: Self.log, type: .info)
                os_log("☎️🔌 [Description][Local] peerConnection.peerConnection.setLocalDescription", log: Self.log, type: .info)
                self.peerConnection.setLocalDescription(sessionDescription) { error in
                    if let error = error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume()
                    }
                }
            }
        }
    }

    
    func setRemoteDescription(_ sessionDescription: RTCSessionDescription) async throws {
        return try await withCheckedThrowingContinuation { cont in
            factory.webRTCQueue.async {
                //os_log("☎️ Setting the remote description with sdp: %{public}@", log: Self.log, type: .info, sessionDescription.sdp)
                os_log("☎️ Setting the remote description", log: Self.log, type: .info)
                os_log("☎️🔌 [Description][Remote] peerConnection.peerConnection.setRemoteDescription", log: Self.log, type: .info)
                self.peerConnection.setRemoteDescription(sessionDescription) { error in
                    if let error = error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume()
                    }
                }
            }
        }
    }

    
    func rollback() async throws {
        let rollbackSessionDescription = RTCSessionDescription(type: .rollback, sdp: "")
        try await self.setLocalDescription(rollbackSessionDescription)
    }

    
    func addIceCandidate(_ iceCandidate: RTCIceCandidate) async throws {
        return try await withCheckedThrowingContinuation { cont in
            factory.webRTCQueue.async {
                os_log("☎️🔌 peerConnection.peerConnection.add(iceCandidate)", log: Self.log, type: .info)
                self.peerConnection.add(iceCandidate) { error in
                    if let error = error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume()
                    }
                }
            }
        }
    }

    
    func removeIceCandidates(_ iceCandidates: [RTCIceCandidate]) async {
        return await withCheckedContinuation { cont in
            factory.webRTCQueue.async {
                os_log("☎️🔌 peerConnection.peerConnection.remove(iceCandidate)", log: Self.log, type: .info)
                self.peerConnection.remove(iceCandidates)
                cont.resume()
            }
        }
    }
    

    func addDataChannel(dataChannelDelegate: ObvDataChannelDelegate) async throws {
        let label = "data0"
        let configuration = Self.createRTCDataChannelConfiguration()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            factory.webRTCQueue.async {
                os_log("☎️🔌 peerConnection.peerConnection.dataChannel", log: Self.log, type: .info)
                guard let dataChannel = self.peerConnection.dataChannel(forLabel: label, configuration: configuration) else {
                    return cont.resume(throwing: ObvError.dataChannelCreationFailed)
                }
                self.dataChannel = dataChannel
                self.dataChannelDelegate = dataChannelDelegate
                self.dataChannel?.delegate = self
                return cont.resume()
            }
        }
    }

    
    private static func createRTCDataChannelConfiguration() -> RTCDataChannelConfiguration {
        let configuration = RTCDataChannelConfiguration()
        configuration.isOrdered = true
        configuration.isNegotiated = true
        configuration.channelId = 1
        return configuration
    }

    
    func sendData(buffer: RTCDataBuffer) async -> Bool {
        return await withCheckedContinuation { cont in
            factory.webRTCQueue.async { [weak self] in
                guard let _self = self else { cont.resume(returning: false); return }
                assert(_self.dataChannel != nil)
                let result = _self.dataChannel?.sendData(buffer) ?? false
                cont.resume(returning: result)
            }
        }
    }

    
    func createAndAddAudioTrack(isEnabled: Bool) async {
        
        os_log("☎️🔌 ObvPeerConnection.createAndAddAudioTrack()", log: Self.log, type: .info)
        
        await withCheckedContinuation { [weak self] cont in
            
            guard let self else { return cont.resume() }
            
            factory.webRTCQueue.async { [weak self] in
                
                guard let self else { return cont.resume() }

                if self.localAudioTrack == nil {
                    let audioTrack = factory.createAudioTrack(trackId: ObvMessengerConstants.TrackId.audio)
                    audioTrack.isEnabled = isEnabled
                    os_log("☎️🔌 peerConnection.peerConnection.add(audioTrack)", log: Self.log, type: .info)
                    self.peerConnection.add(audioTrack, streamIds: [ObvMessengerConstants.StreamId.olvid])
                    self.localAudioTrack = audioTrack
                }
                cont.resume()
                
            }
            
        }
    }
    
    
    func createAndAddLocalVideoAndScreencastTracks() async {
        os_log("☎️🔌 ObvPeerConnection.createAndAddLocalVideoAndScreencastTracks()", log: Self.log, type: .info)
        
        await withCheckedContinuation { [weak self] (cont: CheckedContinuation<Void, Never>) in
            
            guard let self else { return cont.resume() }
            
            factory.webRTCQueue.async { [weak self] in
                
                guard let self else { return cont.resume() }
                
                // Although the iOS/macOS versions of Olvid do not support sharing a local screencast yet, we create a screencast track to match the tracks of the Android version of the app.
                if self.localScreencastTrack == nil {
                    let screencastTrack = factory.createScreencastTrack(trackId: ObvMessengerConstants.TrackId.screencast)
                    screencastTrack.isEnabled = false
                    os_log("☎️🔌 peerConnection.peerConnection.add(screencastTrack)", log: Self.log, type: .info)
                    self.peerConnection.add(screencastTrack, streamIds: [ObvMessengerConstants.StreamId.olvid, ObvMessengerConstants.StreamId.screencast])
                    self.localScreencastTrack = screencastTrack
                }

                if self.localVideoTrack == nil {
                    let videoTrack = factory.createVideoTrack(trackId: ObvMessengerConstants.TrackId.video)
                    videoTrack.isEnabled = false
                    os_log("☎️🔌 peerConnection.peerConnection.add(videoTrack)", log: Self.log, type: .info)
                    self.peerConnection.add(videoTrack, streamIds: [ObvMessengerConstants.StreamId.olvid, ObvMessengerConstants.StreamId.video])
                    self.localVideoTrack = videoTrack
                    Task { [weak self] in
                        guard let self else { return }
                        guard let delegate else { return }
                        await delegate.peerConnection(self, didAddLocalVideoTrack: videoTrack)
                    }
                }
                
                cont.resume()
                
            }
            
        }
    }

    
    func setLocalVideoTrack(isEnabled: Bool) async {
        await withCheckedContinuation { [weak self] (cont: CheckedContinuation<Void, Never>) in
            guard let self else { return cont.resume() }
            factory.webRTCQueue.async { [weak self] in
                guard let self else { return cont.resume() }
                assert(self.localVideoTrack != nil)
                self.localVideoTrack?.isEnabled = isEnabled
                cont.resume()
            }
        }
    }
    
    
    func setAudioTrack(isEnabled: Bool) async throws {
        guard let localAudioTrack else {
            assertionFailure()
            throw ObvError.audioTrackIsNil
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            factory.webRTCQueue.async {
                localAudioTrack.isEnabled = isEnabled
                cont.resume()
            }
        }
    }
    
    
    var isAudioTrackEnabled: Bool {
        get throws {
            guard let localAudioTrack else {
                throw ObvError.audioTrackIsNil
            }
            return localAudioTrack.isEnabled
        }
    }
    
}


// MARK: - Errors

extension ObvPeerConnection {
    
    enum ObvError: Error {
        case sdpOfferGenerationFailed
        case sdpAnswerGenerationFailed
        case dataChannelCreationFailed
        case audioTrackIsNil
        case videoTrackIsNil
    }
    
}


// MARK: - Implementing RTCPeerConnectionDelegate

extension ObvPeerConnection: RTCPeerConnectionDelegate {
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        guard peerConnection == self.peerConnection else { assertionFailure(); return }
        Task { [weak self] in
            guard let _self = self else { return }
            await _self.delegate?.peerConnectionShouldNegotiate(_self)
        }
    }
    
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        guard peerConnection == self.peerConnection else { assertionFailure(); return }
        self.signalingState = stateChanged
        Task { [weak self] in
            guard let _self = self else { assertionFailure(); return }
            await _self.delegate?.peerConnection(_self, didChange: stateChanged)
        }
    }
    
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        guard peerConnection == self.peerConnection else { assertionFailure(); return }
        self.connectionState = newState
        Task { [weak self] in
            guard let _self = self else { assertionFailure(); return }
            guard let delegate = _self.delegate else { assertionFailure(); return }
            await delegate.peerConnection(_self, didChange: newState)
        }
    }
    
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        guard peerConnection == self.peerConnection else { assertionFailure(); return }
        self.iceConnectionState = newState
        Task { [weak self] in
            guard let _self = self else { return }
            guard let delegate = _self.delegate else { return }
            await delegate.peerConnection(_self, didChange: newState)
        }
    }
    
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        guard peerConnection == self.peerConnection else { assertionFailure(); return }
        Task { [weak self] in
            guard let _self = self else { assertionFailure(); return }
            guard let delegate = _self.delegate else { assertionFailure(); return }
            await delegate.peerConnection(_self, didChange: newState)
        }
    }
    
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        guard peerConnection == self.peerConnection else { assertionFailure(); return }
        Task { [weak self] in
            guard let _self = self else { return }
            await _self.delegate?.peerConnection(_self, didGenerate: candidate)
        }
    }
    
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        guard peerConnection == self.peerConnection else { assertionFailure(); return }
        Task { [weak self] in
            guard let _self = self else { return }
            await _self.delegate?.peerConnection(_self, didRemove: candidates)
        }
    }
    
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        guard peerConnection == self.peerConnection else { assertionFailure(); return }
        Task { [weak self] in
            guard let _self = self else { return }
            await _self.delegate?.peerConnection(_self, didOpen: dataChannel)
        }
    }
    
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        // Not used, but required by the protocol
        os_log("☎️🔌🥰 ObvPeerConnection.peerConnection(_:didRemove:RTCMediaStream)", log: Self.log, type: .info)
    }

    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        // Not used, but required by the protocol
        os_log("☎️🔌🥰 ObvPeerConnection.peerConnection(_:didAdd:RTCPeerConnection)", log: Self.log, type: .info)
    }
    
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        os_log("☎️🔌🥰 ObvPeerConnection.peerConnection(_:didAdd:RTCRtpReceiver)", log: Self.log, type: .info)
        guard peerConnection == self.peerConnection else { assertionFailure(); return }
        Task { [weak self] in
            guard let self else { return }
            await delegate?.peerConnection(self, didAdd: rtpReceiver, streams: mediaStreams)
        }
    }
    
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove rtpReceiver: RTCRtpReceiver) {
        os_log("☎️🔌🥰 ObvPeerConnection.peerConnection(_:didRemove:RTCRtpReceiver)", log: Self.log, type: .info)
    }
    
}


// MARK: - RTCDataChannelDelegate

extension ObvPeerConnection: RTCDataChannelDelegate {
    
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        guard peerConnection == self.peerConnection else { assertionFailure(); return }
        assert(self.dataChannel == dataChannel)
        Task { [weak self] in
            guard let self else { return }
            await dataChannelDelegate?.dataChannelDidChangeState(dataChannel)
        }
    }
    
    
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard peerConnection == self.peerConnection else { assertionFailure(); return }
        assert(self.dataChannel == dataChannel)
        Task { [weak self] in
            guard let self else { return }
            await dataChannelDelegate?.dataChannel(dataChannel, didReceiveMessageWith: buffer)
        }
    }
    
}


protocol ObvPeerConnectionDelegate: AnyObject {
    
    func peerConnectionShouldNegotiate(_ peerConnection: ObvPeerConnection) async
    func peerConnection(_ peerConnection: ObvPeerConnection, didChange stateChanged: RTCSignalingState) async
    func peerConnection(_ peerConnection: ObvPeerConnection, didChange newState: RTCPeerConnectionState) async
    func peerConnection(_ peerConnection: ObvPeerConnection, didChange newState: RTCIceConnectionState) async
    func peerConnection(_ peerConnection: ObvPeerConnection, didChange newState: RTCIceGatheringState) async
    func peerConnection(_ peerConnection: ObvPeerConnection, didGenerate candidate: RTCIceCandidate) async
    func peerConnection(_ peerConnection: ObvPeerConnection, didRemove candidates: [RTCIceCandidate]) async
    func peerConnection(_ peerConnection: ObvPeerConnection, didOpen dataChannel: RTCDataChannel) async
    func peerConnection(_ peerConnection: ObvPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) async

    // The following delegate method does not have a WebRTC equivalent, we call it ourselves when adding a local video track to the peer connection.
    func peerConnection(_ peerConnection: ObvPeerConnection, didAddLocalVideoTrack videoTrack: RTCVideoTrack) async

}


protocol ObvDataChannelDelegate: AnyObject {
    
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) async
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) async

}
