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


/// Publishes the first instant of the current calendar day, and yields a new one each time that day changes.
///
/// A date formatted by ``Foundation/Date/discussionCellFormat(relativeTo:)`` is *fixed*, so the string it produces can
/// only change when the local calendar day changes: a message shown as `11:57` becomes `Tue`, then `09/11`, then
/// `09/11/25`. Formatting relative to ``startOfCurrentDay``, and recomputing when it changes, is therefore all it takes
/// to keep such a timestamp fresh. Since this monitor is shared, one wake-up per day serves every timestamp the app
/// displays, however many there are and on however many surfaces.
///
/// All the logic worth testing lives in `Calendar.startOfNextDay(after:)`. This type only turns it into a stream, so it
/// is deliberately thin.
@MainActor
public final class ObvCurrentDayMonitor {

    public static let shared = ObvCurrentDayMonitor()

    /// The first instant of the current calendar day. Changes once per day, and whenever a time zone or system clock
    /// change moves us to another day. Read it to format a date; iterate ``startOfCurrentDayStream()`` to be told when
    /// it changed.
    public private(set) var startOfCurrentDay: Date

    private var continuationForStreamUUID = [UUID: AsyncStream<Date>.Continuation]()
    private var waitForNextDayTask: Task<Void, Never>?
    private var notificationTokens = [NSObjectProtocol]()

    private init() {
        self.startOfCurrentDay = Calendar.current.startOfDay(for: .now)
        observeNotificationsThatMayChangeTheCurrentDay()
        waitForNextDay()
    }


    /// Yields ``startOfCurrentDay`` right away, then a new value at each day change.
    ///
    /// The first value is yielded immediately so that a consumer can seed itself from the stream alone. A consumer that
    /// already has an up-to-date value, and only cares about later changes, can skip it with `dropFirst()`. The stream
    /// ends when its consumer stops iterating; there is no need to unregister explicitly.
    public func startOfCurrentDayStream() -> AsyncStream<Date> {
        let streamUUID = UUID()
        return AsyncStream(Date.self) { continuation in
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.continuationForStreamUUID.removeValue(forKey: streamUUID)
                }
            }
            continuationForStreamUUID[streamUUID] = continuation
            continuation.yield(startOfCurrentDay)
        }
    }


    /// The system posts these when the calendar day, the time zone, or the clock changes. Each of them can move us to
    /// another day, and each of them invalidates the wake-up date computed by ``waitForNextDay()``. Time zone changes
    /// matter as much as the day timer does here: crossing a time zone by car is exactly when CarPlay is in use.
    private func observeNotificationsThatMayChangeTheCurrentDay() {
        let names: [Notification.Name] = [
            .NSCalendarDayChanged,
            .NSSystemTimeZoneDidChange,
            .NSSystemClockDidChange,
        ]
        for name in names {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.refreshStartOfCurrentDay()
                    self.waitForNextDay() // The date we were waiting for may no longer be the next start of day
                }
            }
            notificationTokens.append(token)
        }
    }


    /// Sleeps until the start of the next calendar day, yields it, and starts over.
    private func waitForNextDay() {
        waitForNextDayTask?.cancel()
        waitForNextDayTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(seconds: Self.secondsUntilStartOfNextDay())
                } catch {
                    return // The task was cancelled
                }
                guard let self else { return }
                self.refreshStartOfCurrentDay()
            }
        }
    }


    /// Yielding an unchanged value would make every consumer redraw for nothing, and a system clock change can fire
    /// without changing the day.
    private func refreshStartOfCurrentDay() {
        let newStartOfCurrentDay = Calendar.current.startOfDay(for: .now)
        guard newStartOfCurrentDay != startOfCurrentDay else { return }
        startOfCurrentDay = newStartOfCurrentDay
        for continuation in continuationForStreamUUID.values {
            continuation.yield(newStartOfCurrentDay)
        }
    }


    private static func secondsUntilStartOfNextDay() -> TimeInterval {
        let now = Date.now
        // `startOfNextDay(after:)` is always strictly greater than `now`, so the value returned below is always > 0:
        // waiting for the next day can never turn into a busy loop.
        guard let startOfNextDay = Calendar.current.startOfNextDay(after: now) else {
            assertionFailure()
            return 3600 // Should never happen. Retry within an hour rather than never refreshing again.
        }
        return startOfNextDay.timeIntervalSince(now)
    }

}
