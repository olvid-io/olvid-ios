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
    
    static func getUptime() -> TimeInterval {
        var uptime = timespec()
        if clock_gettime(CLOCK_MONOTONIC_RAW, &uptime) != 0 {
            return 0
        }
        return TimeInterval(uptime.tv_sec)
    }
    
}
