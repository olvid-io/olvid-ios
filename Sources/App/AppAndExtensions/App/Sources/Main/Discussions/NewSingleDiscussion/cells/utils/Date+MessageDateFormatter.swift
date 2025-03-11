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
    
    
    func formattedForOlvidMessage(specificMonthFormat: Date.FormatStyle.Symbol.Month? = nil) -> String {
        return self.formatted(self.formatStyleForOlvidMessage(specificMonthFormat: specificMonthFormat))
    }
        
}


extension Calendar {
    
    func isDateInPastSevenDays(_ date: Date) -> Bool {
        for dayIncrement in 0..<7 {
            if Calendar.current.isDateInToday(date.advanced(by: .init(days: dayIncrement))) {
                return true
            }
        }
        return false
    }
    
}
