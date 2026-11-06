/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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

    /// What is actually making the sound, there being two things that can.
    private var engine: TheThingMakingTheSound?
    private var timer: Timer?

    /// Set only for the fallback, which has no delegate and says what has become of it by posting notifications.
    private var whatTheFallbackHasToSay: [any NSObjectProtocol] = []

    /// Set only for the fallback, whose item reports through neither a delegate nor a notification whether it can be read at all.
    private var whetherTheFallbackCanReadTheFile: NSKeyValueObservation?

    /// Where the fallback was asked to start, kept until its item can be seeked. An `AVPlayer` drops a seek made before its item is ready to play rather than
    /// performing it when it becomes ready, so a recording scrubbed to the middle and started would begin at the beginning.
    private var whereTheFallbackShouldStart: TimeInterval?

    var current: HardLinkToFyle?
    
    @Published var currentPlayRate: PlayRate = .default // We need to save the current play rate in order to reset it everytime a new player is created
    
    weak var delegate: ObvAudioPlayerDelegate? {
        willSet { // When delegate changed, we stop previous audioURL attached to this delegate to play.
            delegate?.playerWillChangeCurrentFyle(previousHardlink: current)
        }
    }
    
    var timeObserverToken: Any?

    var currentPosition: TimeInterval? {
        engine?.currentTime
    }
    
    var totalDuration: TimeInterval? {
        engine?.duration
    }
        
    var isPlaying: Bool { engine?.isPlaying ?? false }

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
        stopListeningToTheFallback()
        let engine = makeSomethingThatWillPlay(url)
        self.engine = engine
        if case .anAsset(_, let item) = engine {
            // Set before the observation below, which fires while it is being installed.
            whereTheFallbackShouldStart = time
            whatTheFallbackHasToSay = [
                NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                    self?.theRecordingHasBeenHeardOut()
                },
                // Acted on rather than merely written down. The fallback cannot say at the moment it is asked whether it will play — it answers `true` before
                // reading a byte — so everything above has already been told that this recording is playing. Left as a log line, a recording neither reader can
                // decode would sit there with a pause button on it for ever.
                NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] notification in
                    let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                    self?.theFallbackCannotPlay(url, item: item, reason: error?.localizedDescription)
                },
            ]
            // The other way the fallback can fail, and the one that matters here: an item that never becomes ready to play at all. Nothing is posted for it, so it
            // is watched rather than waited for. `.initial` as well as `.new`, so that a status already settled before this line runs is not missed in silence.
            // The same observation says when the item can be seeked, which is the only moment at which the fallback can be put where it was asked to start.
            whetherTheFallbackCanReadTheFile = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                switch item.status {
                case .failed:
                    self?.theFallbackCannotPlay(url, item: item, reason: item.error?.localizedDescription)
                case .readyToPlay:
                    self?.theFallbackCanNowStartWhereItWasAskedTo(item: item)
                default:
                    break
                }
            }
        }
        timer?.invalidate()

        self.setRate(rate: currentPlayRate)

        timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { _ in
            guard self.isPlaying else { return }
            guard let currentTime = self.engine?.currentTime else { return }
            self.delegate?.audioIsPlaying(currentTime: currentTime)
            self.setupNowPlaying()
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, options: [.allowBluetoothHFP, .allowBluetoothA2DP])
            try session.setActive(true)
            OlvidCallInAppLog.log(call: nil, "voice message player activated the audio session; \(OlvidCallInAppLog.audioSessionSnapshot())")
        } catch {
            logger.fault("🎵 Failed to take the audio session: \(error.localizedDescription, privacy: .public)")
            try? session.setActive(false)
            OlvidCallInAppLog.log(call: nil, "voice message player could not take the audio session (\(error.localizedDescription)) and deactivated it; \(OlvidCallInAppLog.audioSessionSnapshot())")
            // The engine, the clock and — for the fallback — three observers are installed by the time this is reached, and nothing else will take them away: a
            // caller answers a refusal by forgetting that it ever asked, so ``stop()`` is never called. Let go of them silently, nothing having been announced.
            letGoOfTheRecording()
            return false
        }
        if let time = time {
            engine.seek(to: time)
        }
        // Decide output based on current route: if no external output, use speaker; otherwise, default route
        let shouldUseSpeaker = !isExternalOutputConnected
        setSpeaker(to: shouldUseSpeaker)
        logger.notice("🎵 Start playing \(url.lastPathComponent, privacy: .private(mask: .hash)) through \(engine.name, privacy: .public) with speaker \(shouldUseSpeaker ? "enabled" : "disabled", privacy: .public)")
        let success = engine.play()
        if success {
            setupNowPlaying()
        } else {
            logger.fault("🎵 The player refused to play \(url.lastPathComponent, privacy: .private(mask: .hash))")
            // A refusal here is answered the way a refused audio session is: the caller forgets that it ever asked, so ``stop()`` is never called and nothing
            // else takes the engine, the clock and the observers away. Reached only for `AVAudioPlayer` — the fallback answers `true` before reading a byte and
            // reports its failure through ``theFallbackCannotPlay(_:item:reason:)``.
            try? session.setActive(false)
            OlvidCallInAppLog.log(call: nil, "voice message player refused to play and deactivated the audio session; \(OlvidCallInAppLog.audioSessionSnapshot())")
            letGoOfTheRecording()
        }
        return success
    }


    /// `AVAudioPlayer` for everything it will open, and `AVPlayer` for the rest.
    ///
    /// **The fallback is not a second guess at the same question.** `AVAudioPlayer` reaches a file through Audio File Services, which chooses a parser from the
    /// file's name and hands it the bytes: a name ending in `.mp3` goes to the MP3 parser, and a file that parser cannot scan is refused outright with
    /// `kAudioFileInvalidFileError` — measured on a received interview recording, which drew its whole waveform and then made no sound at all, in the new
    /// discussion screen and in the legacy one alike. `AVPlayer` reaches the same bytes through CoreMedia, which is a different reader, and the waveform is the
    /// proof that this one can read them: it is drawn by an `AVAssetReader` decoding the file to PCM, so a recording with bars has already been read end to end
    /// by the machinery the fallback uses.
    ///
    /// Tried second rather than first, and that is deliberate: nothing that plays today changes. `AVAudioPlayer` seeks without tolerance, reports its position
    /// synchronously, and is what every recording in this app has always been played through.
    private func makeSomethingThatWillPlay(_ url: URL) -> TheThingMakingTheSound {
        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer.enableRate = true
            audioPlayer.delegate = self
            return .anAudioFile(audioPlayer)
        } catch {
            logger.error("🎵 AVAudioPlayer refused \(url.lastPathComponent, privacy: .private(mask: .hash)) (\(error.localizedDescription, privacy: .public)), falling back on AVPlayer")
            let item = AVPlayerItem(url: url)
            // Pitch-preserving, as `enableRate` is on the player above, so the two sound the same at 1.5× and 2×.
            item.audioTimePitchAlgorithm = .spectral
            let player = AVPlayer(playerItem: item)
            return .anAsset(player, item: item)
        }
    }


    /// The fallback has failed, which it can only say after having answered that it would play.
    ///
    /// Stopped outright rather than left standing: everything above has been told this recording is playing, and ``stop()`` is what unsays it — the delegate is told,
    /// the player lets go of the recording, and the view showing it draws a play button again instead of a pause it can never honour.
    ///
    /// **The stopping is put off to the next turn of the main queue, and both halves of that are load-bearing.** `AVPlayerItem`'s status is reported on whatever
    /// thread settled it, where nothing else in this class is, and stopping would otherwise invalidate the very observation whose block is running — releasing the
    /// last reference to a closure that has not returned. What comes with putting it off is that the player may by then be holding something else, so it is stopped
    /// only if it is still holding the one that failed.
    private func theFallbackCannotPlay(_ url: URL, item: AVPlayerItem, reason: String?) {
        logger.fault("🎵 AVPlayer cannot play \(url.lastPathComponent, privacy: .private(mask: .hash)): \(reason ?? "no reason given", privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard case .anAsset(_, let stillHeld) = self.engine, stillHeld === item else { return }
            self.stop()
        }
    }


    /// The fallback's item is ready, so the seek it was given while it was not can be made.
    ///
    /// Put off to the next turn of the main queue for the same two reasons as ``theFallbackCannotPlay(_:item:reason:)``: the status is reported on whatever thread
    /// settled it, and the player may by then be holding another recording, which is what the identity test answers. The requested time is forgotten once used, so
    /// an item that becomes ready twice — one asked to play again after having been paused — is not thrown back to where it first started.
    private func theFallbackCanNowStartWhereItWasAskedTo(item: AVPlayerItem) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard case .anAsset(_, let stillHeld) = self.engine, stillHeld === item else { return }
            guard let time = self.whereTheFallbackShouldStart else { return }
            self.whereTheFallbackShouldStart = nil
            self.logger.notice("🎵 The fallback is ready and starts at \(time, privacy: .public)")
            self.engine?.seek(to: time)
        }
    }


    private func stopListeningToTheFallback() {
        whatTheFallbackHasToSay.forEach { NotificationCenter.default.removeObserver($0) }
        whatTheFallbackHasToSay = []
        whereTheFallbackShouldStart = nil
        whetherTheFallbackCanReadTheFile?.invalidate()
        whetherTheFallbackCanReadTheFile = nil
    }


    /// The fallback has reached the end of the recording. The other one is told through ``audioPlayerDidFinishPlaying(_:successfully:)``.
    private func theRecordingHasBeenHeardOut() {
        logger.notice("🎵 Audio did finish playing \(self.engine?.url?.lastPathComponent ?? "nil", privacy: .private(mask: .hash))")
        OlvidCallInAppLog.log(call: nil, "voice message player reached the end of the recording; \(OlvidCallInAppLog.audioSessionSnapshot())")
        self.delegate?.audioPlayerDidFinishPlaying()
        self.clearNowPlaying()
    }

    func stop() {
        guard let engine else { return }
        logger.notice("🎵 Stop \(engine.url?.lastPathComponent ?? "nil", privacy: .private(mask: .hash))")
        OlvidCallInAppLog.log(call: nil, "voice message player stopped; \(OlvidCallInAppLog.audioSessionSnapshot())")
        letGoOfTheRecording()
        self.delegate?.audioPlayerDidStopPlaying()
        self.clearNowPlaying()
    }


    /// Undoes everything ``play(_:at:)`` installs, and says nothing to anybody.
    ///
    /// The silence is the point: ``stop()`` uses this and then tells the delegate, where a `play` that refuses the recording has announced nothing there is to
    /// unsay.
    private func letGoOfTheRecording() {
        self.engine?.stop()
        self.engine = nil
        self.current = nil
        stopListeningToTheFallback()
        self.timer?.invalidate()
        self.timer = nil
    }

    func pause() {
        guard let engine else { return }
        logger.notice("🎵 Pause \(engine.url?.lastPathComponent ?? "nil", privacy: .private(mask: .hash))")
        engine.pause()
        self.delegate?.audioPlayerDidPause()
        self.clearNowPlaying()
    }

    func setRate(rate: PlayRate) {
        self.currentPlayRate = rate
        guard let engine else { return }
        logger.info("🎵 Changing rate \(engine.url?.lastPathComponent ?? "nil", privacy: .private(mask: .hash))")
        
        engine.setRate(rate.rawValue.floatValue)
    }
    
    func resume(at time: TimeInterval? = 0) {
        guard let engine else { return }
        if let time = time {
            engine.seek(to: time)
        }
        
        // Before playing the audio, we re-apply the appropriate audio output
        let shouldUseSpeaker = !isExternalOutputConnected
        setSpeaker(to: shouldUseSpeaker)

        // Persist the desired output so route changes can react appropriately
        logger.notice("🎵 Resume \(engine.url?.lastPathComponent ?? "nil", privacy: .private(mask: .hash))")
        _ = engine.play()
        // The time that was **asked for**, not the one read back. The fallback's seek is asynchronous, so reading its position here returns where the recording
        // stood before the seek — which is then recorded above as where it has got to, and a scrub from 0:02 to 1:30 snaps back to 0:02 until the next tick.
        self.delegate?.audioIsPlaying(currentTime: time ?? engine.currentTime)
        self.setupNowPlaying()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully successfull: Bool) {
        guard successfull else { return }
        theRecordingHasBeenHeardOut()
    }

    static func duration(of url: URL) async throws -> Double {
        let audioAsset = AVURLAsset.init(url: url, options: nil)
        let duration = try await audioAsset.load(.duration)
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
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, options: [.allowBluetoothHFP, .allowBluetoothA2DP])
        try? session.setMode(.default)
        
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
            guard let engine = self?.engine else { return .commandFailed }
            if !engine.isPlaying {
                _ = engine.play()
                return .success
            }
            return .commandFailed
        }

        /// Add handler for Pause Command
        commandCenter.pauseCommand.addTarget { [weak self] event in
            guard let engine = self?.engine else { return .commandFailed }
            if engine.isPlaying {
                engine.pause()
                return .success
            }
            return .commandFailed
        }
    }

    func setupNowPlaying() {
        guard let engine else { return }
        /// Define Now Playing Info
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = engine.url?.lastPathComponent

        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = engine.currentTime
        // Left out rather than defaulted when the length is not known: `Int(_:)` of a `Double` that is `nan` — which is what an asset reports until its item is
        // ready — is a trap, not a zero.
        if let duration = engine.duration {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = Int(duration)
        }
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0

        /// Set the metadata
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

}


