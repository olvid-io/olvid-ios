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
import WebRTC
import ObvSettings
import os.log
import OlvidUtils
import ObvAppCoreConstants


final class ConfigureAudioSessionOperation: OperationWithSpecificReasonForCancel<ConfigureAudioSessionOperation.ReasonForCancel>, @unchecked Sendable {

    private static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "ConfigureAudioSessionOperation")

    private static var dateOfLastConfiguration: Date?
    
    override func main() {
        
        os_log("☎️🎵 [WebRTCOperation][ConfigureAudioSessionOperation] Start", log: Self.log, type: .info)
        defer { os_log("☎️🎵 [WebRTCOperation][ConfigureAudioSessionOperation] Finish", log: Self.log, type: .info) }

        do {

            // See also https://stackoverflow.com/questions/49170274/callkit-loudspeaker-bug-how-whatsapp-fixed-it/49466250#49466250
            // See also https://developer.apple.com/forums/thread/64544#189703
            // See also https://stackoverflow.com/questions/48023629/abnormal-behavior-of-speaker-button-on-system-provided-call-screen?rq=1
            
            let rtcAudioSession = RTCAudioSession.sharedInstance()
            
            rtcAudioSession.lockForConfiguration()
            defer { rtcAudioSession.unlockForConfiguration() }
            
//            try rtcAudioSession.setCategory(.playAndRecord, mode: .voiceChat)
            try rtcAudioSession.setCategory(.playAndRecord, mode: .videoChat)

            
            let configuration = RTCAudioSessionConfiguration.webRTC()
            configuration.categoryOptions = [.allowBluetooth, .allowBluetoothA2DP, .duckOthers]
            try rtcAudioSession.setConfiguration(configuration)
            
            if ObvUICoreDataConstants.useCallKit {
                rtcAudioSession.useManualAudio = true
            } else {
                rtcAudioSession.useManualAudio = false
                if !ObvMessengerConstants.isRunningOnRealDevice {
                    try rtcAudioSession.setActive(true)
                }
                //rtcAudioSession.audioSessionDidActivate(rtcAudioSession.session)
            }
            
            try rtcAudioSession.overrideOutputAudioPort(.none)

            Self.dateOfLastConfiguration = Date.now
            
        } catch {
            if let date = Self.dateOfLastConfiguration, abs(date.timeIntervalSinceNow) < 1 {
                assertionFailure("\(error.localizedDescription) - This happens when answering an incoming call while another Olvid call was in progress. In practice, it seems to work.")
            }
            return cancel(withReason: .configureAudioSessionFailed(error: error))
        }
        
    }
    
    
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        case configureAudioSessionFailed(error: Error)
        var logType: OSLogType {
            return .fault
        }
    }
    
}
