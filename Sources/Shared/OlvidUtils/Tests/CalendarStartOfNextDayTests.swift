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

import Testing
import Foundation
@testable import OlvidUtils


/// Tests for `Calendar.startOfNextDay(after:)`, the wake-up date used by `ObvCurrentDayMonitor` to refresh every
/// timestamp the app displays.
///
/// Every test pins both the calendar and the time zone, so none of them depends on the machine running them. The
/// daylight saving time cases are the point of the exercise: the implementation this replaced derived its wake-up date
/// with `now.addingTimeInterval(86400)`, which lands on the wrong day whenever a day does not last 24 hours, and
/// returned an instant *in the past* on a fall-back day.
struct CalendarStartOfNextDayTests {

    // MARK: - Helpers

    private static func calendar(in timeZoneIdentifier: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: timeZoneIdentifier))
        return calendar
    }


    /// Parses `"yyyy-MM-dd HH:mm:ss ZZZ"`. The explicit UTC offset matters: on a fall-back night the same wall clock
    /// time occurs twice, and the offset is what says which of the two is meant.
    private static func date(_ string: String, in timeZoneIdentifier: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZ"
        return try #require(formatter.date(from: string), "Could not parse \(string)")
    }


    // MARK: - Known day boundaries, including both daylight saving time transitions

    struct DayBoundaryCase: Sendable, CustomStringConvertible {
        let timeZone: String
        let now: String
        let expectedStartOfNextDay: String
        /// The length of the wait the monitor derives from `startOfNextDay(after:)`.
        let expectedSecondsUntilStartOfNextDay: TimeInterval
        let comment: String
        var description: String { "\(timeZone) \(now) — \(comment)" }
    }

    static let dayBoundaryCases: [DayBoundaryCase] = [
        .init(timeZone: "Europe/Paris",
              now: "2026-07-26 14:03:11 +0200",
              expectedStartOfNextDay: "2026-07-27 00:00:00 +0200",
              expectedSecondsUntilStartOfNextDay: 35809,
              comment: "an ordinary 24 hour day"),
        .init(timeZone: "Europe/Paris",
              now: "2026-10-25 00:30:00 +0200",
              expectedStartOfNextDay: "2026-10-26 00:00:00 +0100",
              expectedSecondsUntilStartOfNextDay: 88200, // 24.5 hours: this day lasts 25
              comment: "early on a 25 hour fall-back day, where +86400s stays on the same day"),
        .init(timeZone: "Europe/Paris",
              now: "2026-10-25 02:30:30 +0100",
              expectedStartOfNextDay: "2026-10-26 00:00:00 +0100",
              expectedSecondsUntilStartOfNextDay: 77370,
              comment: "the second pass through the repeated 02:00-03:00 hour"),
        .init(timeZone: "Europe/Paris",
              now: "2026-03-29 00:30:00 +0100",
              expectedStartOfNextDay: "2026-03-30 00:00:00 +0200",
              expectedSecondsUntilStartOfNextDay: 81000, // 22.5 hours: this day lasts 23
              comment: "early on a 23 hour spring-forward day"),
        .init(timeZone: "America/New_York",
              now: "2026-11-01 01:15:10 -0500",
              expectedStartOfNextDay: "2026-11-02 00:00:00 -0500",
              expectedSecondsUntilStartOfNextDay: 81890,
              comment: "the second pass through the repeated 01:00-02:00 hour"),
        .init(timeZone: "Pacific/Auckland",
              now: "2026-04-05 02:30:00 +1200",
              expectedStartOfNextDay: "2026-04-06 00:00:00 +1200",
              expectedSecondsUntilStartOfNextDay: 77400,
              comment: "a southern hemisphere fall-back day"),
        .init(timeZone: "UTC",
              now: "2026-12-31 23:59:59 +0000",
              expectedStartOfNextDay: "2027-01-01 00:00:00 +0000",
              expectedSecondsUntilStartOfNextDay: 1,
              comment: "one second before a year boundary"),
    ]

    @Test(arguments: dayBoundaryCases)
    func startOfNextDayIsTheFirstInstantOfTheFollowingDay(testCase: DayBoundaryCase) throws {
        let calendar = try Self.calendar(in: testCase.timeZone)
        let now = try Self.date(testCase.now, in: testCase.timeZone)
        let expected = try Self.date(testCase.expectedStartOfNextDay, in: testCase.timeZone)

        let startOfNextDay = try #require(calendar.startOfNextDay(after: now))

        #expect(startOfNextDay == expected)
        #expect(startOfNextDay.timeIntervalSince(now) == testCase.expectedSecondsUntilStartOfNextDay)
    }


    /// The regression test for the bug this replaced: on a 25 hour day, `+86400s` lands *before* `now`, and a wait
    /// derived from it would have fired immediately, over and over, for the rest of the day.
    @Test func onAFallBackDayTheOldArithmeticWentBackwardsAndTheNewOneDoesNot() throws {
        let calendar = try Self.calendar(in: "Europe/Paris")
        let now = try Self.date("2026-10-25 00:30:00 +0200", in: "Europe/Paris")

        let oldMidnight = try #require(calendar.date(bySettingHour: 0, minute: 0, second: 0, of: now.addingTimeInterval(86400)))
        #expect(oldMidnight < now)
        #expect(oldMidnight.timeIntervalSince(now) == -1800)

        let startOfNextDay = try #require(calendar.startOfNextDay(after: now))
        #expect(startOfNextDay > now)
    }


    // MARK: - Invariants, checked hour by hour across a whole year

    /// The invariants `ObvCurrentDayMonitor` relies on, over every hour of 2026 in time zones with northern, southern,
    /// half-hour and no daylight saving time. The monitor sleeps for `startOfNextDay(after: .now) - .now` without any
    /// floor, so "strictly in the future" is what keeps it from becoming a busy loop, and "at most 25 hours away" is
    /// what keeps it from skipping a day.
    @Test(arguments: ["Europe/Paris", "America/New_York", "Pacific/Auckland", "Australia/Lord_Howe", "Asia/Tokyo", "UTC"])
    func startOfNextDayIsAlwaysInTheFutureAndAtMostOneDayAway(timeZoneIdentifier: String) throws {
        let calendar = try Self.calendar(in: timeZoneIdentifier)
        var instant = try Self.date("2026-01-01 00:00:00 +0000", in: "UTC")
        let endOfYear = try Self.date("2027-01-01 00:00:00 +0000", in: "UTC")

        while instant < endOfYear {
            let startOfNextDay = try #require(calendar.startOfNextDay(after: instant),
                                             "No start of next day for \(instant) in \(timeZoneIdentifier)")
            let seconds = startOfNextDay.timeIntervalSince(instant)

            #expect(seconds > 0, "Wait would not be in the future at \(instant) in \(timeZoneIdentifier)")
            // The longest day on earth lasts 25 hours, so a longer wait would mean a whole day was skipped.
            #expect(seconds <= 25 * 3600, "Wait of \(seconds)s skips a day at \(instant) in \(timeZoneIdentifier)")
            #expect(!calendar.isDate(startOfNextDay, inSameDayAs: instant),
                    "Start of next day is still the same day at \(instant) in \(timeZoneIdentifier)")

            instant.addTimeInterval(3600)
        }
    }


    /// Waiting until the start of the next day is only useful if nothing is left of the current one: no instant may sit
    /// between the result and the day it starts.
    @Test(arguments: ["Europe/Paris", "America/New_York", "Pacific/Auckland", "UTC"])
    func startOfNextDayIsItsOwnStartOfDay(timeZoneIdentifier: String) throws {
        let calendar = try Self.calendar(in: timeZoneIdentifier)
        var instant = try Self.date("2026-01-01 00:00:00 +0000", in: "UTC")
        let endOfYear = try Self.date("2027-01-01 00:00:00 +0000", in: "UTC")

        while instant < endOfYear {
            let startOfNextDay = try #require(calendar.startOfNextDay(after: instant))
            #expect(calendar.startOfDay(for: startOfNextDay) == startOfNextDay,
                    "\(startOfNextDay) is not the first instant of its day in \(timeZoneIdentifier)")
            instant.addTimeInterval(3600)
        }
    }

}
