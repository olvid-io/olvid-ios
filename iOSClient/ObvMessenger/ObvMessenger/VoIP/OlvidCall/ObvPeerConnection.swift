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
import WebRTC
import os.log
import OlvidUtils


/// An instance of this class is a wrapper around a WebRTC `RTCPeerConnection` object. It ensures all the calls made to this wrapped object are made on the same internal serial queue.
final class ObvPeerConnection: NSObject {

    private static let internalQueue = DispatchQueue(label: "ObvPeerConnection internal queue")
    private static let factory = ObvPeerConnectionFactory(internalQueue: internalQueue)

    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: ObvPeerConnection.self))
    
    private var peerConnection: RTCPeerConnection!
    private var dataChannel: RTCDataChannel?
    private var audioTrack: RTCAudioTrack?

    private(set) var connectionState: RTCPeerConnectionState = .new
    private(set) var signalingState: RTCSignalingState = .stable
    private(set) var iceConnectionState: RTCIceConnectionState = .new
    
    private weak var delegate: ObvPeerConnectionDelegate?
    private weak var dataChannelDelegate: ObvDataChannelDelegate?

    
    init(with configuration: RTCConfiguration, constraints: RTCMediaConstraints, delegate: ObvPeerConnectionDelegate) async throws {
        self.delegate = delegate
        super.init()
        guard let pc = await ObvPeerConnection.factory.make(with: configuration, constraints: constraints, delegate: self) else {
            throw ObvError.rtcPeerConnectionCreationFailed
        }
        self.peerConnection = pc
    }


    func close() async {
        return await withCheckedContinuation { cont in
            Self.internalQueue.async {
                os_log("☎️🔌 peerConnection.close()", log: Self.log, type: .info)
                self.peerConnection.close()
                cont.resume()
            }
        }
    }

    
    func restartIce() async {
        return await withCheckedContinuation { cont in
            Self.internalQueue.async {
                os_log("☎️🔌 peerConnection.restartIce()", log: Self.log, type: .info)
                self.peerConnection.restartIce()
                cont.resume()
            }
        }
    }

    
    var localDescription: RTCSessionDescription? {
        get async {
            return await withCheckedContinuation { cont in
                Self.internalQueue.async {
                    cont.resume(returning: self.peerConnection.localDescription)
                }
            }
        }

    }


    func offer(for mediaConstraints: RTCMediaConstraints) async throws -> RTCSessionDescription {
        return try await withCheckedThrowingContinuation({ cont in
            Self.internalQueue.async {
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
            Self.internalQueue.async {
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
            Self.internalQueue.async {
                //os_log("☎️ Setting the local description with sdp: %{public}@", log: Self.log, type: .info, sessionDescription.sdp)
                os_log("☎️ Setting the local description", log: Self.log, type: .info)
                os_log("☎️🔌 peerConnection.peerConnection.setLocalDescription", log: Self.log, type: .info)
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
            Self.internalQueue.async {
                //os_log("☎️ Setting the remote description with sdp: %{public}@", log: Self.log, type: .info, sessionDescription.sdp)
                os_log("☎️ Setting the remote description", log: Self.log, type: .info)
                os_log("☎️🔌 peerConnection.peerConnection.setRemoteDescription", log: Self.log, type: .info)
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
            Self.internalQueue.async {
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
            Self.internalQueue.async {
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
            Self.internalQueue.async {
                os_log("☎️🔌 peerConnection.peerConnection.dataChannel", log: Self.log, type: .info)
                guard let dataChannel = self.peerConnection.dataChannel(forLabel: label, configuration: configuration) else {
                    cont.resume(throwing: ObvError.dataChannelCreationFailed)
                    return
                }
                self.dataChannel = dataChannel
                self.dataChannelDelegate = dataChannelDelegate
                self.dataChannel?.delegate = self
                cont.resume()
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
            Self.internalQueue.async { [weak self] in
                guard let _self = self else { cont.resume(returning: false); return }
                assert(_self.dataChannel != nil)
                let result = _self.dataChannel?.sendData(buffer) ?? false
                cont.resume(returning: result)
            }
        }
    }

    
    func addAudioTrack(isEnabled: Bool) async throws {
        let streamId = "audioStreamId"
        let audioConstrains = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = try await Self.factory.audioSource(with: audioConstrains)
        let audioTrack = try await Self.factory.audioTrack(with: audioSource, trackId: "audio0")
        await withCheckedContinuation { cont in
            Self.internalQueue.async {
                audioTrack.isEnabled = isEnabled
                os_log("☎️🔌 peerConnection.peerConnection.add(audioTrack)", log: Self.log, type: .info)
                self.peerConnection.add(audioTrack, streamIds: [streamId])
                self.audioTrack = audioTrack
                cont.resume()
            }
        }
    }

    
    func setAudioTrack(isEnabled: Bool) async throws {
        guard let audioTrack else {
            assertionFailure()
            throw ObvError.audioTrackIsNil
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            Self.internalQueue.async {
                audioTrack.isEnabled = isEnabled
                cont.resume()
            }
        }
    }
    
    
    var isAudioTrackEnabled: Bool {
        get throws {
            guard let audioTrack else {
                throw ObvError.audioTrackIsNil
            }
            return audioTrack.isEnabled
        }
    }
    
}


// MARK: - Errors

extension ObvPeerConnection {
    
    enum ObvError: Error {
        case sdpOfferGenerationFailed
        case sdpAnswerGenerationFailed
        case rtcPeerConnectionCreationFailed
        case dataChannelCreationFailed
        case audioTrackIsNil
    }
    
}


// MARK: - ObvPeerConnectionFactory

private final class ObvPeerConnectionFactory {

    private let internalQueue: DispatchQueue
    private var factory: RTCPeerConnectionFactory?

    private static let errorDomain = "ObvPeerConnectionFactory"
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: ObvPeerConnectionFactory.errorDomain, code: 0, userInfo: userInfo)
    }

    init(internalQueue: DispatchQueue) {
        self.internalQueue = internalQueue
    }

    func make(with configuration: RTCConfiguration, constraints: RTCMediaConstraints, delegate: RTCPeerConnectionDelegate?) async -> RTCPeerConnection? {
        return await withCheckedContinuation { cont in
            self.internalQueue.async {
                if self.factory == nil {
                    RTCInitializeSSL()
                    let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
                    let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
                    self.factory = RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
                }
                let pc = self.factory?.peerConnection(with: configuration, constraints: constraints, delegate: delegate)
                cont.resume(returning: pc)
            }
        }
    }

    func audioSource(with constraints: RTCMediaConstraints) async throws -> RTCAudioSource {
        return try await withCheckedThrowingContinuation { cont in
            self.internalQueue.async {
                guard let factory = self.factory else {
                    cont.resume(throwing: Self.makeError(message: "Factory is not instantiated"))
                    return
                }
                cont.resume(returning: factory.audioSource(with: constraints))
            }
        }
    }

    func audioTrack(with audioSource: RTCAudioSource, trackId: String) async throws -> RTCAudioTrack {
        return try await withCheckedThrowingContinuation { cont in
            self.internalQueue.async {
                guard let factory = self.factory else {
                    cont.resume(throwing: Self.makeError(message: "Factory is not instantiated"))
                    return
                }
                cont.resume(returning: factory.audioTrack(with: audioSource, trackId: trackId))
            }
        }
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
            guard let delegate = _self.delegate else { assertionFailure(); return }
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
    }

    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        // Not used, but required by the protocol
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

}


protocol ObvDataChannelDelegate: AnyObject {
    
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) async
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) async

}
