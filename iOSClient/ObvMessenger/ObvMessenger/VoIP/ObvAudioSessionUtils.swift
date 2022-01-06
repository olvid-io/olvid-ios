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
import WebRTC

enum AudioInputIcon {
    case sf(_: String)
    case png(_: String)
}

struct AudioInput {
    let label: String
    let isCurrent: Bool
    fileprivate let activate0: () -> Void
    let icon: AudioInputIcon
    let isSpeaker: Bool

    init(label: String, isCurrent: Bool, activate0: @escaping () -> Void, icon: AudioInputIcon, isSpeaker: Bool) {
        self.label = label
        self.isCurrent = isCurrent
        self.activate0 = activate0
        self.icon = icon
        self.isSpeaker = isSpeaker
    }

    /// For testing purpose
    init(label: String, isCurrent: Bool, icon: AudioInputIcon, isSpeaker: Bool) {
        self.init(label: label, isCurrent: isCurrent, activate0: {}, icon: icon, isSpeaker: isSpeaker)
    }

    func activate() {
        activate0()
        ObvMessengerInternalNotification.audioInputHasBeenActivated(
            label: label,
            activate: activate0).postOnDispatchQueue()
    }
}

extension AudioInput {

    @available(iOS 13.0, *)
    var toAction: UIAction {
        let state: UIMenuElement.State = isCurrent ? .on : .off
        let image: UIImage?
        switch icon {
        case .sf(let systemName):
            image = UIImage(systemName: systemName)
        case .png(let name):
            image = UIImage(named: name)?.withTintColor(UIColor.label)
        }
        return UIAction(title: label, image: image, identifier: nil, discoverabilityTitle: nil, state: state) { action in
            activate()
        }
    }
}

final class ObvAudioSessionUtils {

    @Atomic() static private(set) var shared = ObvAudioSessionUtils()

    private init() {}
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: ObvAudioSessionUtils.self))
        
    private let rtcAudioSession = RTCAudioSession.sharedInstance()
    private var audioSession: AVAudioSession { rtcAudioSession.session }
    
    func configureAudioSessionForMakingOrAnsweringCall() throws {
        os_log("☎️🎵 Configure audio session", log: log, type: .info)
        try audioSession.setCategory(.playAndRecord)
        try audioSession.setMode(.voiceChat)
    }

    func getAllInputs() -> [AudioInput] {
        let log = self.log
        var inputs: [AudioInput] = []
        let currentRoute = audioSession.currentRoute
        func isSpeakerCurrent() -> Bool {
            return currentRoute.outputs.contains(where: { $0.isSpeaker })
        }
        if let availableInputs = audioSession.availableInputs {
            for input in availableInputs {
                let label = input.portName
                let activate = {
                    let audioSession = AVAudioSession.sharedInstance()
                    if isSpeakerCurrent() {
                        do {
                            try audioSession.overrideOutputAudioPort(.none)
                            os_log("☎️🎵 Speaker was disabled", log: log, type: .info)
                        } catch {
                            os_log("☎️🎵 Could not disable speaker: %{public}@", log: log, type: .info, error.localizedDescription)
                        }
                    }
                    try? audioSession.setPreferredInput(input)
                }
                var isCurrent = currentRoute.inputs.contains(where: {$0.portType == input.portType})
                if isCurrent, input.portType == .builtInMic {
                    /// Special case, we do not want to have both .builtInMic and speaker checked
                    /// we deselect manually builtInMic if the speaker is enabled.
                    isCurrent = !isSpeakerCurrent()
                }
                let icon = getAudioIcon(input: input)
                inputs.append(AudioInput(label: label, isCurrent: isCurrent, activate0: activate, icon: icon, isSpeaker: false))
            }
        }
        do {
            let label = CommonString.Word.Speaker
            let activate = {
                if !isSpeakerCurrent() {
                    do {
                        // This also switch back the input to the Built-In Microphone
                        let audioSession = AVAudioSession.sharedInstance()
                        try audioSession.overrideOutputAudioPort(.speaker)
                        os_log("☎️🎵 Speaker was enabled", log: log, type: .info)
                    } catch {
                        os_log("☎️🎵 Could not enable speaker: %{public}@", log: log, type: .info, error.localizedDescription)
                    }
                }
            }
            inputs.append(AudioInput(label: label, isCurrent: isSpeakerCurrent(), activate0: activate, icon: .sf("speaker.3.fill"), isSpeaker: true))
        }
        return inputs
    }

    func getCurrentAudioInput() -> AudioInput? {
        let allInputs = getAllInputs()
        return allInputs.first { $0.isCurrent }
    }


    private func getAudioIcon(input: AVAudioSessionPortDescription) -> AudioInputIcon {
        switch input.portType {
        case .builtInMic: return .sf("iphone")
        case .headsetMic: return .sf("headphones")
        case .lineIn: return .sf("rectangle.dock")
        case .airPlay: return .sf("airplayaudio")
        case .bluetoothA2DP: return .png("bluetooth")
        case .bluetoothLE: return .png("bluetooth")
        case .bluetoothHFP: return .png("bluetooth")
        case .builtInReceiver: return .sf("iphone")
        case .builtInSpeaker: return .sf("speaker.3.fill")
        case .HDMI: return .sf("display")
        case .headphones: return .sf("headphones")
        case .lineOut: return .sf("rectangle.dock")
        default: assertionFailure()
        }
        return .sf("speaker.1.fill")
    }

}


fileprivate extension AVAudioSessionPortDescription {
    var isSpeaker: Bool {
        return portType == AVAudioSession.Port.builtInSpeaker
    }
}

extension AVAudioSession.RouteChangeReason: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknown: return "unknown"
        case .newDeviceAvailable: return "newDeviceAvailable"
        case .oldDeviceUnavailable: return "oldDeviceUnavailable"
        case .categoryChange: return "categoryChange"
        case .override: return "override"
        case .wakeFromSleep: return "wakeFromSleep"
        case .noSuitableRouteForCategory: return "noSuitableRouteForCategory"
        case .routeConfigurationChange: return "routeConfigurationChange"
        @unknown default: return "@unknown"
        }
    }

}
