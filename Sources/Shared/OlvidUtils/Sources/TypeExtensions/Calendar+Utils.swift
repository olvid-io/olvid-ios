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

/// Week and year counterparts of Foundation's `Calendar.isDate(_:inSameDayAs:)`. Like it, they take the reference date
/// explicitly: comparing against an implicit `Date()` makes the result silently depend on the current time, which
/// callers then have no way to observe, and tests no way to control.
extension Calendar {

    func isDate(_ date: Date, inSameWeekAs referenceDate: Date) -> Bool {
        return isDate(date, equalTo: referenceDate, toGranularity: .weekOfYear)
    }

    func isDate(_ date: Date, inSameYearAs referenceDate: Date) -> Bool {
        return isDate(date, equalTo: referenceDate, toGranularity: .year)
    }

    /// The first instant of the calendar day that follows the one containing `date`. Always strictly greater than
    /// `date`, which makes it a safe wake-up date for anything that must refresh at each day change.
    ///
    /// Adding one *calendar* day to the start of the current day, instead of adding 86400 seconds, is what makes this
    /// correct across daylight saving time changes: a fall-back day lasts 25 hours and a spring-forward day 23, so
    /// `Date.addingTimeInterval(86400)` lands on the wrong day on both. On the rare days where midnight itself does not
    /// exist, because the clocks jump forward at midnight, this returns the first instant that does exist that day.
    ///
    /// Returns `nil` only if the calendar cannot represent that instant, which does not happen with the calendars iOS
    /// exposes.
    func startOfNextDay(after date: Date) -> Date? {
        guard let startOfNextDay = self.date(byAdding: .day, value: 1, to: startOfDay(for: date)) else { return nil }
        guard startOfNextDay > date else { assertionFailure(); return nil }
        return startOfNextDay
    }

}
