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


extension Date {

    public var relativeFormatted: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) || calendar.isDateInYesterday(self) {
            let formatter = RelativeDateTimeFormatter()
            formatter.dateTimeStyle = .named
            return formatter.localizedString(for: self, relativeTo: Date())
        } else {
            var dateStyle: Date.FormatStyle = .dateTime
                .weekday(.wide)
                .month()
                .day()
            if calendar.component(.year, from: self) != calendar.component(.year, from: Date()) {
                dateStyle = dateStyle.year()
            }
            return self.formatted(dateStyle)
        }
    }

}