/// One of the two things that can make the sound of a recording.
///
/// There are two because there are two readers. `AVAudioPlayer` reaches a file through Audio File Services, which picks a parser from the file's **name**; `AVPlayer`
/// reaches it through CoreMedia, which is what the waveform is drawn with. A recording whose name promises one thing and whose bytes are another — or one whose
/// bytes the stricter parser simply cannot scan — draws its bars and refuses to play. See ``ObvAudioPlayer/makeSomethingThatWillPlay(_:)``.
///
/// Everything above this is written once and asks nothing about which of the two it has. The one asymmetry worth knowing is the **rate**: setting `rate` on an
/// `AVPlayer` *starts it playing*, where setting it on an `AVAudioPlayer` does not, so the fallback carries the reader's chosen speed in `defaultRate` and writes
/// `rate` only when there is already a sound to change the speed of.
private enum TheThingMakingTheSound {

    case anAudioFile(AVAudioPlayer)
    case anAsset(AVPlayer, item: AVPlayerItem)

    /// For the log alone.
    var name: String {
        switch self {
        case .anAudioFile: return "AVAudioPlayer"
        case .anAsset: return "AVPlayer"
        }
    }

    var url: URL? {
        switch self {
        case .anAudioFile(let player): return player.url
        case .anAsset(_, let item): return (item.asset as? AVURLAsset)?.url
        }
    }

