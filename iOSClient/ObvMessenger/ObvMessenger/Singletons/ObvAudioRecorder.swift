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

protocol ObvAudioRecorderDelegate: AnyObject {

    func recordingHasFailed()

}

final class ObvAudioRecorder: NSObject, AVAudioRecorderDelegate {

    public static let shared: ObvAudioRecorder = ObvAudioRecorder()

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: ObvAudioRecorder.self))

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

    func startRecording(url: URL, settings: [String: Int],
                        completionHandler: @escaping (Result<Void, StartRecordingError>) -> Void) {
        guard !isRecording else {
            completionHandler(.failure(.recordingInProgress))
            return
        }
        do {
            try recordingSession.setCategory(.playAndRecord, mode: .default)
            try recordingSession.setActive(true)
            recordingSession.requestRecordPermission() { granted in
                guard granted else {
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
                self.audioRecorder?.record()
                completionHandler(.success(()))
            }
        } catch(let error) {
            completionHandler(.failure(.audioSessionError(error)))
        }
    }

    enum StopRecordingError: Error {
        case noRecordingsInProgress
    }

    func stopRecording(completionHandler: @escaping (Result<URL, StopRecordingError>) -> Void) {
        guard isRecording else {
            completionHandler(.failure(.noRecordingsInProgress))
            return
        }
        guard let audioRecorder = audioRecorder else { assertionFailure(); return }

        let url = audioRecorder.url
        audioRecorder.stop()
        self.audioRecorder = nil

        completionHandler(.success(url))
    }

    func cancelRecording() {
        guard isRecording else { return }
        guard let audioRecorder = audioRecorder else { assertionFailure(); return }
        audioRecorder.stop()
        if FileManager.default.fileExists(atPath: audioRecorder.url.path) {
            audioRecorder.deleteRecording()
        }
        self.audioRecorder = nil
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        guard error != nil else { return }
        delegate?.recordingHasFailed()
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully: Bool) {
        guard !successfully else { return }
        delegate?.recordingHasFailed()
    }


}
