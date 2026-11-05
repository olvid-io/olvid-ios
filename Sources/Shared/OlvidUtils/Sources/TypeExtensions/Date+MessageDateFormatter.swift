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

    private func formatStyleForOlvidMessage(specificMonthFormat: Date.FormatStyle.Symbol.Month?) -> FormatStyle {
        
        let hourAndMinute = Date.FormatStyle()
            .hour()
            .minute()

        if Calendar.current.isDateInToday(self) {
           return hourAndMinute
        }
        
        if Calendar.current.isDateInPastSevenDays(self) {
            return hourAndMinute
                .weekday(.wide)
        }
        
        if Calendar.current.isDate(self, equalTo: Date.now, toGranularity: .year) {
            return hourAndMinute
                .weekday()
                .day()
                .month(specificMonthFormat ?? .wide)
        }
        
        return hourAndMinute
            .weekday()
            .day()
            .month(specificMonthFormat ?? .abbreviated)
            .year()

    }
    
    
    /// The way a discussion shows the date of one of its messages, relative to now:
    /// - today: the time, e.g. `10:00`
    /// - within the past seven days: the weekday and the time, e.g. `Tuesday 10:00`
    /// - earlier in the current year: the weekday, the day, the month and the time, e.g. `Tue 9 November 10:00`
    /// - older: the same, with an abbreviated month and the year
    ///
    /// This is *not* ``discussionCellFormat``, which is how the discussions **list** shows the date of the latest message of a discussion, and which
    /// drops the time as soon as a message is older than today.
    ///
    /// Note that the returned string goes stale when the day changes: a message sent today at 23:59 shows as `23:59`, and should show as
    /// `Tuesday 23:59` once past midnight. A caller that must keep it up to date can observe `ObvCurrentDayMonitor`, as the discussions list does.
    func formattedForOlvidMessage(specificMonthFormat: Date.FormatStyle.Symbol.Month? = nil) -> String {
        return self.formatted(self.formatStyleForOlvidMessage(specificMonthFormat: specificMonthFormat))
    }

}


fileprivate extension Calendar {

    func isDateInPastSevenDays(_ date: Date) -> Bool {
        for dayIncrement in 0..<7 {
            if Calendar.current.isDateInToday(date.advanced(by: .init(days: dayIncrement))) {
                return true
            }
        }
        return false
    }
    
}