    var currentTime: TimeInterval {
        switch self {
        case .anAudioFile(let player): return player.currentTime
        case .anAsset(let player, _):
            let time = player.currentTime()
            return time.isNumeric ? time.seconds : 0
        }
    }

    /// Nil while the length is not known, which for an asset is until its item is ready — and which is **not** the same as nought. Whoever asks must be able to tell
    /// the two apart: the discussion screen divides by this to know how far along the recording is.
    var duration: TimeInterval? {
        switch self {
        case .anAudioFile(let player): return player.duration
        case .anAsset(_, let item):
            guard item.duration.isNumeric else { return nil }
            return item.duration.seconds
        }
    }

    /// Whether there is a sound, which for the fallback is **`.playing` alone**.
    ///
    /// `.waitingToPlayAtSpecifiedRate` is not it, though it is not `.paused` either: an item that never becomes ready stays in it for ever, and reading it as
    /// playing would leave a pause button on a silent recording and have a route change pause a player that never started. The cost of the strict reading is that
    /// the moment right after `play()` answers *not playing*; the clock above runs whatever this says and corrects it on its next tick, 30ms later.
    var isPlaying: Bool {
        switch self {
        case .anAudioFile(let player): return player.isPlaying
        case .anAsset(let player, _): return player.timeControlStatus == .playing
        }
    }

