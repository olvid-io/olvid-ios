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
import AVFoundation
import ObvSystemIcon


/// Represents an audio option made available to the user when tapping the audio button in the in-house user interface.
struct OlvidCallAudioOption: Identifiable, Equatable {
    
    enum Identifier: Hashable {
        case builtInSpeaker
        case notBuiltInSpeaker(uid: String)
    }
    
    let id: Identifier
    let portDescription: AVAudioSessionPortDescription? // Nil for the built-in speaker
    let portType: AVAudioSession.Port
    let portName: String
    
    enum IconKind {
        case sf(_: SystemIcon)
        case png(_: String)
    }
    

    var icon: IconKind {
        switch portType {
        case .builtInMic:
            return .sf(.speakerWave3Fill)
        case .headsetMic:
            return .sf(.headphones)
        case .airPlay:
            return .sf(.airplayaudio)
        case .bluetoothA2DP:
            return .png("bluetooth")
        case .bluetoothLE: 
            return .png("bluetooth")
        case .bluetoothHFP:
            return iconKindForBluetooth()
        case .builtInSpeaker:
            return .sf(.speakerWave3Fill)
        case .builtInReceiver:
            return .sf(.mic)
        case .builtInSpeaker:
            return .sf(.speakerWave3Fill)
        case .HDMI:
            return .sf(.display)
        case .headphones: 
            return .sf(.headphones)
        case .usbAudio:
            if self.portName.lowercased().contains("Studio Display".lowercased()) {
                return .sf(.display)
            } else {
                return .sf(.waveform)
            }
        default:
            if portType.rawValue == "Bluetooth" {
                return iconKindForBluetooth()
            } else {
                return .sf(.speakerWave3Fill)
            }
        }
    }
    
    private func iconKindForBluetooth() -> IconKind {
        if self.portName.lowercased().contains("AirPods M".lowercased()) {
            return .sf(.airpodsmax)
        } else if self.portName.lowercased().contains("AirPods Pro".lowercased()) {
            return .sf(.airpodspro)
        } else if self.portName.lowercased().contains("AirPods".lowercased()) {
            return .sf(.airpods)
        } else {
            return .png("bluetooth")
        }
    }
    
    
    private init(id: Identifier, portDescription: AVAudioSessionPortDescription?, portType: AVAudioSession.Port, portName: String) {
        self.id = id
        self.portDescription = portDescription
        self.portType = portType
        self.portName = portName
    }
    
    /// Initializes an `OlvidCallAudioOption` from an `AVAudioSessionPortDescription`. This is typically used when listing all available audio inputs.
    init(portDescription: AVAudioSessionPortDescription) {
        self.init(id: .notBuiltInSpeaker(uid: portDescription.uid),
                  portDescription: portDescription,
                  portType: portDescription.portType,
                  portName: portDescription.portName)
    }
    
    
    /// Returns the `OlvidCallAudioOption` appropriate for the built-in speaker
    static func builtInSpeaker() -> OlvidCallAudioOption {
        .init(id: .builtInSpeaker,
              portDescription: nil,
              portType: .builtInSpeaker,
              portName: NSLocalizedString("BUILT_IN_SPEAKER", comment: ""))
    }
    
    
    /// Only used for SwiftUI previews
    static func forPreviews(portType: AVAudioSession.Port, portName: String) -> OlvidCallAudioOption {
        .init(id: .notBuiltInSpeaker(uid: UUID().uuidString),
              portDescription: nil,
              portType: portType,
              portName: portName)
    }
    
}
