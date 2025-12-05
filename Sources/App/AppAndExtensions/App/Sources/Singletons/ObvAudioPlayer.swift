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
import AVFoundation
import MediaPlayer
import os.log
import ObvAppCoreConstants

protocol ObvAudioPlayerDelegate: AnyObject {
    func audioPlayerDidFinishPlaying()
    func audioPlayerDidPause()
    func audioPlayerDidStopPlaying()
    func audioIsPlaying(currentTime: TimeInterval)
    func playerWillChangeCurrentFyle(previousHardlink: HardLinkToFyle?)
}

final class ObvAudioPlayer: NSObject, AVAudioPlayerDelegate, ObservableObject {

    enum PlayRate: NSNumber {
        case `default` = 1
        case OneAndhalf = 1.5
        case double = 2
        
        var title: String? {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if let str = formatter.string(from: self.rawValue) {
                return str + " x"
            }
            
            return nil
        }
        
        var next: PlayRate {
            switch self {
            case .default:
                return .OneAndhalf
            case .OneAndhalf:
                return .double
            case .double:
                return .default
            }
        }
    }
    
    public static let shared: ObvAudioPlayer = ObvAudioPlayer()
    private let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: ObvAudioPlayer.self))

    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    var current: HardLinkToFyle?
    
    @Published var currentPlayRate: PlayRate = .default // We need to save the current play rate in order to reset it everytime a new player is created
    
    weak var delegate: ObvAudioPlayerDelegate? {
        willSet { // When delegate changed, we stop previous audioURL attached to this delegate to play.
            delegate?.playerWillChangeCurrentFyle(previousHardlink: current)
        }
    }
    
    var timeObserverToken: Any?

    var currentPosition: TimeInterval? {
        audioPlayer?.currentTime
    }
    
    var totalDuration: TimeInterval? {
        audioPlayer?.duration
    }
        
    var isPlaying: Bool { audioPlayer?.isPlaying ?? false }

    override init() {
        super.init()
        setupRemoteTransportControls()
        // Observe audio route changes
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleRouteChange(_:)),
                                               name: AVAudioSession.routeChangeNotification,
                                               object: nil)
    }

    func play(_ hardLink: HardLinkToFyle, at time: TimeInterval? = 0) -> Bool {
        guard let url = hardLink.hardlinkURL else { return false }
        current = hardLink
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.enableRate = true
            audioPlayer?.delegate = self
            if let timer = timer {
                timer.invalidate()
            }
            guard let audioPlayer = self.audioPlayer else { assertionFailure(); return false }
            
            self.setRate(rate: currentPlayRate)
            
            timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) {_ in
                guard self.isPlaying else { return }
                self.delegate?.audioIsPlaying(currentTime: audioPlayer.currentTime)
                self.setupNowPlaying()
            }
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playAndRecord, options: [.allowBluetoothHFP, .allowBluetoothA2DP])
                try session.setActive(true)
            } catch {
                try? session.setActive(false)
                return false
            }
            if let time = time {
                audioPlayer.currentTime = time
            }
            // Decide output based on current route: if no external output, use speaker; otherwise, default route
            let shouldUseSpeaker = !isExternalOutputConnected
            setSpeaker(to: shouldUseSpeaker)
            logger.info("🎵 Start playing \(url.lastPathComponent, privacy: .public) with speaker \(shouldUseSpeaker ? "enabled" : "disabled", privacy: .public)")
            let success = audioPlayer.play()
            if success {
                setupNowPlaying()
            }
            return success
        } catch(let error) {
            logger.fault("🎵 Failed to play: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func stop() {
        guard let audioPlayer = audioPlayer else { return }
        logger.info("🎵 Stop \(audioPlayer.url?.lastPathComponent ?? "nil", privacy: .public)")
        audioPlayer.stop()
        self.audioPlayer = nil
        self.current = nil
        self.timer?.invalidate()
        self.timer = nil
        self.delegate?.audioPlayerDidStopPlaying()
        self.clearNowPlaying()
    }

    func pause() {
        guard let audioPlayer = audioPlayer else { return }
        logger.info("🎵 Pause \(audioPlayer.url?.lastPathComponent ?? "nil", privacy: .public)")
        audioPlayer.pause()
        self.delegate?.audioPlayerDidPause()
        self.clearNowPlaying()
    }

    func setRate(rate: PlayRate) {
        self.currentPlayRate = rate
        guard let audioPlayer = audioPlayer else { return }
        logger.info("🎵 Changing rate \(audioPlayer.url?.lastPathComponent ?? "nil", privacy: .public)")
        
        audioPlayer.rate = rate.rawValue.floatValue
    }
    
    func resume(at time: TimeInterval? = 0) {
        guard let audioPlayer = audioPlayer else { return }
        if let time = time {
            audioPlayer.currentTime = time
        }
        // Persist the desired output so route changes can react appropriately
        logger.info("🎵 Resume \(audioPlayer.url?.lastPathComponent ?? "nil", privacy: .public)")
        audioPlayer.play()
        self.delegate?.audioIsPlaying(currentTime: audioPlayer.currentTime)
        self.setupNowPlaying()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully successfull: Bool) {
        guard successfull else { return }
        logger.info("🎵 Audio did finish playing \(player.url?.lastPathComponent ?? "nil", privacy: .public)")
        self.delegate?.audioPlayerDidFinishPlaying()
        self.clearNowPlaying()
    }

    static func duration(of url: URL) async throws -> Double {
        let audioAsset = AVURLAsset.init(url: url, options: nil)
        let duration = try await audioAsset.load(.duration)
//        let duration = audioAsset.duration
        let durationInSeconds = CMTimeGetSeconds(duration)
        return durationInSeconds
    }

    var isSpeakerEnable: Bool {
        let session = AVAudioSession.sharedInstance()
        return session.currentRoute.outputs.contains(where: { (output: AVAudioSessionPortDescription) -> Bool in
            return output.portType == AVAudioSession.Port.builtInSpeaker
        })
    }

    private var isExternalOutputConnected: Bool {
        let session = AVAudioSession.sharedInstance()
        // Consider headphones, Bluetooth, HDMI, AirPlay as external (non-speaker) outputs
        return session.currentRoute.outputs.contains(where: { (output: AVAudioSessionPortDescription) -> Bool in
            switch output.portType {
            case AVAudioSession.Port.headphones,
                 AVAudioSession.Port.bluetoothA2DP,
                 AVAudioSession.Port.bluetoothLE,
                 AVAudioSession.Port.bluetoothHFP,
                 AVAudioSession.Port.HDMI,
                 AVAudioSession.Port.airPlay,
                 AVAudioSession.Port.lineOut,
                 AVAudioSession.Port.carAudio,
                 AVAudioSession.Port.displayPort,
                 AVAudioSession.Port.usbAudio:
                return true
            default:
                return false
            }
        })
    }

    func setSpeaker(to value: Bool) {
        guard value != isSpeakerEnable else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            if value {
                try session.overrideOutputAudioPort(.speaker)
            } else {
                try session.overrideOutputAudioPort(.none)
            }
            logger.info("🎵 Speaker was \(value ? "enabled" : "disabled", privacy: .public)")
        } catch {
            logger.error("🎵 Could not \(value ? "enable" : "disable", privacy: .public) speaker: \(error.localizedDescription, privacy: .public)")
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        
        if let userInfo = notification.userInfo,
           let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
           let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) {
            guard reason == .newDeviceAvailable || reason == .oldDeviceUnavailable else { return } // Only handle connected or disconnected devices.
        }
        
        // Always apply output logic for subsequent notifications
        applyOutputForCurrentRoute()
    }

    private func applyOutputForCurrentRoute() {
        let shouldUseSpeaker = !isExternalOutputConnected
        // If we are moving to speaker and playback is ongoing, pause as requested
        if shouldUseSpeaker && isPlaying {
            pause()
        }
        setSpeaker(to: shouldUseSpeaker)
    }

}

extension ObvAudioPlayer {

    func setupRemoteTransportControls() {
        /// Get the shared MPRemoteCommandCenter
        let commandCenter = MPRemoteCommandCenter.shared()

        /// Add handler for Play Command
        commandCenter.playCommand.addTarget { [weak self] event in
            guard let audioPlayer = self?.audioPlayer else { return .commandFailed }
            if !audioPlayer.isPlaying {
                audioPlayer.play()
                return .success
            }
            return .commandFailed
        }

        /// Add handler for Pause Command
        commandCenter.pauseCommand.addTarget { [weak self] event in
            guard let audioPlayer = self?.audioPlayer else { return .commandFailed }
            if audioPlayer.isPlaying {
                audioPlayer.pause()
                return .success
            }
            return .commandFailed
        }
    }

    func setupNowPlaying() {
        guard let audioPlayer = self.audioPlayer else { return }
        /// Define Now Playing Info
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = audioPlayer.url?.lastPathComponent

        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = audioPlayer.currentTime
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = Int(audioPlayer.duration)
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0

        /// Set the metadata
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

}
