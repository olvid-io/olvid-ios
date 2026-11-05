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


/// Turns a number of seconds into something a reader can read — "2 min", "3 h", "5 d" — in their own language.
///
/// **Moved here from the app target on 2026-08-13**, unchanged, because three places now need it and they are in
/// different targets. The app has always used it, for a tap-to-read bubble and a system message among others; the
/// SwiftUI discussion screen needs it for the countdown on an ephemeral message, which is Step 24b and cannot be
/// served the way the same screen serves a *system* message. That one is handed a string the app formatted once,
/// which works because the duration of a shared setting does not change. A countdown changes every second, so
/// whoever draws it has to format it, and the alternative to sharing this was a second implementation of "2 min"
/// that would drift from this one.
///
/// **It rounds down, deliberately** — see ``chooseMostAppropriateAllowedUnit(for:)``. A `DateComponentsFormatter`
/// left to itself rounds to the nearest value, so a message with 59 minutes left would say "1 h" and appear to gain
/// time.
public final class DurationFormatter {
    
    public let formatter: DateComponentsFormatter

    public var unitsStyle: DateComponentsFormatter.UnitsStyle {
        get { formatter.unitsStyle }
        set { formatter.unitsStyle = newValue }
    }
    
    public var maximumUnitCount: Int {
        get { formatter.maximumUnitCount }
        set { formatter.maximumUnitCount = newValue }
    }
    
    public init() {
        self.formatter = DateComponentsFormatter()
        formatter.allowedUnits = [ .second, .minute, .hour, .day, .month, .year ]
        formatter.zeroFormattingBehavior = [ .dropAll ]
        self.unitsStyle = .abbreviated
        self.maximumUnitCount = 1
    }
    
    public func string(from ti: TimeInterval) -> String? {
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
    
    
    public struct DurationTransition {
        public static let oneYear: TimeInterval = 31_536_000
        public static let oneMonth: TimeInterval = 2_678_400
        public static let oneDay: TimeInterval = 86_400
        public static let oneHour: TimeInterval = 3_600
        public static let oneMinute: TimeInterval = 60
    }
    
}
