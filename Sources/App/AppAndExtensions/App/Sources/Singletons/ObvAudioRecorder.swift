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
import os.log
import ObvAppCoreConstants

protocol ObvAudioRecorderDelegate: AnyObject {

    func recordingHasFailed()

}

final class ObvAudioRecorder: NSObject, AVAudioRecorderDelegate, ObservableObject {

    public static let shared: ObvAudioRecorder = ObvAudioRecorder()

    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: ObvAudioRecorder.self))

    private var recordDurationDispatchTimer: DispatchSourceTimer?
    
    let recordingSession: AVAudioSession = AVAudioSession.sharedInstance()
    var audioRecorder: AVAudioRecorder? {
        didSet {
            if audioRecorder == nil {
                if let disableIdleTimerRequestIdentifier = self.disableIdleTimerRequestIdentifier {
                    DispatchQueue.main.async {
                        IdleTimerManager.shared.enableIdleTimer(disableRequestIdentifier: disableIdleTimerRequestIdentifier)
                    }
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.disableIdleTimerRequestIdentifier = IdleTimerManager.shared.disableIdleTimer()
                }
            }
        }
    }
    private var disableIdleTimerRequestIdentifier: UUID?

    weak var delegate: ObvAudioRecorderDelegate?

    override init() {}

    var isRecording: Bool { audioRecorder?.isRecording ?? false }
    
    @Published var currentDuration: TimeInterval = 0.0
    
    private var minPower: Float = -60
    private var maxPower: Float = 0
    
    @Published var liveWaveformSamples: [Float] = []
    
    var duration: TimeInterval? {
        guard isRecording else { return nil }
        return audioRecorder?.currentTime
    }

    enum StartRecordingError: Error {
        case recordingInProgress
        case noRecordPermission
        case audioSessionError(_: Error)
        case audioRecorderError(_: Error)
    }

    func updateWaveFormSamples() {
        guard let recorder = audioRecorder else { return }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        
        // Met à jour des extrêmes observés
        minPower = min(minPower * 0.97 + power * 0.03, minPower)
        maxPower = max(maxPower * 0.97 + power * 0.03, maxPower)
        
        // Normalise dynamiquement
        let normalized = normalize(power)
        liveWaveformSamples.append(normalized)
    }
    
    private func normalize(_ value: Float) -> Float {
        guard maxPower > minPower else { return 0 }
        let normalized = (value - minPower) / (maxPower - minPower)
        return max(0, min(1, normalized))
    }
    
    func startRecording(url: URL, settings: [String: Int],
                        completionHandler: @escaping (Result<Void, StartRecordingError>) -> Void) {
        guard !isRecording else {
            completionHandler(.failure(.recordingInProgress))
            return
        }
        do {
            try recordingSession.setCategory(.record, mode: .default)
            try recordingSession.setActive(true)
            liveWaveformSamples.removeAll()
            
            recordingSession.requestRecordPermission() { [weak self] granted in
                guard let self, granted else {
                    completionHandler(.failure(.noRecordPermission))
                    return
                }
                do {
                    self.audioRecorder = try AVAudioRecorder(url: url, settings: settings)
                } catch(let error) {
                    completionHandler(.failure(.audioRecorderError(error)))
                }
                self.audioRecorder?.delegate = self
                os_log("🎤 Start Recording in %{public}@", log: self.log, type: .info, url.absoluteString)
                self.audioRecorder?.isMeteringEnabled = true
                self.audioRecorder?.record()
                completionHandler(.success(()))
                
                // Use DispatchSourceTimer for reliable scheduling on Mac Catalyst and across run loop modes
                let timer = DispatchSource.makeTimerSource(queue: .main)
                timer.schedule(deadline: .now() + .milliseconds(30), repeating: .milliseconds(30))
                self.recordDurationDispatchTimer = timer

                timer.setEventHandler { [weak self] in
                    guard let self = self else { return }
                    assert(Thread.isMainThread)
                    guard self.isRecording else {
                        self.recordDurationDispatchTimer?.cancel()
                        self.recordDurationDispatchTimer = nil
                        return
                    }
                    self.currentDuration = self.duration ?? 0.0
                    self.updateWaveFormSamples()
                }

                timer.resume()
            }
        } catch(let error) {
            completionHandler(.failure(.audioSessionError(error)))
        }
    }

    enum StopRecordingError: Error {
        case noRecordingsInProgress
        case noAudioRecorderAvailable
    }

    //func stopRecording(completionHandler: @escaping (Result<URL, StopRecordingError>) -> Void) {
    func stopRecording() throws(StopRecordingError) -> URL {
        guard isRecording else {
            throw .noRecordingsInProgress
        }
        guard let audioRecorder = audioRecorder else {
            assertionFailure()
            throw .noAudioRecorderAvailable
        }

        let url = audioRecorder.url
        audioRecorder.stop()
        self.audioRecorder = nil

        // Invalidate timers
        self.recordDurationDispatchTimer?.cancel()
        self.recordDurationDispatchTimer = nil

        return url
    }

    func cancelRecording() {
        guard isRecording else { return }
        guard let audioRecorder = audioRecorder else { assertionFailure(); return }
        audioRecorder.stop()
        if FileManager.default.fileExists(atPath: audioRecorder.url.path) {
            audioRecorder.deleteRecording()
        }
        self.audioRecorder = nil

        // Invalidate timers
        self.recordDurationDispatchTimer?.cancel()
        self.recordDurationDispatchTimer = nil
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        guard error != nil else { return }
        delegate?.recordingHasFailed()
        // Invalidate timers on failure
        self.recordDurationDispatchTimer?.cancel()
        self.recordDurationDispatchTimer = nil
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully: Bool) {
        guard !successfully else { return }
        delegate?.recordingHasFailed()
        // Invalidate timers on failure
        self.recordDurationDispatchTimer?.cancel()
        self.recordDurationDispatchTimer = nil
    }


}