    /// Whether a sound was started. An asset answers *yes* without having read a byte, there being nothing to ask it synchronously — which is honest rather than
    /// optimistic: it is reached only when the file has already been read end to end to draw its waveform.
    func play() -> Bool {
        switch self {
        case .anAudioFile(let player): return player.play()
        case .anAsset(let player, _): player.play(); return true
        }
    }

    func pause() {
        switch self {
        case .anAudioFile(let player): player.pause()
        case .anAsset(let player, _): player.pause()
        }
    }

    func stop() {
        switch self {
        case .anAudioFile(let player): player.stop()
        // There is no stopping an `AVPlayer`, and nothing needs one: this is called as the player is let go of, and pausing is what stops the sound.
        case .anAsset(let player, _): player.pause()
        }
    }

    /// Exactly, in both cases — a recording scrubbed to a place must start there and not at the nearest key frame.
    func seek(to time: TimeInterval) {
        switch self {
        case .anAudioFile(let player): player.currentTime = time
        case .anAsset(let player, _): player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    func setRate(_ rate: Float) {
        switch self {
        case .anAudioFile(let player):
            player.rate = rate
        case .anAsset(let player, _):
            // The speed the next `play()` will use, which is the whole reason this is not simply written to `rate`: writing a non-zero `rate` to an `AVPlayer`
            // starts it. A reader changing the speed of a paused recording would have set it going.
            player.defaultRate = rate
            if player.rate != 0 {
                player.rate = rate
            }
        }
    }

}
