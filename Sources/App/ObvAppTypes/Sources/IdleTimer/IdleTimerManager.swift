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

import UIKit
import OSLog
import ObvAppCoreConstants


/// This singleton centralizes all requests to keep the screen awake. It is the single writer of the two system mechanisms that achieve it: the app
/// idle timer, which prevents an iOS device from dimming its screen, and a `ProcessInfo` activity, which prevents a Mac display from sleeping and its
/// screen saver from starting. Both are always derived from the set of current requests, never written from a call site.
@MainActor
public final class IdleTimerManager {

    public static let shared = IdleTimerManager()

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "IdleTimerManager")

    /// The name shown next to our power assertion by `pmset -g assertions`.
    private static let activityReason = "Olvid keeps the display awake"

    private init() {}

    private var reasonForDisableIdleTimerRequest = [UUID: Reason]()

    /// The token of the activity preventing the display from sleeping. Non nil iff at least one request asks for it.
    private var currentActivity: NSObjectProtocol?


    /// Why the screen must stay awake. The reason decides which of the two system mechanisms a request drives, and whether
    /// ``forceEnableIdleTimer()`` may drop it.
    public enum Reason: Sendable, CustomStringConvertible {

        /// The local user is looking at the screen because of what she is doing right now, such as recording an audio message or waiting for the app
        /// to finish initializing. The screen must stay awake on an iOS device and on a Mac alike. Such a request lasts as long as that activity, and is
        /// dropped when the user's activity changes.
        case currentUserActivity

        /// A call is in progress. On a Mac, the display must not sleep for the whole duration of the call, audio-only calls included, and the request
        /// must survive a change of the user's current activity. Under iOS, an audio call is expected to let the screen turn off, so this request does
        /// nothing there.
        case callInProgress

        /// Video is shown during a call, either our own camera preview or a remote participant's. The screen must stay lit under iOS too.
        case videoIsShownDuringCall

        /// A long task runs that the user is asked to wait for with the app open, such as a history transfer or a drain of the inbox. The screen must stay
        /// lit under iOS, where locking the device would suspend the task, and the request must survive a change of the user's current activity. A Mac
        /// display may sleep, which does not suspend the task.
        case longRunningTask

        /// `true` if the request must prevent an iOS device from dimming its screen. Without effect under macOS, which has no idle timer.
        fileprivate var preventsScreenDimming: Bool {
            switch self {
            case .currentUserActivity, .videoIsShownDuringCall, .longRunningTask: return true
            case .callInProgress: return false
            }
        }

        /// `true` if the request must prevent a Mac display from sleeping and its screen saver from starting. Without effect under iOS.
        fileprivate var preventsDisplaySleep: Bool {
            switch self {
            case .currentUserActivity, .callInProgress, .videoIsShownDuringCall: return true
            case .longRunningTask: return false
            }
        }

        /// `true` if ``IdleTimerManager/forceEnableIdleTimer()`` may drop this request.
        fileprivate var isTiedToTheCurrentUserActivity: Bool {
            switch self {
            case .currentUserActivity: return true
            case .callInProgress, .videoIsShownDuringCall, .longRunningTask: return false
            }
        }

        public var description: String {
            switch self {
            case .currentUserActivity: return "currentUserActivity"
            case .callInProgress: return "callInProgress"
            case .videoIsShownDuringCall: return "videoIsShownDuringCall"
            case .longRunningTask: return "longRunningTask"
            }
        }

    }


    /// Requests this manager to keep the screen awake, for the given reason.
    /// - Returns: A request `UUID` that can be used in the ``enableIdleTimer(disableRequestIdentifier:)`` method.
    public func disableIdleTimer(reason: Reason) -> UUID {
        assert(Thread.isMainThread)
        let requestIdentifier = UUID()
        reasonForDisableIdleTimerRequest[requestIdentifier] = reason
        Self.logger.info("Screen awake request added for reason \(reason.description, privacy: .public). \(self.reasonForDisableIdleTimerRequest.count) request(s) are now active.")
        applyCurrentRequests()
        return requestIdentifier
    }


    /// Releases one of the requests made during a call to ``disableIdleTimer(reason:)``.
    /// - Parameter disableRequestIdentifier: A request `UUID` as received during the call to ``disableIdleTimer(reason:)``.
    ///
    /// The screen is only allowed to dim or to sleep again if no other request is active.
    public func enableIdleTimer(disableRequestIdentifier: UUID) {
        assert(Thread.isMainThread)
        guard let reason = reasonForDisableIdleTimerRequest.removeValue(forKey: disableRequestIdentifier) else { return }
        Self.logger.info("Screen awake request released for reason \(reason.description, privacy: .public). \(self.reasonForDisableIdleTimerRequest.count) request(s) remain.")
        applyCurrentRequests()
    }


    /// Drops all the requests tied to what the user is currently doing. Requests that are independent of the user's current activity, such as the one
    /// made for an ongoing call, are kept: a call outlives the screen the user happens to be looking at.
    public func forceEnableIdleTimer() {
        assert(Thread.isMainThread)
        reasonForDisableIdleTimerRequest = reasonForDisableIdleTimerRequest.filter { !$0.value.isTiedToTheCurrentUserActivity }
        applyCurrentRequests()
    }


    /// The single place where the two system mechanisms are written, both derived from the set of active requests.
    private func applyCurrentRequests() {

        let reasons = reasonForDisableIdleTimerRequest.values

        // Under iOS, this keeps the screen lit. Under macOS, setting this property does nothing at all.

        UIApplication.shared.isIdleTimerDisabled = reasons.contains(where: { $0.preventsScreenDimming })

        // Under macOS, this activity takes a PreventUserIdleDisplaySleep power assertion, which is what keeps the display awake and the screen saver
        // from starting. It is only begun on a Mac, so that an audio call cannot keep an iOS screen lit whatever iOS does with the options of an
        // activity. A single activity is held for the whole set of requests, since the assertion is process-wide and taking it twice achieves nothing.

        let displaySleepMustBePrevented = ProcessInfo.processInfo.isMacCatalystApp && reasons.contains(where: { $0.preventsDisplaySleep })

        switch (displaySleepMustBePrevented, currentActivity) {
        case (true, nil):
            currentActivity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled], reason: Self.activityReason)
            Self.logger.notice("Did begin the activity preventing the display from sleeping.")
        case (false, .some(let activity)):
            // We nil the token before ending the activity, so that a re-entrant evaluation cannot end it twice.
            currentActivity = nil
            ProcessInfo.processInfo.endActivity(activity)
            Self.logger.notice("Did end the activity preventing the display from sleeping.")
        case (true, .some), (false, nil):
            break
        }

    }

}
