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


// MARK: - Content specific
public extension Date {

    /// The way the discussions list shows the date of the latest message of a discussion, relative to now:
    /// - today: the time, e.g. `10:00`
    /// - earlier in the current calendar week: the abbreviated weekday, e.g. `Tue`
    /// - earlier in the current year: the day and the month, e.g. `09/11`
    /// - older: the day, the month, and a two-digit year, e.g. `09/11/20`
    ///
    /// Note that there is no "Yesterday" format: a message received yesterday shows as `Tue`, unless yesterday fell in
    /// the previous calendar week, in which case it shows as `09/11`.
    var discussionCellFormat: String {
        discussionCellFormat(relativeTo: .now)
    }

    /// Same as ``discussionCellFormat``, but relative to an explicit reference date.
    ///
    /// The returned string only depends on the *calendar day* of `referenceDate`. A caller that must keep it up to date
    /// can therefore pass `ObvCurrentDayMonitor.shared.startOfCurrentDay` and recompute whenever it changes, which is
    /// both the cheapest possible refresh and a dependency the caller can observe.
    func discussionCellFormat(relativeTo referenceDate: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(self, inSameDayAs: referenceDate) {
            return self.formatted(date: .omitted, time: .shortened) // 10:00
        } else if calendar.isDate(self, inSameWeekAs: referenceDate) {
            return self.formatted(.dateTime.weekday(.abbreviated)) // Tue
        } else if calendar.isDate(self, inSameYearAs: referenceDate) {
            return self.formatted(.dateTime.day().month(.defaultDigits)) // 09/11
        } else {
            return self.formatted(.dateTime.day().month(.defaultDigits).year(.twoDigits)) // 09/11/20
        }
    }

}
