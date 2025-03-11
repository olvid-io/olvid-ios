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
import AVFAudio
import os.log
import ObvAppCoreConstants


/// Very simple player used instead of the ``SoundsPlayer`` for performance reasons under macOS.
/// We tested several solutions for playing call sounds (including the system sounds framework and the AVAudioEngine APIs) and came up with this solution that uses
/// the `AVAudioPlayer` API. Although not perferct (sometimes, play/pause hang for a long time under macOS), it has the advantage of not blocking the main thread and does not crash
/// (unlike some of the tests we made with AVAudioEngine, that does not seem to be very resilient during audio interrupts, which often happen during an audio call).
final class OlvidCallAudioPlayer: NSObject, AVAudioPlayerDelegate {

    private static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "OlvidCallAudioPlayer")

    private let internalQueue = OperationQueue.createSerialQueue(name: "OlvidCallAudioPlayer internal queue")

    private var currentPlayer: AVAudioPlayer?
    private var currentSound: Sound?
    private let feedbackGenerator = UINotificationFeedbackGenerator()

    func play(_ sound: Sound) {
        let scheduledTime = Date.now
        internalQueue.addOperation { [weak self] in
            
            guard let self else { return }
            
            currentPlayer?.stop()
            currentPlayer = nil
            currentSound = nil
            
            guard abs(Date.now.timeIntervalSince(scheduledTime)) < 1 else {
                return
            }

            currentPlayer = try? AVAudioPlayer(contentsOf: sound.url)
            currentSound = sound
            currentPlayer?.delegate = self
            
            currentPlayer?.play()

            if let feedback = sound.feedback {
                DispatchQueue.main.async { [weak self] in
                    self?.feedbackGenerator.notificationOccurred(feedback)
                }
            }
                        
        }
    }
    
    
    func stop() {
        internalQueue.addOperation { [weak self] in
            guard let self else { return }
            currentPlayer?.stop()
            currentPlayer = nil
            currentSound = nil
        }
    }
    
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        internalQueue.addOperation { [weak self] in
            
            guard let self else { return }

            if let currentSound, currentSound.doesLoop == true {
                // Note that
                play(currentSound)
            }
            
            currentPlayer?.stop()
            currentPlayer = nil
            currentSound = nil
            
        }
    }

    
    enum Sound: CaseIterable {
        
        case connect
        case disconnect
        case reconnecting
        case ringing
        
        private var filename: String {
            switch self {
            case .connect: return "connect.mp3"
            case .disconnect: return "disconnect.mp3"
            case .reconnecting: return "reconnecting.mp3"
            case .ringing: return "ringing.mp3"
            }
        }

        fileprivate var url: URL {
            if ObvMessengerConstants.targetEnvironmentIsMacCatalyst {
                return Bundle.main.bundleURL
                    .appendingPathComponent("Contents")
                    .appendingPathComponent("Resources")
                    .appendingPathComponent(filename)
                    .resolvingSymlinksInPath()
            } else {
                return Bundle.main.bundleURL.appendingPathComponent(filename)
            }
        }
        
        fileprivate var avAudioFile: AVAudioFile {
            get throws {
                try .init(forReading: url)
            }
        }

        
        fileprivate var doesLoop: Bool {
            switch self {
            case .ringing:
                return true
            case .connect, .disconnect, .reconnecting:
                return false
            }
        }
        

        fileprivate var feedback: UINotificationFeedbackGenerator.FeedbackType? {
            switch self {
            case .ringing:
                return nil
            case .connect:
                return .success
            case .disconnect, .reconnecting:
                return .error
            }
        }

    }


    enum ObvError: Error {
        case failedToCreateAVAudioPCMBuffer
    }
    
}
