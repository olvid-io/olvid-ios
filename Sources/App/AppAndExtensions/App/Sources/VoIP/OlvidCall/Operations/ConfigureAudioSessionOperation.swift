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
import WebRTC
import ObvSettings
import os.log
import OlvidUtils
import ObvAppCoreConstants


final class ConfigureAudioSessionOperation: OperationWithSpecificReasonForCancel<ConfigureAudioSessionOperation.ReasonForCancel>, @unchecked Sendable {

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "ConfigureAudioSessionOperation")

    private static var dateOfLastConfiguration: Date?

    /// The call this configuration is for, used to prefix the in-app log lines.
    private let uuidForCallKit: UUID

    init(uuidForCallKit: UUID) {
        self.uuidForCallKit = uuidForCallKit
        super.init()
    }

    override func main() {

        Self.logger.info("☎️🎵 [WebRTCOperation][ConfigureAudioSessionOperation] Start")
        defer { Self.logger.info("☎️🎵 [WebRTCOperation][ConfigureAudioSessionOperation] Finish") }

        // Names the call that threw, for the in-app log line written on failure.
        var step = "lock"

        do {

            // See also https://stackoverflow.com/questions/49170274/callkit-loudspeaker-bug-how-whatsapp-fixed-it/49466250#49466250
            // See also https://developer.apple.com/forums/thread/64544#189703
            // See also https://stackoverflow.com/questions/48023629/abnormal-behavior-of-speaker-button-on-system-provided-call-screen?rq=1

            let rtcAudioSession = RTCAudioSession.sharedInstance()

            rtcAudioSession.lockForConfiguration()
            defer { rtcAudioSession.unlockForConfiguration() }

//            try rtcAudioSession.setCategory(.playAndRecord, mode: .voiceChat)
            step = "setCategory"
            try rtcAudioSession.setCategory(.playAndRecord, mode: .videoChat)


            let configuration = RTCAudioSessionConfiguration.webRTC()
            configuration.categoryOptions = [.allowBluetoothHFP, .allowBluetoothA2DP, .duckOthers]
            step = "setConfiguration"
            try rtcAudioSession.setConfiguration(configuration)

            if ObvUICoreDataConstants.useCallKit {
                rtcAudioSession.useManualAudio = true
            } else {
                rtcAudioSession.useManualAudio = false
                if !ObvMessengerConstants.isRunningOnRealDevice {
                    step = "setActive"
                    try rtcAudioSession.setActive(true)
                }
                //rtcAudioSession.audioSessionDidActivate(rtcAudioSession.session)
            }

            step = "overrideOutputAudioPort"
            try rtcAudioSession.overrideOutputAudioPort(.none)

            Self.dateOfLastConfiguration = Date.now

            OlvidCallInAppLog.log(call: uuidForCallKit, "audio session configured; \(OlvidCallInAppLog.audioSessionSnapshot())")

        } catch {
            OlvidCallInAppLog.log(call: uuidForCallKit, "audio session configuration failed at \(step): \(error.localizedDescription); \(OlvidCallInAppLog.audioSessionSnapshot())")
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
