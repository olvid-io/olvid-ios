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
import ObvSettings
import OSLog


actor ObvPeerConnectionFactory {

    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "ObvPeerConnectionFactory")

    let webRTCQueue = DispatchQueue(label: "WebRTC queue") // Queue to use for synchronizing all calls to the WebRTC framework
    private let factory: RTCPeerConnectionFactory

    private let localAudioSource: RTCAudioSource
    private let localCameraVideoSource: RTCVideoSource
    private let localScreencastSource: RTCVideoSource
    
    private var localVideoCapturer: RTCCameraVideoCapturer?
    private var currentCameraPosition: AVCaptureDevice.Position?
    private var currentVideoSize: CGSize?
    private var localPreviewVideoTrack: RTCVideoTrack? // Not added to a peer connexion, only used to display a preview

    init() {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        self.factory = RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        self.localAudioSource = factory.audioSource(with: constraints)
        self.localCameraVideoSource = factory.videoSource(forScreenCast: false)
        self.localScreencastSource = factory.videoSource(forScreenCast: true)
    }
    
    
    deinit {
        debugPrint("ObvPeerConnectionFactory deinit")
    }

    
    func createPeerConnection(with configuration: RTCConfiguration, constraints: RTCMediaConstraints) async throws -> RTCPeerConnection {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RTCPeerConnection, Error>) in
            guard let peerConnection = factory.peerConnection(with: configuration, constraints: constraints, delegate: nil) else {
                return continuation.resume(throwing: ObvError.rtcPeerConnectionCreationFailed)
            }
            return continuation.resume(returning: peerConnection)
        }
    }


    /// Creates and return a `RTCAudioTrack`.
    nonisolated
    func createAudioTrack(trackId: String) -> RTCAudioTrack {
        let audioTrack = factory.audioTrack(with: localAudioSource, trackId: trackId)
        return audioTrack
    }
    
    
    /// Creates and return a local `RTCVideoTrack`.
    nonisolated
    func createVideoTrack(trackId: String) -> RTCVideoTrack {
        let videoTrack = factory.videoTrack(with: localCameraVideoSource, trackId: trackId)
        return videoTrack
    }
    
    
    /// Although the iOS/macOS versions of Olvid do not support sharing a local screencast yet, we create a screencast track to match the tracks of the Android version of the app.
    nonisolated
    func createScreencastTrack(trackId: String) -> RTCVideoTrack {
        let screencastTrack = factory.videoTrack(with: localScreencastSource, trackId: trackId)
        return screencastTrack
    }

    
    enum ObvError: Error {
        case rtcPeerConnectionCreationFailed
        case couldNotAccessRequestedLocalCaptureDevice
        case couldNotAccessSupportedFormats
        case couldNotDetermineFPS
        case badAVCaptureDeviceAuthorizationStatus(currentStatus: AVAuthorizationStatus)
    }
    
    // MARK: - Capturing a local video stream
    
    func startCaptureLocalVideo(preferredPosition: AVCaptureDevice.Position) async throws -> (previewVideoTrack: RTCVideoTrack, position: AVCaptureDevice.Position, videoSize: CGSize) {
        
        // Check that video authorization status
        
        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch authorizationStatus {
        case .notDetermined, .restricted, .denied:
            throw ObvError.badAVCaptureDeviceAuthorizationStatus(currentStatus: authorizationStatus)
        case .authorized:
            break // No problem, we can continue
        @unknown default:
            assertionFailure()
            throw ObvError.badAVCaptureDeviceAuthorizationStatus(currentStatus: authorizationStatus)
        }
                
        // If we reach this point, we can try to capture a local video stream
        
        if let localPreviewVideoTrack, let currentVideoSize {
            if currentCameraPosition == preferredPosition {
                return (localPreviewVideoTrack, preferredPosition, currentVideoSize)
            } else {
                if let localVideoCapturer {
                    await localVideoCapturer.stopCapture()
                    self.localVideoCapturer = nil
                    self.currentCameraPosition = nil
                    self.currentVideoSize = nil
                    self.localPreviewVideoTrack = nil
                }
            }
        }
        
        let frontCamera = RTCCameraVideoCapturer.captureDevices().first(where: { $0.position == .front })
        let backCamera = RTCCameraVideoCapturer.captureDevices().first(where: { $0.position == .back })
        let cameras: [AVCaptureDevice]
        switch preferredPosition {
        case .front, .unspecified:
            cameras = [frontCamera, backCamera].compactMap({ $0 })
        case .back:
            cameras = [backCamera, frontCamera].compactMap({ $0 })
        @unknown default:
            cameras = [frontCamera, backCamera].compactMap({ $0 })
        }
        
        guard let cameraToUse = cameras.first else {
            assertionFailure()
            throw ObvError.couldNotAccessRequestedLocalCaptureDevice
        }
        
        let allFormats = RTCCameraVideoCapturer.supportedFormats(for: cameraToUse).filter({ $0.mediaType == .video })
        
        let format = try getUserPreferredFormat(among: allFormats)
                
        let videoSize = CGSize(width: CGFloat(CMVideoFormatDescriptionGetDimensions(format.formatDescription).width),
                               height: CGFloat(CMVideoFormatDescriptionGetDimensions(format.formatDescription).height))

        // Compute the fps for the capturer. Take the maximum acceptable fps, but not larger than 30fps.
        
        let fps: Float64 = min(30, format.videoSupportedFrameRateRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate })?.maxFrameRate ?? 30)
        
        let capturer = RTCCameraVideoCapturer(delegate: localCameraVideoSource)
        
        if ObvMessengerConstants.targetEnvironmentIsMacCatalyst {
            capturer.setRotationDependsOnDeviceOrientation(false)
        }

        try await capturer.startCapture(with: cameraToUse, format: format, fps: Int(fps))

        let track = createVideoTrack(trackId: "localPreviewVideoTrack")

        self.localVideoCapturer = capturer
        self.currentCameraPosition = cameraToUse.position
        self.currentVideoSize = videoSize
        self.localPreviewVideoTrack = track

        return (track, cameraToUse.position, videoSize)

    }

    
    func stopCaptureLocalVideo() async {
        await self.localVideoCapturer?.stopCapture()
        self.localVideoCapturer = nil
        self.currentCameraPosition = nil
        self.currentVideoSize = nil
        self.localPreviewVideoTrack = nil
    }
    
    
    
    private func getUserPreferredFormat(among allFormats: [AVCaptureDevice.Format]) throws -> AVCaptureDevice.Format {
        
        let preferredVideoSendResolution = ObvMessengerSettings.VoIP.videoSendResolution
        let preferredHeight = preferredVideoSendResolution.rawValue // 1080, 720, etc.
        
        // Compute a dictionary where the values are formats, all having the same distance to the preferred height
        var formatFromDistanceToPreferredHeight = [Int: [AVCaptureDevice.Format]]()
        for format in allFormats {
            let distance = abs(Int(CMVideoFormatDescriptionGetDimensions(format.formatDescription).height) - preferredHeight)
            var formats = formatFromDistanceToPreferredHeight[distance, default: []]
            formats.append(format)
            formatFromDistanceToPreferredHeight[distance] = formats
        }
        
        // Find all the formats having the shortest distance to the user preferred height.
        
        guard let formatsWithAppropriateHeight = formatFromDistanceToPreferredHeight.min(by: { $0.key < $1.key })?.value else {
            throw ObvError.couldNotAccessSupportedFormats
        }
        
        // Keep the formats with the largest width
        
        guard let maxAvailableWidth = formatsWithAppropriateHeight.map({ CMVideoFormatDescriptionGetDimensions($0.formatDescription).width }).max() else {
            throw ObvError.couldNotAccessSupportedFormats
        }
        
        let formatsWithAppropriateSize = formatsWithAppropriateHeight.filter({ CMVideoFormatDescriptionGetDimensions($0.formatDescription).width == maxAvailableWidth })
        
        if formatsWithAppropriateSize.count == 1 {
            return formatsWithAppropriateSize.first!
        }
        
        guard !formatsWithAppropriateSize.isEmpty else {
            throw ObvError.couldNotAccessSupportedFormats
        }
        
        // If at least one format supports reactions, keep only the formats supporting this feature
        
        var remainingFormats = formatsWithAppropriateSize
        
        if #available(iOS 17.0, *) {
            if remainingFormats.contains(where: { $0.reactionEffectsSupported }) {
                remainingFormats = remainingFormats.filter({ $0.reactionEffectsSupported })
            }
        }
        
        // If at least one format supports center stage, keep only the formats supporting this feature
        
        if remainingFormats.contains(where: { $0.isCenterStageSupported }) {
            remainingFormats = remainingFormats.filter({ $0.isCenterStageSupported })
        }

        // If at least one format supports HDR, keep only the formats supporting this feature

        if remainingFormats.contains(where: { $0.isVideoHDRSupported }) {
            remainingFormats = remainingFormats.filter({ $0.isVideoHDRSupported })
        }

        // If at least one format supports 420f (vs 420v), keep only the formats supporting this feature
        
        if remainingFormats.contains(where: { $0.formatDescription.mediaSubType == .init(rawValue: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) }) {
            remainingFormats = remainingFormats.filter { $0.formatDescription.mediaSubType == .init(rawValue: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) }
        }

        // Keep the formats with the largest possible max fps
        
        guard let formatToUse = remainingFormats.max(by: { $0.maxFrameRate < $1.maxFrameRate }) else {
            throw ObvError.couldNotAccessSupportedFormats
        }
        
        return formatToUse
        
    }
        
}

// MARK: - Helpers

private extension AVCaptureDevice.Format {
    
    var maxFrameRate: Float64 {
        return self.videoSupportedFrameRateRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate })?.maxFrameRate ?? 0
    }
    
}


private extension RTCCameraVideoCapturer {
    
    func stopCapture() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            stopCapture { continuation.resume() }
        }
    }
    
}
