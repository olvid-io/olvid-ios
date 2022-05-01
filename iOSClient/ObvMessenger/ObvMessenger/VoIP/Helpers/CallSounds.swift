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
import UIKit

@MainActor
final class CallSounds {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: CallSounds.self))
    private var allAudioPlayers = [SoundType: AVAudioPlayer]()
    private var soundCurrentlyPlaying: SoundType?
    
    static private(set) var shared = CallSounds()

    private var feedbackGenerator: UINotificationFeedbackGenerator = UINotificationFeedbackGenerator()
            
    /// This initializer creates all `AVAudioPlayer` so as to be as responsive as possible when asked to play any of the available sounds.
    private init() {
        for type in SoundType.allCases {
            do {
                allAudioPlayers[type] = try type.makeAudioPlayer()
            } catch {
                assertionFailure()
                os_log("Could not initialize audio player for sound %{public}@", log: log, type: .fault, type.filename)
                // We continue anyway
            }
        }
    }
    
    enum SoundType: CaseIterable {
        
        case ringing
        case connect
        case disconnect
        
        fileprivate var filename: String {
            switch self {
            case .ringing: return "ringing.mp3"
            case .connect: return "connect.mp3"
            case .disconnect: return "disconnect.mp3"
            }
        }
        
        private var loops: Bool {
            switch self {
            case .ringing:
                return true
            case .connect, .disconnect:
                return false
            }
        }
        
        fileprivate func makeAudioPlayer() throws -> AVAudioPlayer {
            let soundURL = Bundle.main.bundleURL.appendingPathComponent(self.filename)
            let player = try AVAudioPlayer(contentsOf: soundURL)
            player.numberOfLoops = self.loops ? Int.max : 0
            return player
        }

        fileprivate var feedback: UINotificationFeedbackGenerator.FeedbackType? {
            switch self {
            case .ringing:
                return nil
            case .connect:
                return .success
            case .disconnect:
                return .error
            }
        }

    }
    
    
    func play(sound type: SoundType) {
        assert(Thread.isMainThread)
        os_log("☎️🎵 Play %{public}@", log: self.log, type: .info, type.filename)
        self.internalStopCurrentSound()
        self.allAudioPlayers[type]?.currentTime = 0
        self.allAudioPlayers[type]?.play()
        self.soundCurrentlyPlaying = type
        if let feedback = type.feedback {
            self.feedbackGenerator.notificationOccurred(feedback)
        }
    }

    private func internalStopCurrentSound() {
        if let type = self.soundCurrentlyPlaying {
            os_log("☎️🎵 Stop %{public}@", log: self.log, type: .info, type.filename)
            self.allAudioPlayers[type]?.stop()
            self.soundCurrentlyPlaying = nil
        }
    }
    
    func stopCurrentSound() {
        assert(Thread.isMainThread)
        self.internalStopCurrentSound()
    }

    func prepareFeedback() {
        assert(Thread.isMainThread)
        self.feedbackGenerator.prepare()
    }

}
