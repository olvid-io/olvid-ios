/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvAppCoreConstants


extension Sound {
    var isPlayable: Bool { filename != nil }
}


@MainActor
public final class SoundsPlayer<S: Sound>: NSObject {

    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: SoundsPlayer.self))
    private var currentAudioPlayer: AVAudioPlayer?
    private var soundCurrentlyPlaying: S?
    private let obvAVAudioPlayerDelegate = ObvAVAudioPlayerDelegate()

    private lazy var feedbackGenerator: UINotificationFeedbackGenerator = {
        UINotificationFeedbackGenerator()
    }()

    private func createPlayerIfNeeded(sound: S, note: Note?) throws {
        guard let filename = sound.filename else { assertionFailure(); return }
        let filenameSplit = filename.split(separator: ".")
        let filenameBase: String
        let filenameExtension: String
        switch filenameSplit.count {
        case 1:
            filenameBase = String(filenameSplit[0])
            filenameExtension = "caf"
        case 2:
            filenameBase = String(filenameSplit[0])
            filenameExtension = String(filenameSplit[1])
        default:
            assertionFailure()
            throw ObvError.fileDoesNotExist
        }
        let soundURL: URL
        if let note = note {
            guard let url = Bundle.module.url(forResource: filenameBase + note.index, withExtension: filenameExtension) else {
                assertionFailure()
                throw ObvError.fileDoesNotExist
            }
            soundURL = url
        } else {
            guard let url = Bundle.module.url(forResource: filenameBase, withExtension: filenameExtension) else {
                assertionFailure()
                throw ObvError.fileDoesNotExist
            }
            soundURL = url
        }
        guard FileManager.default.fileExists(atPath: soundURL.path) else {
            os_log("🎵 Could not find audio file at path: %{public}@", log: log, type: .fault, filename, soundURL.path)
            assertionFailure()
            throw ObvError.fileDoesNotExist
        }
        let player = try AVAudioPlayer(contentsOf: soundURL)
        player.numberOfLoops = sound.loops ? Int.max : 0
        self.currentAudioPlayer = player
    }

    public func play(sound: S, note: Note? = nil, category: AVAudioSession.Category?) {
        assert(Thread.isMainThread)
        guard sound.isPlayable else { return }
        self.internalStopCurrentSound()
        guard let filename = sound.filename else { assertionFailure(); return }
        do {
            try createPlayerIfNeeded(sound: sound, note: note)
        } catch(let error) {
            os_log("🎵 Could not initialize audio player for sound %{public}@: %{public}@", log: log, type: .fault, filename, error.localizedDescription)
            assertionFailure()
            return
        }
        if let category = category {
            do {
                obvAVAudioPlayerDelegate.setCategoryToRestore(to: AVAudioSession.sharedInstance().category)
                try AVAudioSession.sharedInstance().setCategory(category, mode: .default, options: [])
            } catch let error {
                os_log("🎵 Error in AVAudioSession %{public}@", log: self.log, type: .info, error.localizedDescription)
            }
        }
        guard let currentAudioPlayer else { return }
        os_log("🎵 Play %{public}@", log: self.log, type: .info, filename)
        currentAudioPlayer.currentTime = 0
        currentAudioPlayer.delegate = self.obvAVAudioPlayerDelegate
        self.soundCurrentlyPlaying = sound
        currentAudioPlayer.play()
        if let feedback = sound.feedback {
            self.feedbackGenerator.notificationOccurred(feedback)
        }
    }

    private func internalStopCurrentSound() {
        if let sound = self.soundCurrentlyPlaying {
            guard let filename = sound.filename else { assertionFailure(); return }
            os_log("🎵 Stop %{public}@", log: self.log, type: .info, filename)
            self.currentAudioPlayer?.stop()
            self.currentAudioPlayer = nil
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

    
    enum ObvError: Error {
        case fileDoesNotExist
    }
    
}


// MARK: - Private AVAudioPlayerDelegate

private final class ObvAVAudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    
    private let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: "SoundsPlayer"))
    private var categoryToRestore: AVAudioSession.Category?
    
    fileprivate func setCategoryToRestore(to newCategoryToRestore: AVAudioSession.Category?) {
        self.categoryToRestore = newCategoryToRestore
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard let categoryToRestore = self.categoryToRestore else { return }
        defer { self.categoryToRestore = nil }
        do {
            try AVAudioSession.sharedInstance().setCategory(categoryToRestore, mode: .default, options: [])
        } catch {
            assertionFailure()
            logger.fault("Could not restore the previous share audio session category: \(error.localizedDescription)")
            assertionFailure()
        }
    }
    
}
