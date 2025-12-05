/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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

public extension Date {

    /// The interval in milliseconds between the date value and 00:00:00 UTC on 1 January 1970.
    var epochInMs: Int64 { Int64(timeIntervalSince1970 * 1000) }

    /// Returns a `Date` initialized relative to 00:00:00 UTC on 1 January 1970 by a given number of milliseconds.
    init(epochInMs: Int64) {
        self.init(timeIntervalSince1970: Double(epochInMs) / 1000)
    }

    static func obvMax(date1: Date?, date2: Date?) -> Date? {
        switch (date1, date2) {
            case (.none, .none):
            return nil
        case (.none, .some):
            return date2
        case (.some, .none):
            return date1
        case (.some(let d1), .some(let d2)):
            return d1 > d2 ? d1 : d2
        }
    }
    
}
