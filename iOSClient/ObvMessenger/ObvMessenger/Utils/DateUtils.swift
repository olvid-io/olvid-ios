/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

final class DurationFormatter {
    
    let formatter: DateComponentsFormatter

    var unitsStyle: DateComponentsFormatter.UnitsStyle {
        get { formatter.unitsStyle }
        set { formatter.unitsStyle = newValue }
    }
    
    var maximumUnitCount: Int {
        get { formatter.maximumUnitCount }
        set { formatter.maximumUnitCount = newValue }
    }
    
    init() {
        self.formatter = DateComponentsFormatter()
        formatter.allowedUnits = [ .second, .minute, .hour, .day, .month, .year ]
        formatter.zeroFormattingBehavior = [ .dropAll ]
        self.unitsStyle = .abbreviated
        self.maximumUnitCount = 1
    }
    
    func string(from ti: TimeInterval) -> String? {
        if self.maximumUnitCount == 1 {
            chooseMostAppropriateAllowedUnit(for: ti)
        } else {
            formatter.allowedUnits = [ .second, .minute, .hour, .day, .month, .year ]
        }
        return formatter.string(from: ti)
    }
    
    
    /// This method makes sure the value returned from the `string(from:TimeInterval)` rounds the time interval
    /// down, instead of "to the nearest value".
    private func chooseMostAppropriateAllowedUnit(for ti: TimeInterval) {
        if ti > DurationTransition.oneYear {
            formatter.allowedUnits = [ .year ]
        } else if ti > DurationTransition.oneMonth {
            formatter.allowedUnits = [ .month ]
        } else if ti > DurationTransition.oneDay {
            formatter.allowedUnits = [ .day ]
        } else if ti > DurationTransition.oneHour {
            formatter.allowedUnits = [ .hour ]
        } else if ti > DurationTransition.oneMinute {
            formatter.allowedUnits = [ .minute ]
        } else {
            formatter.allowedUnits = [ .second ]
        }
    }
    
    
    struct DurationTransition {
        static let oneYear: TimeInterval = 31_536_000
        static let oneMonth: TimeInterval = 2_678_400
        static let oneDay: TimeInterval = 86_400
        static let oneHour: TimeInterval = 3_600
        static let oneMinute: TimeInterval = 60
    }
    
}


// MARK: - Notifying on change

extension TimeInterval {

    static func optionalMin(_ val1: TimeInterval?, _ val2: TimeInterval?) -> TimeInterval? {
        switch (val1, val2) {
        case (.none, .none):
            return nil
        case (.some(let val), .none):
            return val
        case (.none, .some(let val)):
            return val
        case (.some(let v1), .some(let v2)):
            return min(v1, v2)
        }
    }

}

extension Date {

    @available(iOS 13.0, *)
    var relativeFormatted: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) || calendar.isDateInYesterday(self) {
            let formatter = RelativeDateTimeFormatter()
            formatter.dateTimeStyle = .named
            return formatter.localizedString(for: self, relativeTo: Date())
        } else {
            if #available(iOS 15.0, *) {
                var dateStyle: Date.FormatStyle = .dateTime
                    .weekday(.wide)
                    .month()
                    .day()
                if calendar.component(.year, from: self) != calendar.component(.year, from: Date()) {
                    dateStyle = dateStyle.year()
                }
                return self.formatted(dateStyle)
            } else {
                let df = DateFormatter()
                df.doesRelativeDateFormatting = true
                df.dateStyle = .short
                df.timeStyle = .medium
                df.locale = Locale.current
                return df.string(from: self)
            }
        }
    }

}
