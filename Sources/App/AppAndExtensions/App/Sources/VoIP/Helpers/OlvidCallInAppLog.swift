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
import CallKit
import WebRTC
import OlvidUtils


/// The lines a call writes to the in-app logs (Settings > Advanced), so that a call that connected without audio can be read on the phone itself.
///
/// Call audio starts only once CallKit has activated the audio session and WebRTC has been allowed to start its audio unit. The lines written here
/// follow that chain: the time spent inside a CallKit action, the audio session configuration, the activation callbacks, the state of the shared
/// `RTCAudioSession` at each step, and the state transitions of the call.
enum OlvidCallInAppLog {

    /// Each line carries the first eight characters of the call's CallKit identifier, so that two calls in the same day's file do not mix.
    /// Lines written where no call is known carry a dash.
    static func log(call uuidForCallKit: UUID?, _ message: String) {
        let prefix = uuidForCallKit.map({ String($0.uuidString.prefix(8)) }) ?? "-"
        ObvDisplayableLogs.shared.log("☎️ [\(prefix)] \(message)")
    }


    /// What the shared WebRTC audio session believes, and the route the system reports. Reading these properties takes no configuration lock.
    static func audioSessionSnapshot() -> String {
        let session = RTCAudioSession.sharedInstance()
        let inputs = session.currentRoute.inputs.map({ $0.portType.rawValue }).joined(separator: "+")
        let outputs = session.currentRoute.outputs.map({ $0.portType.rawValue }).joined(separator: "+")
        return "audio session: active=\(session.isActive) manualAudio=\(session.useManualAudio) audioEnabled=\(session.isAudioEnabled) category=\(session.category) mode=\(session.mode) options=\(session.categoryOptions.rawValue) inputAvailable=\(session.inputAvailable) otherAudioPlaying=\(session.session.isOtherAudioPlaying) route=\(inputs.isEmpty ? "none" : inputs)->\(outputs.isEmpty ? "none" : outputs)"
    }


    static func seconds(_ interval: TimeInterval) -> String {
        return String(format: "%.2fs", interval)
    }


    @MainActor
    private static let callObserver = CXCallObserver()


    /// The calls CallKit knows on this device, cellular calls and calls of other apps included.
    @MainActor
    static func callKitCalls() -> String {
        let calls = callObserver.calls
        guard !calls.isEmpty else { return "CallKit calls: none" }
        let descriptions = calls.map { call in
            "\(call.uuid.uuidString.prefix(8)) \(call.isOutgoing ? "outgoing" : "incoming") connected=\(call.hasConnected) ended=\(call.hasEnded) held=\(call.isOnHold)"
        }
        return "CallKit calls: \(descriptions.joined(separator: ", "))"
    }


    static func description(of reason: CXCallEndedReason) -> String {
        switch reason {
        case .failed: return "failed"
        case .remoteEnded: return "remote ended"
        case .unanswered: return "unanswered"
        case .answeredElsewhere: return "answered elsewhere"
        case .declinedElsewhere: return "declined elsewhere"
        @unknown default: return "raw \(reason.rawValue)"
        }
    }

}


/// Forwards WebRTC's own audio lines to the in-app logs while a call exists.
///
/// The shipped framework prints nothing by itself in a release build. Its audio lines are the only view on whether the audio unit was
/// initialized and started, and on whether an interruption is holding it back. At info severity WebRTC also logs several ICE lines per second,
/// so only the lines about audio and interruptions are kept.
///
/// `RTCCallbackLogger` is not thread safe and must not be started twice, hence the lock.
final class OlvidCallWebRTCLogForwarder {

    private let callbackLogger = RTCCallbackLogger()
    private let lock = NSLock()
    private var isStarted = false

    init() {
        callbackLogger.severity = .info
    }


    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !isStarted else { return }
        isStarted = true
        // The handler runs on the WebRTC thread that logs. Handing the string to the in-app log is all it does there.
        callbackLogger.start { message in
            let line = message.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercased = line.lowercased()
            guard lowercased.contains("audio") || lowercased.contains("interrupt") else { return }
            ObvDisplayableLogs.shared.log("☎️ [webrtc] \(line)")
        }
    }


    func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard isStarted else { return }
        isStarted = false
        callbackLogger.stop()
    }

}


/// Writes the system's audio session interruptions and route changes to the in-app logs, with their reason, and the loss and reset of the media services.
///
/// An interruption that begins and never ends stops WebRTC's audio unit for good. One that begins with the "app was suspended" reason explains a
/// stale interruption flag on the shared `RTCAudioSession`. A reset of the media services leaves the process with an audio session it must configure
/// again. All three are invisible without these lines.
final class OlvidCallAudioSessionEventsObserver {

    private var tokens = [NSObjectProtocol]()

    init() {
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: AVAudioSession.mediaServicesWereLostNotification, object: nil, queue: nil) { _ in
            OlvidCallInAppLog.log(call: nil, "media services were lost; \(OlvidCallInAppLog.audioSessionSnapshot())")
        })
        tokens.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { _ in
            OlvidCallInAppLog.log(call: nil, "media services were reset; \(OlvidCallInAppLog.audioSessionSnapshot())")
        })
        tokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { notification in
            let userInfo = notification.userInfo ?? [:]
            let type = (userInfo[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let reason = (userInfo[AVAudioSessionInterruptionReasonKey] as? UInt).flatMap(AVAudioSession.InterruptionReason.init(rawValue:))
            let options = (userInfo[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init(rawValue:))
            let typeName: String
            switch type {
            case .began: typeName = "began"
            case .ended: typeName = "ended"
            default: typeName = "unknown"
            }
            let reasonName: String
            switch reason {
            case .default: reasonName = "default"
            case .appWasSuspended: reasonName = "app was suspended"
            case .builtInMicMuted: reasonName = "built-in mic muted"
            default:
                if #available(iOS 17.0, *), reason == .routeDisconnected {
                    reasonName = "route disconnected"
                } else {
                    reasonName = reason.map({ "raw \($0.rawValue)" }) ?? "none"
                }
            }
            let shouldResume = options?.contains(.shouldResume) ?? false
            OlvidCallInAppLog.log(call: nil, "system audio session interruption \(typeName), reason: \(reasonName), shouldResume=\(shouldResume); \(OlvidCallInAppLog.audioSessionSnapshot())")
        })
        tokens.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { notification in
            let userInfo = notification.userInfo ?? [:]
            let reason = (userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            let reasonName: String
            switch reason {
            case .newDeviceAvailable: reasonName = "new device available"
            case .oldDeviceUnavailable: reasonName = "old device unavailable"
            case .categoryChange: reasonName = "category change"
            case .override: reasonName = "override"
            case .wakeFromSleep: reasonName = "wake from sleep"
            case .noSuitableRouteForCategory: reasonName = "no suitable route for category"
            case .routeConfigurationChange: reasonName = "route configuration change"
            default: reasonName = reason.map({ "raw \($0.rawValue)" }) ?? "unknown"
            }
            OlvidCallInAppLog.log(call: nil, "system audio route change, reason: \(reasonName); \(OlvidCallInAppLog.audioSessionSnapshot())")
        })
    }


    deinit {
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

}
