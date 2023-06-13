/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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


// MARK: - Generic
extension Date {
    var isToday: Bool { Calendar.current.isDateInToday(self)}
    
    var isThisWeek: Bool { Calendar.current.isDateInThisWeek(self) }

    var isThisYear: Bool { Calendar.current.isDateInThisYear(self) }
}


// MARK: - Content specific
public extension Date {
    @available(iOS 15.0, *)
    var discussionCellFormat: String {
        if isToday {
            return self.formatted(date: .omitted, time: .shortened) // 10:00
        } else if self.isThisWeek {
            return self.formatted(.dateTime.weekday(.abbreviated)) // Tue
        } else if self.isThisYear {
            return self.formatted(.dateTime.day().month(.defaultDigits)) // 09/11
        } else {
            return self.formatted(.dateTime.day().month(.defaultDigits).year(.twoDigits)) // 09/11/20
        }
    }
}
